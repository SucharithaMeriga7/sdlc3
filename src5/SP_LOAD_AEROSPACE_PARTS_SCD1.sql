/*=========================================================
Object Name : SP_LOAD_AEROSPACE_PARTS_SCD1
Purpose     : Aerospace Parts SCD1 pipeline with RISK_SCORE
Author      : SDLC_AGENT
=========================================================*/
CREATE OR REPLACE PROCEDURE GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.SP_LOAD_AEROSPACE_PARTS_SCD1()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    -- SECTION 1: Variables
    v_start_ts      TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    v_run_id        VARCHAR       := UUID_STRING();
    v_last_load_ts  TIMESTAMP_NTZ;
    v_src_count     INTEGER := 0;
    v_dedup_count   INTEGER := 0;
    v_insert_count  INTEGER := 0;
    v_update_count  INTEGER := 0;
    v_delete_count  INTEGER := 0;
    v_invalid_count INTEGER := 0;
    v_tgt_before    INTEGER := 0;
    v_tgt_after     INTEGER := 0;
    v_result        VARCHAR;

BEGIN
    USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

    -- SECTION 2: Source Processing
    -- Watermark: last successful load timestamp or full load on first run
    SELECT COALESCE(MAX(DW_UPDATE_TIMESTAMP), '1900-01-01'::TIMESTAMP_NTZ)
    INTO :v_last_load_ts
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    SELECT COUNT(*) INTO :v_src_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
    WHERE UPDATED_AT > :v_last_load_ts;

    SELECT COUNT(*) INTO :v_tgt_before
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    -- Stage deduplicated + transformed source records
    CREATE TEMPORARY TABLE STAGE_PARTS AS
    SELECT
        PART_NUMBER,
        INITCAP(MANUFACTURER)                                   AS MANUFACTURER,
        NULLIF(CASE WHEN WEIGHT_KG <= 0 THEN NULL ELSE WEIGHT_KG END, NULL) AS WEIGHT_KG,
        ROUND(UNIT_PRICE_USD, 2)                                AS UNIT_PRICE_USD,
        LIFECYCLE_STATUS,
        INSTALLATION_DATE,
        CERTIFICATION_STATUS,
        LEAD_TIME_DAYS,
        UPDATED_AT,
        CASE
            WHEN CERTIFICATION_STATUS = 'Certification Pending' AND LEAD_TIME_DAYS > 90  THEN 'High Risk'
            WHEN CERTIFICATION_STATUS = 'Certification Pending' OR  LEAD_TIME_DAYS > 120 THEN 'Medium Risk'
            WHEN CERTIFICATION_STATUS IN ('FAA','EASA','Dual') AND LEAD_TIME_DAYS <= 60  THEN 'Low Risk'
            ELSE 'Medium Risk'
        END AS RISK_SCORE
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY PART_NUMBER ORDER BY UPDATED_AT DESC) AS RN
        FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
        WHERE UPDATED_AT > :v_last_load_ts
    ) t
    WHERE RN = 1;

    SELECT COUNT(*) INTO :v_dedup_count FROM STAGE_PARTS;

    -- SECTION 3: Data Validation
    -- Count and remove exclusion records: End of Life + installation older than 3 years
    CREATE TEMPORARY TABLE STAGE_VALID AS
    SELECT * FROM STAGE_PARTS
    WHERE NOT (
        LIFECYCLE_STATUS = 'End of Life'
        AND INSTALLATION_DATE < DATEADD(year, -3, CURRENT_DATE())
    );

    SELECT (:v_dedup_count - COUNT(*)) INTO :v_invalid_count FROM STAGE_VALID;

    -- SECTION 4: Merge Logic
    -- SCD1 upsert + soft delete for missing source records
    MERGE INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET tgt
    USING STAGE_VALID src
    ON tgt.PART_NUMBER = src.PART_NUMBER
    WHEN MATCHED THEN UPDATE SET
        tgt.MANUFACTURER         = src.MANUFACTURER,
        tgt.WEIGHT_KG            = src.WEIGHT_KG,
        tgt.UNIT_PRICE_USD       = src.UNIT_PRICE_USD,
        tgt.LIFECYCLE_STATUS     = src.LIFECYCLE_STATUS,
        tgt.INSTALLATION_DATE    = src.INSTALLATION_DATE,
        tgt.CERTIFICATION_STATUS = src.CERTIFICATION_STATUS,
        tgt.LEAD_TIME_DAYS       = src.LEAD_TIME_DAYS,
        tgt.RISK_SCORE           = src.RISK_SCORE,
        tgt.RECORD_STATUS        = 'Active',
        tgt.DW_UPDATE_TIMESTAMP  = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (
        PART_NUMBER, MANUFACTURER, WEIGHT_KG, UNIT_PRICE_USD,
        LIFECYCLE_STATUS, INSTALLATION_DATE, CERTIFICATION_STATUS,
        LEAD_TIME_DAYS, RISK_SCORE, RECORD_STATUS,
        DW_INSERT_TIMESTAMP, DW_UPDATE_TIMESTAMP
    ) VALUES (
        src.PART_NUMBER, src.MANUFACTURER, src.WEIGHT_KG, src.UNIT_PRICE_USD,
        src.LIFECYCLE_STATUS, src.INSTALLATION_DATE, src.CERTIFICATION_STATUS,
        src.LEAD_TIME_DAYS, src.RISK_SCORE, 'Active',
        CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
    );

    -- Capture insert/update counts via post-merge target delta
    SELECT COUNT(*) INTO :v_tgt_after
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    SET v_insert_count = :v_tgt_after - :v_tgt_before;
    SET v_update_count = :v_dedup_count - :v_invalid_count - :v_insert_count;

    -- Soft delete: mark target records absent from current source batch
    UPDATE GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET tgt
    SET tgt.RECORD_STATUS       = 'Decommissioned',
        tgt.DW_UPDATE_TIMESTAMP = CURRENT_TIMESTAMP()
    WHERE tgt.RECORD_STATUS != 'Decommissioned'
      AND NOT EXISTS (
          SELECT 1 FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_SOURCE src
          WHERE src.PART_NUMBER = tgt.PART_NUMBER
      );

    SELECT COUNT(*) INTO :v_delete_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET
    WHERE RECORD_STATUS = 'Decommissioned'
      AND DW_UPDATE_TIMESTAMP >= :v_start_ts;

    -- SECTION 5: Reconciliation
    -- Log pipeline run metrics to ETL_RECONCILIATION_LOG
    INSERT INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG (
        RUN_ID, PROCEDURE_NAME, RUN_START_TS, RUN_END_TS,
        SRC_COUNT, DEDUP_COUNT, INVALID_COUNT,
        INSERT_COUNT, UPDATE_COUNT, DELETE_COUNT,
        TGT_COUNT_BEFORE, TGT_COUNT_AFTER, STATUS
    ) VALUES (
        :v_run_id, 'SP_LOAD_AEROSPACE_PARTS_SCD1', :v_start_ts, CURRENT_TIMESTAMP(),
        :v_src_count, :v_dedup_count, :v_invalid_count,
        :v_insert_count, :v_update_count, :v_delete_count,
        :v_tgt_before, :v_tgt_after, 'SUCCESS'
    );

    -- SECTION 6: Error Handling
    v_result := OBJECT_CONSTRUCT(
        'run_id',        :v_run_id,
        'status',        'SUCCESS',
        'src_count',     :v_src_count,
        'dedup_count',   :v_dedup_count,
        'invalid_count', :v_invalid_count,
        'insert_count',  :v_insert_count,
        'update_count',  :v_update_count,
        'delete_count',  :v_delete_count,
        'tgt_before',    :v_tgt_before,
        'tgt_after',     :v_tgt_after
    )::VARCHAR;

    RETURN :v_result;

EXCEPTION WHEN OTHER THEN
    INSERT INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG (
        RUN_ID, PROCEDURE_NAME, RUN_START_TS, RUN_END_TS,
        SRC_COUNT, DEDUP_COUNT, INVALID_COUNT,
        INSERT_COUNT, UPDATE_COUNT, DELETE_COUNT,
        TGT_COUNT_BEFORE, TGT_COUNT_AFTER, STATUS
    ) VALUES (
        :v_run_id, 'SP_LOAD_AEROSPACE_PARTS_SCD1', :v_start_ts, CURRENT_TIMESTAMP(),
        :v_src_count, :v_dedup_count, :v_invalid_count,
        :v_insert_count, :v_update_count, :v_delete_count,
        :v_tgt_before, :v_tgt_after, 'FAILED: ' || SQLERRM
    );
    RETURN OBJECT_CONSTRUCT('error', SQLERRM)::VARCHAR;
END;
$$;