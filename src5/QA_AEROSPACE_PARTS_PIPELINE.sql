/*=========================================================
Object Name : QA_AEROSPACE_PARTS_PIPELINE
Purpose     : QA acceptance criteria queries
Target DB   : GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD
Warehouse   : SNOWFLAKE_LEARNING_WH
SP          : SP_LOAD_AEROSPACE_PARTS_SCD1
AC Range    : AC-001 through AC-010
=========================================================*/

USE DATABASE GEN_AI_POC_SNOWFLAKECOE;
USE SCHEMA SDLC_WIZARD;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

-- ============================================================
-- AC-001: TARGET TABLE EXISTS AND IS ACCESSIBLE
-- PASS: Returns row count >= 0 with no error
-- ============================================================
SELECT
    'AC-001'                              AS acceptance_criteria,
    'TARGET TABLE EXISTS AND ACCESSIBLE'  AS description,
    COUNT(*)                              AS row_count,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET;

-- ============================================================
-- AC-002: RECONCILIATION LOG POPULATED AFTER SP RUN
-- PASS: At least one SUCCESS record exists in log
-- ============================================================
SELECT
    'AC-002'                                    AS acceptance_criteria,
    'RECONCILIATION LOG POPULATED'              AS description,
    COUNT(*)                                    AS log_entries,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM ETL_RECONCILIATION_LOG
WHERE SP_NAME = 'SP_LOAD_AEROSPACE_PARTS_SCD1'
  AND STATUS  = 'SUCCESS';

-- ============================================================
-- AC-003: MANUFACTURER IS UPPERCASED
-- PASS: No rows where MANUFACTURER differs from its UPPER() value
-- ============================================================
SELECT
    'AC-003'                                AS acceptance_criteria,
    'MANUFACTURER UPPERCASED'               AS description,
    COUNT(*)                                AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE MANUFACTURER <> UPPER(MANUFACTURER);

-- ============================================================
-- AC-004: WEIGHT_KG NULL WHEN SOURCE VALUE <= 0
-- PASS: No rows where WEIGHT_KG <= 0
-- ============================================================
SELECT
    'AC-004'                                AS acceptance_criteria,
    'WEIGHT_KG NULL FOR NON-POSITIVE VALUES' AS description,
    COUNT(*)                                AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE WEIGHT_KG <= 0;

-- ============================================================
-- AC-005: UNIT_PRICE_USD ROUNDED TO 3 DECIMAL PLACES
-- PASS: No rows where UNIT_PRICE_USD has more than 3 decimal places
-- ============================================================
SELECT
    'AC-005'                                    AS acceptance_criteria,
    'UNIT_PRICE_USD ROUNDED TO 3 DECIMALS'      AS description,
    COUNT(*)                                    AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE UNIT_PRICE_USD <> ROUND(UNIT_PRICE_USD, 3);

-- ============================================================
-- AC-006: RISK_SCORE HIGH RISK LOGIC
-- PASS: All Pending + LEAD_TIME_DAYS > 90 records = 'High Risk'
-- ============================================================
SELECT
    'AC-006'                                AS acceptance_criteria,
    'RISK_SCORE HIGH RISK LOGIC'            AS description,
    COUNT(*)                                AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE CERTIFICATION_STATUS = 'Pending'
  AND LEAD_TIME_DAYS > 90
  AND RISK_SCORE <> '