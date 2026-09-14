/*=========================================================
Object Name : QA_AEROSPACE_PARTS_PIPELINE
Purpose     : QA acceptance criteria queries
Database    : GEN_AI_POC_SNOWFLAKECOE
Schema      : SDLC_WIZARD
Warehouse   : SNOWFLAKE_LEARNING_WH
SP          : SP_LOAD_AEROSPACE_PARTS_SCD1
AC Range    : AC-001 through AC-010
=========================================================*/

USE DATABASE GEN_AI_POC_SNOWFLAKECOE;
USE SCHEMA SDLC_WIZARD;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

-- ============================================================
-- AC-001: TARGET TABLE EXISTS AND IS ACCESSIBLE
-- PASS: Returns row count >= 0 with no errors
-- ============================================================
SELECT
    'AC-001'                                AS acceptance_criteria,
    'TARGET TABLE EXISTS AND IS ACCESSIBLE' AS description,
    COUNT(*)                                AS row_count,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET;

-- ============================================================
-- AC-002: SCHEMA VALIDATION — REQUIRED COLUMNS PRESENT
-- PASS: column_count = 15
-- ============================================================
SELECT
    'AC-002'                              AS acceptance_criteria,
    'SCHEMA VALIDATION - REQUIRED COLUMNS' AS description,
    COUNT(*)                              AS column_count,
    CASE WHEN COUNT(*) = 15 THEN 'PASS' ELSE 'FAIL' END AS result
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'SDLC_WIZARD'
  AND TABLE_NAME   = 'AEROSPACE_PARTS_TARGET'
  AND COLUMN_NAME IN (
      'PART_NUMBER','PART_NAME','MANUFACTURER','CATEGORY',
      'WEIGHT_KG','UNIT_PRICE_USD','LEAD_TIME_DAYS',
      'CERTIFICATION_STATUS','LIFECYCLE_STATUS','INSTALLATION_DATE',
      'UPDATED_AT','RISK_SCORE','RECORD_STATUS',
      'DW_INSERT_TIMESTAMP','DW_UPDATE_TIMESTAMP'
  );

-- ============================================================
-- AC-003: NO DUPLICATE PART_NUMBER IN TARGET
-- PASS: duplicate_count = 0
-- ============================================================
SELECT
    'AC-003'                          AS acceptance_criteria,
    'NO DUPLICATE PART_NUMBER'        AS description,
    COUNT(*)                          AS duplicate_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT PART_NUMBER
    FROM AEROSPACE_PARTS_TARGET
    GROUP BY PART_NUMBER
    HAVING COUNT(*) > 1
);

-- ============================================================
-- AC-004: EXCLUSION FILTER — NO END OF LIFE + >3 YEARS OLD
-- PASS: excluded_count = 0
-- ============================================================
SELECT
    'AC-004'                                        AS acceptance_criteria,
    'EXCLUSION FILTER END-OF-LIFE + INSTALL >3 YRS' AS description,
    COUNT(*)                                        AS excluded_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE LIFECYCLE_STATUS = 'End of Life'
  AND INSTALLATION_DATE < DATEADD(year, -3, CURRENT_DATE());

-- ============================================================
-- AC-005: RISK_SCORE VALID VALUES ONLY
-- PASS: invalid_count = 0
-- ============================================================
SELECT
    'AC-005'                       AS acceptance_criteria,
    'RISK_SCORE VALID VALUES ONLY' AS description,
    COUNT(*)                       AS invalid_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE RISK_SCORE NOT IN ('High Risk','Medium Risk','Low Risk')
   OR RISK_SCORE IS NULL;

-- ============================================================
-- AC-006: MANUFACTURER STORED IN CAMELCASE (INITCAP)
-- PASS: non_camelcase_count = 0
-- ============================================================
SELECT
    'AC-006'                              AS acceptance_criteria,
    'MANUFACTURER IN CAMELCASE (INITCAP)' AS description,
    COUNT(*)                              AS non_camelcase_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE MANUFACTURER IS NOT NULL
  AND MANUFACTURER != INITCAP(MANUFACTURER);

-- ============================================================
-- AC-007: WEIGHT_KG NULL WHERE SOURCE VALUE WAS <= 0
-- PASS: invalid_weight_count = 0
-- ============================================================
SELECT
    'AC-007'                            AS acceptance_criteria,
    'WEIGHT_KG NULL FOR ZERO/NEG VALUES' AS description,
    COUNT(*)