-- ============================================================
-- Home360 — Phase 2: Customer + Home 360 Views
-- ============================================================
-- Run after 03_seed_data.sql.
--
-- Three views that form the read layer for the UI and NBA engine:
--
--   V_CUSTOMER_360       — unified context per customer (one row)
--   V_POLICY_COMPARISON  — CURRENT vs RENEWAL side-by-side with
--                          absolute change, percentage change,
--                          severity classification, and exclusion diff
--   V_RISK_CHANGE        — previous vs current risk assessment with
--                          direction arrows and root cause
--
-- Design decisions:
--   • V_CUSTOMER_360 aggregates claims and picks the latest risk/
--     interaction per customer using QUALIFY ROW_NUMBER() to avoid
--     fan-out from 1:many joins.
--   • V_POLICY_COMPARISON uses conditional aggregation (MAX + CASE)
--     to pivot CURRENT/RENEWAL rows into columns. Only includes
--     customers who have BOTH versions.
--   • V_RISK_CHANGE uses LAG() to compare the two most recent
--     assessments per property. Only includes properties with 2+
--     assessments.
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

-- ============================================================
-- 1. V_CUSTOMER_360
-- ============================================================
-- One row per customer with:
--   • Customer demographics + value
--   • Property characteristics
--   • Current policy summary
--   • Claim aggregates (count, open count, total amount)
--   • Latest risk assessment
--   • Has renewal proposed (boolean)
--   • Latest interaction summary
-- ============================================================
CREATE OR REPLACE VIEW V_CUSTOMER_360 AS
WITH claim_agg AS (
    SELECT
        customer_id,
        COUNT(*)                                          AS total_claims,
        SUM(CASE WHEN claim_status = 'OPEN' THEN 1 ELSE 0 END) AS open_claims,
        SUM(claim_amount)                                 AS total_claim_amount,
        MAX(claim_date)                                   AS last_claim_date
    FROM CLAIM
    GROUP BY customer_id
),
latest_risk AS (
    SELECT
        h.property_id,
        h.flood_risk,
        h.fire_risk,
        h.earthquake_risk,
        h.overall_risk_score,
        h.risk_reason,
        h.assessment_date AS risk_assessment_date
    FROM HOME_RISK_HISTORY h
    QUALIFY ROW_NUMBER() OVER (PARTITION BY h.property_id ORDER BY h.assessment_date DESC) = 1
),
has_renewal AS (
    SELECT DISTINCT customer_id
    FROM POLICY_VERSION
    WHERE policy_version = 'RENEWAL'
),
current_policy AS (
    SELECT *
    FROM POLICY_VERSION
    WHERE policy_version = 'CURRENT'
),
latest_interaction AS (
    SELECT
        interaction_id,
        customer_id,
        interaction_type,
        interaction_timestamp,
        raw_transcript,
        agent_note
    FROM INTERACTION
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY interaction_timestamp DESC) = 1
)
SELECT
    -- Customer
    c.customer_id,
    c.name,
    c.age,
    c.tenure_years,
    c.customer_value,
    c.payment_history,
    c.churn_risk_score,
    CASE
        WHEN c.churn_risk_score >= 0.7 THEN 'HIGH'
        WHEN c.churn_risk_score >= 0.4 THEN 'MODERATE'
        WHEN c.churn_risk_score >= 0.2 THEN 'LOW'
        ELSE 'MINIMAL'
    END AS churn_risk_label,

    -- Property
    p.property_id,
    p.property_type,
    p.location,
    p.building_age,
    p.construction_type,

    -- Current policy
    cp.policy_id,
    cp.policy_status,
    cp.effective_date,
    cp.expiry_date,
    cp.annual_premium,
    cp.deductible,
    cp.building_coverage,
    cp.contents_coverage,
    cp.flood_coverage,
    cp.flood_deductible,
    cp.exclusions,
    cp.renewal_date,

    -- Renewal flag
    CASE WHEN hr.customer_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_renewal_proposal,

    -- Claims
    COALESCE(ca.total_claims, 0)        AS total_claims,
    COALESCE(ca.open_claims, 0)         AS open_claims,
    COALESCE(ca.total_claim_amount, 0)  AS total_claim_amount,
    ca.last_claim_date,

    -- Latest risk
    lr.flood_risk           AS current_flood_risk,
    lr.fire_risk            AS current_fire_risk,
    lr.earthquake_risk      AS current_earthquake_risk,
    lr.overall_risk_score   AS current_risk_score,
    lr.risk_reason          AS current_risk_reason,
    lr.risk_assessment_date,

    -- Latest interaction
    li.interaction_id       AS last_interaction_id,
    li.interaction_type     AS last_interaction_type,
    li.interaction_timestamp AS last_interaction_timestamp,
    li.raw_transcript       AS last_interaction_transcript,
    li.agent_note           AS last_interaction_note

