/*=========================================================
Object Name : QA_AEROSPACE_PARTS_PIPELINE
Purpose     : QA acceptance criteria queries AC-001 to AC-010
Database    : GEN_AI_POC_SNOWFLAKECOE
Schema      : SDLC_WIZARD
Warehouse   : SNOWFLAKE_LEARNING_WH
=========================================================*/

USE DATABASE GEN_AI_POC_SNOWFLAKECOE;
USE SCHEMA SDLC_WIZARD;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

-- ============================================================
-- AC-001 | Row Count Reconciliation
-- PASS: TARGET row count >= SOURCE distinct PART_NUMBER count
-- ============================================================
SELECT
    'AC-001' AS CRITERIA,
    'Row Count Reconciliation' AS DESCRIPTION,
    src.SRC_COUNT,
    tgt.TGT_COUNT,
    CASE WHEN tgt.TGT_COUNT >= src.SRC_COUNT THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM
    (SELECT COUNT(DISTINCT PART_NUMBER) AS SRC_COUNT FROM SDLC_WIZARD.AEROSPACE_PARTS_SOURCE) src,
    (SELECT COUNT(*)                    AS TGT_COUNT FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET) tgt;

-- ============================================================
-- AC-002 | SCD Type 1 Merge Accuracy – No Duplicate Business Keys
-- PASS: Zero duplicate PART_NUMBER rows in target
-- ============================================================
SELECT
    'AC-002'                        AS CRITERIA,
    'No Duplicate PART_NUMBER'      AS DESCRIPTION,
    COUNT(*)                        AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM (
    SELECT PART_NUMBER
    FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
    GROUP BY PART_NUMBER
    HAVING COUNT(*) > 1
) dups;

-- ============================================================
-- AC-003 | Deduplication by UPDATED_AT – Latest Record Wins
-- PASS: Target value matches the max UPDATED_AT source record
-- ============================================================
SELECT
    'AC-003'                                AS CRITERIA,
    'Latest UPDATED_AT Record Retained'     AS DESCRIPTION,
    COUNT(*)                                AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM (
    SELECT s.PART_NUMBER
    FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET t
    JOIN (
        SELECT PART_NUMBER, MAX(UPDATED_AT) AS MAX_UPDATED
        FROM SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
        GROUP BY PART_NUMBER
    ) s ON t.PART_NUMBER = s.PART_NUMBER
    WHERE t.UPDATED_AT <> s.MAX_UPDATED
) violations;

-- ============================================================
-- AC-004 | MANUFACTURER CamelCase Transformation
-- PASS: Zero rows where MANUFACTURER differs from INITCAP(source)
-- ============================================================
SELECT
    'AC-004'                            AS CRITERIA,
    'MANUFACTURER CamelCase Applied'    AS DESCRIPTION,
    COUNT(*)                            AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM (
    SELECT t.PART_NUMBER
    FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET t
    JOIN SDLC_WIZARD.AEROSPACE_PARTS_SOURCE s
      ON t.PART_NUMBER = s.PART_NUMBER
    WHERE t.MANUFACTURER <> INITCAP(s.MANUFACTURER)
) violations;

-- ============================================================
-- AC-005 | WEIGHT_KG Null Rule (<=0 set to NULL)
-- PASS: Zero rows where WEIGHT_KG <= 0 in target
-- ============================================================
SELECT
    'AC-005'                            AS CRITERIA,
    'WEIGHT_KG NULL for Zero/Negative'  AS DESCRIPTION,
    COUNT(*)                            AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
WHERE WEIGHT_KG <= 0;

-- ============================================================
-- AC-006 | UNIT_PRICE_USD Rounding to 2 Decimal Places
-- PASS: Zero rows where UNIT_PRICE_USD scale exceeds 2 decimals
-- ============================================================
SELECT
    'AC-006'                                AS CRITERIA,
    'UNIT_PRICE_USD Rounded to 2 Decimals'  AS DESCRIPTION,
    COUNT(*)                                AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
WHERE UNIT_PRICE_USD <> ROUND(UNIT_PRICE_USD, 2);

-- ============================================================
-- AC-007 | Exclusion Rule – PART_STATUS = 'Obsolete' Excluded
-- PASS: Zero rows with PART_STATUS = 'Obsolete' in target
-- ============================================================
SELECT
    'AC-007'                            AS CRITERIA,
    'Obsolete Parts Excluded'           AS DESCRIPTION,
    COUNT(*)                            AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
WHERE UPPER(PART_STATUS) = 'OBSOLETE';

-- ============================================================
-- AC-008 | RISK_SCORE Derivation Logic
-- PASS: Zero rows where RISK_SCORE does not match expected logic
-- Logic: HIGH   = LEAD_TIME_DAYS > 90 OR QUANTITY_ON_HAND < 10
--        MEDIUM = LEAD_TIME_DAYS BETWEEN 31 AND 90
--        LOW    = all others
-- ============================================================
SELECT
    'AC-008'                        AS CRITERIA,
    'RISK_SCORE Derivation Correct' AS DESCRIPTION,
    COUNT(*)                        AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM (
    SELECT PART_NUMBER, RISK_SCORE, LEAD_TIME_DAYS, QUANTITY_ON_HAND,
        CASE
            WHEN LEAD_TIME_DAYS > 90 OR QUANTITY_ON_HAND < 10 THEN 'HIGH'
            WHEN LEAD_TIME_DAYS BETWEEN 31 AND 90              THEN 'MEDIUM'
            ELSE 'LOW'
        END AS EXPECTED_RISK
    FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
) chk
WHERE RISK_SCORE <> EXPECTED_RISK;

