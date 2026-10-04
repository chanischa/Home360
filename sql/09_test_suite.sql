-- ============================================================
-- Home360 — Phase 8: Reusable Test Suite
-- ============================================================
-- Run anytime to validate the full system.
-- Each test returns a PASS/FAIL result.
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

-- ============================================================
-- TEST 1: Table row counts
-- ============================================================
SELECT 'T1_ROW_COUNTS' AS test_id,
       CASE WHEN c = 12 AND p = 12 AND pv = 17 AND hr = 14 AND cl = 8 AND i = 8
            THEN 'PASS' ELSE 'FAIL' END AS result,
       c AS customers, p AS properties, pv AS policy_versions,
       hr AS risk_assessments, cl AS claims, i AS interactions
FROM (
    SELECT
        (SELECT COUNT(*) FROM CUSTOMER) AS c,
        (SELECT COUNT(*) FROM PROPERTY) AS p,
        (SELECT COUNT(*) FROM POLICY_VERSION) AS pv,
        (SELECT COUNT(*) FROM HOME_RISK_HISTORY) AS hr,
        (SELECT COUNT(*) FROM CLAIM) AS cl,
        (SELECT COUNT(*) FROM INTERACTION) AS i
);

-- ============================================================
-- TEST 2: V_CUSTOMER_360 — all 12 customers, no NULL core fields
-- ============================================================
SELECT 'T2_360_COMPLETENESS' AS test_id,
       CASE WHEN COUNT(*) = 12
             AND SUM(CASE WHEN tenure_years IS NULL OR payment_history IS NULL
                          OR location IS NULL OR policy_id IS NULL
                          OR current_flood_risk IS NULL THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN has_renewal_proposal THEN 1 ELSE 0 END) AS with_renewal
FROM V_CUSTOMER_360;

-- ============================================================
-- TEST 3: V_POLICY_COMPARISON — 5 renewal customers
-- ============================================================
SELECT 'T3_POLICY_COMPARISON' AS test_id,
       CASE WHEN COUNT(*) = 5
             AND SUM(CASE WHEN premium_change_pct IS NULL THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result,
       COUNT(*) AS renewal_count,
       MIN(premium_change_pct) AS min_premium_pct,
       MAX(premium_change_pct) AS max_premium_pct
FROM V_POLICY_COMPARISON;

-- ============================================================
-- TEST 4: May's policy comparison — specific values
-- ============================================================
SELECT 'T4_MAY_POLICY' AS test_id,
       CASE WHEN premium_change_pct = 18.0
             AND flood_cov_change_pct = -30.0
             AND flood_ded_change_pct = 100.0
             AND exclusions_changed = TRUE
            THEN 'PASS' ELSE 'FAIL' END AS result,
       premium_change_pct, flood_cov_change_pct, flood_ded_change_pct, exclusions_changed
FROM V_POLICY_COMPARISON
WHERE customer_id = 'C001';

-- ============================================================
-- TEST 5: V_RISK_CHANGE — 2 properties with risk changes
-- ============================================================
SELECT 'T5_RISK_CHANGE' AS test_id,
       CASE WHEN COUNT(*) = 2
             AND SUM(CASE WHEN customer_id = 'C001' AND flood_direction = 'UP' THEN 1 ELSE 0 END) = 1
             AND SUM(CASE WHEN customer_id = 'C006' AND earthquake_direction = 'UP' THEN 1 ELSE 0 END) = 1
            THEN 'PASS' ELSE 'FAIL' END AS result,
       COUNT(*) AS risk_change_count
FROM V_RISK_CHANGE;

-- ============================================================
-- TEST 6: May's risk change — specific values
-- ============================================================
SELECT 'T6_MAY_RISK' AS test_id,
       CASE WHEN prev_flood_risk = 'MEDIUM'
             AND curr_flood_risk = 'HIGH'
             AND flood_direction = 'UP'
             AND risk_score_change_pct = 85.7
             AND overall_direction = 'INCREASED'
            THEN 'PASS' ELSE 'FAIL' END AS result,
       prev_flood_risk, curr_flood_risk, risk_score_change_pct
FROM V_RISK_CHANGE
WHERE customer_id = 'C001';

-- ============================================================
-- TEST 7: Foreign key integrity — no orphans
-- ============================================================
SELECT 'T7_FK_INTEGRITY' AS test_id,
       CASE WHEN orphan_properties = 0
             AND orphan_policies = 0
             AND orphan_claims = 0
             AND orphan_interactions = 0
             AND orphan_risks = 0
            THEN 'PASS' ELSE 'FAIL' END AS result,
       orphan_properties, orphan_policies, orphan_claims,
       orphan_interactions, orphan_risks
FROM (
    SELECT
        (SELECT COUNT(*) FROM PROPERTY p WHERE NOT EXISTS (SELECT 1 FROM CUSTOMER c WHERE c.customer_id = p.customer_id)) AS orphan_properties,
        (SELECT COUNT(*) FROM POLICY_VERSION pv WHERE NOT EXISTS (SELECT 1 FROM CUSTOMER c WHERE c.customer_id = pv.customer_id)) AS orphan_policies,
        (SELECT COUNT(*) FROM CLAIM cl WHERE NOT EXISTS (SELECT 1 FROM CUSTOMER c WHERE c.customer_id = cl.customer_id)) AS orphan_claims,
        (SELECT COUNT(*) FROM INTERACTION i WHERE NOT EXISTS (SELECT 1 FROM CUSTOMER c WHERE c.customer_id = i.customer_id)) AS orphan_interactions,
        (SELECT COUNT(*) FROM HOME_RISK_HISTORY h WHERE NOT EXISTS (SELECT 1 FROM PROPERTY p WHERE p.property_id = h.property_id)) AS orphan_risks
);

-- ============================================================
-- TEST 8: Customer scenario coverage — all 12 have distinct paths
-- ============================================================
SELECT 'T8_SCENARIO_COVERAGE' AS test_id,
       CASE WHEN COUNT(DISTINCT churn_risk_label) >= 3
             AND SUM(CASE WHEN has_renewal_proposal THEN 1 ELSE 0 END) >= 4
             AND SUM(CASE WHEN total_claims > 0 THEN 1 ELSE 0 END) >= 4
             AND SUM(CASE WHEN total_claims = 0 THEN 1 ELSE 0 END) >= 4
            THEN 'PASS' ELSE 'FAIL' END AS result,
       COUNT(DISTINCT churn_risk_label) AS distinct_churn_levels,
       SUM(CASE WHEN has_renewal_proposal THEN 1 ELSE 0 END) AS with_renewal,
       SUM(CASE WHEN total_claims > 0 THEN 1 ELSE 0 END) AS with_claims,
       SUM(CASE WHEN policy_status = 'LAPSED' THEN 1 ELSE 0 END) AS lapsed
FROM V_CUSTOMER_360;

-- ============================================================
-- TEST 9: Cortex Search Service exists
-- ============================================================
SELECT 'T9_SEARCH_SERVICE' AS test_id,
       CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (SHOW CORTEX SEARCH SERVICES IN HOME360_DB.CORE);

-- ============================================================
-- TEST 10: All procedures exist
-- ============================================================
SELECT 'T10_PROCEDURES' AS test_id,
       CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS result,
       COUNT(*) AS procedure_count
FROM (SHOW PROCEDURES IN HOME360_DB.CORE);

-- ============================================================
-- TEST 11: Streamlit app exists
-- ============================================================
SELECT 'T11_STREAMLIT' AS test_id,
       CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (SHOW STREAMLITS LIKE 'HOME360_COPILOT' IN HOME360_DB.CORE);