FROM CUSTOMER c
LEFT JOIN PROPERTY p            ON c.customer_id = p.customer_id
LEFT JOIN current_policy cp     ON c.customer_id = cp.customer_id
LEFT JOIN claim_agg ca          ON c.customer_id = ca.customer_id
LEFT JOIN latest_risk lr        ON p.property_id = lr.property_id
LEFT JOIN has_renewal hr        ON c.customer_id = hr.customer_id
LEFT JOIN latest_interaction li ON c.customer_id = li.customer_id;


-- ============================================================
-- 2. V_POLICY_COMPARISON
-- ============================================================
-- One row per customer who has BOTH a CURRENT and RENEWAL policy.
-- Pivots both versions into columns and computes:
--   • Absolute change (renewal - current)
--   • Percentage change ((renewal - current) / current * 100)
--   • Severity per field (MAJOR / MODERATE / MINOR / UNCHANGED)
--   • Exclusion diff (added / removed)
-- ============================================================
CREATE OR REPLACE VIEW V_POLICY_COMPARISON AS
WITH pivoted AS (
    SELECT
        customer_id,
        policy_id,

        -- CURRENT values
        MAX(CASE WHEN policy_version = 'CURRENT' THEN annual_premium  END) AS cur_premium,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN deductible      END) AS cur_deductible,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN building_coverage END) AS cur_building,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN contents_coverage END) AS cur_contents,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN flood_coverage   END) AS cur_flood_cov,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN flood_deductible END) AS cur_flood_ded,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN exclusions       END) AS cur_exclusions,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN effective_date   END) AS cur_effective,
        MAX(CASE WHEN policy_version = 'CURRENT' THEN expiry_date     END) AS cur_expiry,

        -- RENEWAL values
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN annual_premium  END) AS ren_premium,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN deductible      END) AS ren_deductible,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN building_coverage END) AS ren_building,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN contents_coverage END) AS ren_contents,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN flood_coverage   END) AS ren_flood_cov,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN flood_deductible END) AS ren_flood_ded,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN exclusions       END) AS ren_exclusions,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN effective_date   END) AS ren_effective,
        MAX(CASE WHEN policy_version = 'RENEWAL' THEN expiry_date     END) AS ren_expiry

    FROM POLICY_VERSION
    WHERE policy_version IN ('CURRENT', 'RENEWAL')
    GROUP BY customer_id, policy_id
    HAVING COUNT(DISTINCT policy_version) = 2  -- must have both
)
SELECT
    c.customer_id,
    c.name,
    p.policy_id,

    -- Premium
    p.cur_premium,
    p.ren_premium,
    p.ren_premium - p.cur_premium AS premium_change,
    ROUND((p.ren_premium - p.cur_premium) / NULLIF(p.cur_premium, 0) * 100, 1) AS premium_change_pct,
    CASE
        WHEN ABS((p.ren_premium - p.cur_premium) / NULLIF(p.cur_premium, 0) * 100) > 15 THEN 'MAJOR'
        WHEN ABS((p.ren_premium - p.cur_premium) / NULLIF(p.cur_premium, 0) * 100) > 5  THEN 'MODERATE'
        WHEN p.ren_premium != p.cur_premium THEN 'MINOR'
        ELSE 'UNCHANGED'
    END AS premium_severity,

    -- Deductible
    p.cur_deductible,
    p.ren_deductible,
    p.ren_deductible - p.cur_deductible AS deductible_change,
    ROUND((p.ren_deductible - p.cur_deductible) / NULLIF(p.cur_deductible, 0) * 100, 1) AS deductible_change_pct,
    CASE
        WHEN ABS((p.ren_deductible - p.cur_deductible) / NULLIF(p.cur_deductible, 0) * 100) > 50 THEN 'MAJOR'
        WHEN ABS((p.ren_deductible - p.cur_deductible) / NULLIF(p.cur_deductible, 0) * 100) > 20 THEN 'MODERATE'
        WHEN p.ren_deductible != p.cur_deductible THEN 'MINOR'
        ELSE 'UNCHANGED'
    END AS deductible_severity,

    -- Building coverage
    p.cur_building,
    p.ren_building,
    p.ren_building - p.cur_building AS building_change,
    ROUND((p.ren_building - p.cur_building) / NULLIF(p.cur_building, 0) * 100, 1) AS building_change_pct,
    CASE
        WHEN ABS((p.ren_building - p.cur_building) / NULLIF(p.cur_building, 0) * 100) > 20 THEN 'MAJOR'
        WHEN ABS((p.ren_building - p.cur_building) / NULLIF(p.cur_building, 0) * 100) > 10 THEN 'MODERATE'
        WHEN p.ren_building != p.cur_building THEN 'MINOR'
        ELSE 'UNCHANGED'
    END AS building_severity,

    -- Contents coverage
    p.cur_contents,
    p.ren_contents,
    p.ren_contents - p.cur_contents AS contents_change,
    ROUND((p.ren_contents - p.cur_contents) / NULLIF(p.cur_contents, 0) * 100, 1) AS contents_change_pct,
    CASE
        WHEN ABS((p.ren_contents - p.cur_contents) / NULLIF(p.cur_contents, 0) * 100) > 20 THEN 'MAJOR'
        WHEN ABS((p.ren_contents - p.cur_contents) / NULLIF(p.cur_contents, 0) * 100) > 10 THEN 'MODERATE'
        WHEN p.ren_contents != p.cur_contents THEN 'MINOR'
        ELSE 'UNCHANGED'
    END AS contents_severity,

    -- Flood coverage
    p.cur_flood_cov,
    p.ren_flood_cov,
    p.ren_flood_cov - p.cur_flood_cov AS flood_cov_change,
    ROUND((p.ren_flood_cov - p.cur_flood_cov) / NULLIF(p.cur_flood_cov, 0) * 100, 1) AS flood_cov_change_pct,
    CASE
        WHEN NULLIF(p.cur_flood_cov, 0) IS NULL AND NULLIF(p.ren_flood_cov, 0) IS NULL THEN 'UNCHANGED'
        WHEN ABS((p.ren_flood_cov - p.cur_flood_cov) / NULLIF(p.cur_flood_cov, 0) * 100) > 20 THEN 'MAJOR'
        WHEN ABS((p.ren_flood_cov - p.cur_flood_cov) / NULLIF(p.cur_flood_cov, 0) * 100) > 10 THEN 'MODERATE'
        WHEN p.ren_flood_cov != p.cur_flood_cov THEN 'MINOR'
        ELSE 'UNCHANGED'
    END AS flood_cov_severity,

    -- Flood deductible
    p.cur_flood_ded,
    p.ren_flood_ded,
    p.ren_flood_ded - p.cur_flood_ded AS flood_ded_change,
    ROUND((p.ren_flood_ded - p.cur_flood_ded) / NULLIF(p.cur_flood_ded, 0) * 100, 1) AS flood_ded_change_pct,
    CASE
        WHEN NULLIF(p.cur_flood_ded, 0) IS NULL AND NULLIF(p.ren_flood_ded, 0) IS NULL THEN 'UNCHANGED'
        WHEN ABS((p.ren_flood_ded - p.cur_flood_ded) / NULLIF(p.cur_flood_ded, 0) * 100) > 50 THEN 'MAJOR'
        WHEN ABS((p.ren_flood_ded - p.cur_flood_ded) / NULLIF(p.cur_flood_ded, 0) * 100) > 20 THEN 'MODERATE'
        WHEN p.ren_flood_ded != p.cur_flood_ded THEN 'MINOR'
        ELSE 'UNCHANGED'
    END AS flood_ded_severity,

    -- Exclusions diff
    p.cur_exclusions,
    p.ren_exclusions,
    CASE WHEN p.cur_exclusions != p.ren_exclusions THEN TRUE ELSE FALSE END AS exclusions_changed,

    -- Dates
    p.cur_effective,
    p.cur_expiry,
    p.ren_effective,
    p.ren_expiry,

    -- Overall severity (worst of all fields)
    CASE
        WHEN premium_severity = 'MAJOR'    OR deductible_severity = 'MAJOR'
          OR building_severity = 'MAJOR'   OR contents_severity = 'MAJOR'
          OR flood_cov_severity = 'MAJOR'  OR flood_ded_severity = 'MAJOR'
        THEN 'MAJOR'
        WHEN premium_severity = 'MODERATE'    OR deductible_severity = 'MODERATE'
          OR building_severity = 'MODERATE'   OR contents_severity = 'MODERATE'
          OR flood_cov_severity = 'MODERATE'  OR flood_ded_severity = 'MODERATE'
        THEN 'MODERATE'
        WHEN premium_severity = 'MINOR'    OR deductible_severity = 'MINOR'
          OR building_severity = 'MINOR'   OR contents_severity = 'MINOR'
          OR flood_cov_severity = 'MINOR'  OR flood_ded_severity = 'MINOR'
        THEN 'MINOR'
        ELSE 'UNCHANGED'
    END AS overall_severity