-- ============================================================
-- AC-009 | Soft Delete – Decommissioned Parts Flagged
-- PASS: All source records with PART_STATUS='Decommissioned'
--       have RECORD_STATUS='INACTIVE' in target
-- ============================================================
SELECT
    'AC-009'                                    AS CRITERIA,
    'Decommissioned Parts Soft-Deleted'         AS DESCRIPTION,
    COUNT(*)                                    AS VIOLATION_COUNT,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM (
    SELECT t.PART_NUMBER
    FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET t
    JOIN SDLC_WIZARD.AEROSPACE_PARTS_SOURCE s
      ON t.PART_NUMBER = s.PART_NUMBER
    WHERE UPPER(s.PART_STATUS) = 'DECOMMISSIONED'
      AND t.RECORD_STATUS <> 'INACTIVE'
) violations;

-- ============================================================
-- AC-010 | ETL Reconciliation Log – Run Logged with Metrics
-- PASS: At least one log entry exists for the latest pipeline run
--       with SOURCE_COUNT, INSERT_COUNT, UPDATE_COUNT populated
-- ============================================================
SELECT
    'AC-010'                                AS CRITERIA,
    'ETL Reconciliation Log Entry Exists'   AS DESCRIPTION,
    LOG_ID,
    RUN_TIMESTAMP,
    SOURCE_COUNT,
    INSERT_COUNT,
    UPDATE_COUNT,
    DELETE_COUNT,
    STATUS,
    CASE
        WHEN SOURCE_COUNT IS NOT NULL
         AND INSERT_COUNT IS NOT NULL
         AND UPDATE_COUNT IS NOT NULL
         AND STATUS = 'SUCCESS'
        THEN 'PASS'
        ELSE 'FAIL'
    END AS QA_STATUS
FROM SDLC_WIZARD.ETL_RECONCILIATION_LOG
ORDER BY RUN_TIMESTAMP DESC
LIMIT 1;

-- ============================================================
-- SUMMARY DASHBOARD – All Criteria at a Glance
-- ============================================================
SELECT CRITERIA, DESCRIPTION, STATUS FROM (

    SELECT 'AC-001' AS CRITERIA, 'Row Count Reconciliation'           AS DESCRIPTION,
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET) >=
                  (SELECT COUNT(DISTINCT PART_NUMBER) FROM SDLC_WIZARD.AEROSPACE_PARTS_SOURCE)
             THEN 'PASS' ELSE 'FAIL' END AS STATUS

    UNION ALL SELECT 'AC-002', 'No Duplicate PART_NUMBER',
        CASE WHEN (SELECT COUNT(*) FROM (SELECT PART_NUMBER FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
                   GROUP BY PART_NUMBER HAVING COUNT(*) > 1)) = 0 THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-003', 'Latest UPDATED_AT Record Retained',
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET t
                   JOIN (SELECT PART_NUMBER, MAX(UPDATED_AT) AS MX FROM SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
                         GROUP BY PART_NUMBER) s ON t.PART_NUMBER = s.PART_NUMBER
                   WHERE t.UPDATED_AT <> s.MX) = 0 THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-004', 'MANUFACTURER CamelCase Applied',
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET t
                   JOIN SDLC_WIZARD.AEROSPACE_PARTS_SOURCE s ON t.PART_NUMBER = s.PART_NUMBER
                   WHERE t.MANUFACTURER <> INITCAP(s.MANUFACTURER)) = 0 THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-005', 'WEIGHT_KG NULL for Zero/Negative',
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET WHERE WEIGHT_KG <= 0) = 0
             THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-006', 'UNIT_PRICE_USD Rounded to 2 Decimals',
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
                   WHERE UNIT_PRICE_USD <> ROUND(UNIT_PRICE_USD, 2)) = 0 THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-007', 'Obsolete Parts Excluded',
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET
                   WHERE UPPER(PART_STATUS) = 'OBSOLETE') = 0 THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-008', 'RISK_SCORE Derivation Correct',
        CASE WHEN (SELECT COUNT(*) FROM (
                   SELECT PART_NUMBER, RISK_SCORE,
                       CASE WHEN LEAD_TIME_DAYS > 90 OR QUANTITY_ON_HAND < 10 THEN 'HIGH'
                            WHEN LEAD_TIME_DAYS BETWEEN 31 AND 90 THEN 'MEDIUM'
                            ELSE 'LOW' END AS EXP
                   FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET) x WHERE RISK_SCORE <> EXP) = 0
             THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-009', 'Decommissioned Parts Soft-Deleted',
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.AEROSPACE_PARTS_TARGET t
                   JOIN SDLC_WIZARD.AEROSPACE_PARTS_SOURCE s ON t.PART_NUMBER = s.PART_NUMBER
                   WHERE UPPER(s.PART_STATUS) = 'DECOMMISSIONED' AND t.RECORD_STATUS <> 'INACTIVE') = 0
             THEN 'PASS' ELSE 'FAIL' END

    UNION ALL SELECT 'AC-010', 'ETL Reconciliation Log Entry Exists',
        CASE WHEN (SELECT COUNT(*) FROM SDLC_WIZARD.ETL_RECONCILIATION_LOG
                   WHERE STATUS = 'SUCCESS' AND SOURCE_COUNT IS NOT NULL) > 0
             THEN 'PASS' ELSE 'FAIL' END

) SUMMARY
ORDER BY CRITERIA;