FROM pivoted p
JOIN CUSTOMER c ON p.customer_id = c.customer_id;


-- ============================================================
-- 3. V_RISK_CHANGE
-- ============================================================
-- One row per property that has 2+ risk assessments.
-- Compares the most recent vs the previous assessment.
-- Shows direction of change per risk dimension and root cause.
-- ============================================================
CREATE OR REPLACE VIEW V_RISK_CHANGE AS
WITH ranked AS (
    SELECT
        h.*,
        p.customer_id,
        p.location,
        p.property_type,
        ROW_NUMBER() OVER (PARTITION BY h.property_id ORDER BY h.assessment_date DESC) AS rn
    FROM HOME_RISK_HISTORY h
    JOIN PROPERTY p ON h.property_id = p.property_id
),
current_risk AS (
    SELECT * FROM ranked WHERE rn = 1
),
previous_risk AS (
    SELECT * FROM ranked WHERE rn = 2
)
SELECT
    c.customer_id,
    cu.name,
    c.property_id,
    c.location,
    c.property_type,

    -- Previous assessment
    p.risk_assessment_id    AS prev_assessment_id,
    p.assessment_date       AS prev_assessment_date,
    p.flood_risk            AS prev_flood_risk,
    p.fire_risk             AS prev_fire_risk,
    p.earthquake_risk       AS prev_earthquake_risk,
    p.overall_risk_score    AS prev_risk_score,
    p.risk_reason           AS prev_risk_reason,

    -- Current assessment
    c.risk_assessment_id    AS curr_assessment_id,
    c.assessment_date       AS curr_assessment_date,
    c.flood_risk            AS curr_flood_risk,
    c.fire_risk             AS curr_fire_risk,
    c.earthquake_risk       AS curr_earthquake_risk,
    c.overall_risk_score    AS curr_risk_score,
    c.risk_reason           AS curr_risk_reason,

    -- Flood direction
    CASE
        WHEN p.flood_risk = c.flood_risk THEN 'UNCHANGED'
        WHEN (CASE c.flood_risk WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END)
           > (CASE p.flood_risk WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END)
        THEN 'UP'
        ELSE 'DOWN'
    END AS flood_direction,

    -- Fire direction
    CASE
        WHEN p.fire_risk = c.fire_risk THEN 'UNCHANGED'
        WHEN (CASE c.fire_risk WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END)
           > (CASE p.fire_risk WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END)
        THEN 'UP'
        ELSE 'DOWN'
    END AS fire_direction,

    -- Earthquake direction
    CASE
        WHEN p.earthquake_risk = c.earthquake_risk THEN 'UNCHANGED'
        WHEN (CASE c.earthquake_risk WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END)
           > (CASE p.earthquake_risk WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END)
        THEN 'UP'
        ELSE 'DOWN'
    END AS earthquake_direction,

    -- Overall score change
    c.overall_risk_score - p.overall_risk_score AS risk_score_change,
    ROUND((c.overall_risk_score - p.overall_risk_score) / NULLIF(p.overall_risk_score, 0) * 100, 1) AS risk_score_change_pct,

    -- Overall direction
    CASE
        WHEN c.overall_risk_score > p.overall_risk_score THEN 'INCREASED'
        WHEN c.overall_risk_score < p.overall_risk_score THEN 'DECREASED'
        ELSE 'UNCHANGED'
    END AS overall_direction

FROM current_risk c
JOIN previous_risk p  ON c.property_id = p.property_id
JOIN CUSTOMER cu      ON c.customer_id = cu.customer_id;
