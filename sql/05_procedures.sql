-- ============================================================
-- Home360 — Phase 3: Policy + Risk Comparison Procedures
-- ============================================================
-- Run after 04_views.sql.
--
-- Two stored procedures that return VARIANT (JSON) so they can
-- be consumed by both the Streamlit app and the NBA engine:
--
--   SP_COMPARE_POLICY(customer_id)
--     → structured comparison of CURRENT vs RENEWAL policy
--     → absolute + percentage changes per field
--     → severity classification per field + overall
--     → exclusion diff (added / removed items)
--     → summary of key findings
--
--   SP_ANALYZE_RISK(customer_id)
--     → previous vs current risk per dimension
--     → direction of change
--     → root cause from risk_reason
--     → causal chain linking risk → policy impact
--     → communication points for the agent
--
-- Both procedures handle edge cases gracefully:
--   • Customer with no renewal → returns status: "no_renewal"
--   • Customer with no risk change → returns status: "no_risk_change"
--   • Customer not found → returns status: "not_found"
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

-- ============================================================
-- 1. SP_COMPARE_POLICY
-- ============================================================
-- Input:  customer_id (VARCHAR)
-- Output: VARIANT (JSON object)
--
-- Uses V_POLICY_COMPARISON for the numeric comparison, then
-- adds exclusion-level diffing and a human-readable summary.
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_COMPARE_POLICY(P_CUSTOMER_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS
DECLARE
    v_result VARIANT;
    v_name VARCHAR;
    v_count NUMBER;
BEGIN
    -- Check customer exists
    SELECT COUNT(*) INTO :v_count FROM CUSTOMER WHERE customer_id = :P_CUSTOMER_ID;
    IF (v_count = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'not_found',
            'customer_id', :P_CUSTOMER_ID,
            'message', 'Customer not found'
        );
    END IF;

    SELECT name INTO :v_name FROM CUSTOMER WHERE customer_id = :P_CUSTOMER_ID;

    -- Check renewal exists
    SELECT COUNT(*) INTO :v_count FROM V_POLICY_COMPARISON WHERE customer_id = :P_CUSTOMER_ID;
    IF (v_count = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'no_renewal',
            'customer_id', :P_CUSTOMER_ID,
            'customer_name', :v_name,
            'message', 'No renewal proposal found for this customer'
        );
    END IF;

    -- Build the full comparison JSON
    SELECT OBJECT_CONSTRUCT(
        'status', 'ok',
        'customer_id', pc.customer_id,
        'customer_name', pc.name,
        'policy_id', pc.policy_id,

        'premium', OBJECT_CONSTRUCT(
            'current', pc.cur_premium,
            'renewal', pc.ren_premium,
            'change', pc.premium_change,
            'change_pct', pc.premium_change_pct,
            'severity', pc.premium_severity
        ),
        'deductible', OBJECT_CONSTRUCT(
            'current', pc.cur_deductible,
            'renewal', pc.ren_deductible,
            'change', pc.deductible_change,
            'change_pct', pc.deductible_change_pct,
            'severity', pc.deductible_severity
        ),
        'building_coverage', OBJECT_CONSTRUCT(
            'current', pc.cur_building,
            'renewal', pc.ren_building,
            'change', pc.building_change,
            'change_pct', pc.building_change_pct,
            'severity', pc.building_severity
        ),
        'contents_coverage', OBJECT_CONSTRUCT(
            'current', pc.cur_contents,
            'renewal', pc.ren_contents,
            'change', pc.contents_change,
            'change_pct', pc.contents_change_pct,
            'severity', pc.contents_severity
        ),
        'flood_coverage', OBJECT_CONSTRUCT(
            'current', pc.cur_flood_cov,
            'renewal', pc.ren_flood_cov,
            'change', pc.flood_cov_change,
            'change_pct', pc.flood_cov_change_pct,
            'severity', pc.flood_cov_severity
        ),
        'flood_deductible', OBJECT_CONSTRUCT(
            'current', pc.cur_flood_ded,
            'renewal', pc.ren_flood_ded,
            'change', pc.flood_ded_change,
            'change_pct', pc.flood_ded_change_pct,
            'severity', pc.flood_ded_severity
        ),

        'exclusions', OBJECT_CONSTRUCT(
            'current', pc.cur_exclusions,
            'renewal', pc.ren_exclusions,
            'changed', pc.exclusions_changed
        ),

        'dates', OBJECT_CONSTRUCT(
            'current_effective', pc.cur_effective,
            'current_expiry', pc.cur_expiry,
            'renewal_effective', pc.ren_effective,
            'renewal_expiry', pc.ren_expiry
        ),

        'overall_severity', CASE
            WHEN pc.premium_severity = 'MAJOR'   OR pc.deductible_severity = 'MAJOR'
              OR pc.building_severity = 'MAJOR'  OR pc.contents_severity = 'MAJOR'
              OR pc.flood_cov_severity = 'MAJOR' OR pc.flood_ded_severity = 'MAJOR'
            THEN 'MAJOR'
            WHEN pc.premium_severity = 'MODERATE'   OR pc.deductible_severity = 'MODERATE'
              OR pc.building_severity = 'MODERATE'  OR pc.contents_severity = 'MODERATE'
              OR pc.flood_cov_severity = 'MODERATE' OR pc.flood_ded_severity = 'MODERATE'
            THEN 'MODERATE'
            WHEN pc.premium_severity = 'MINOR'   OR pc.deductible_severity = 'MINOR'
              OR pc.building_severity = 'MINOR'  OR pc.contents_severity = 'MINOR'
              OR pc.flood_cov_severity = 'MINOR' OR pc.flood_ded_severity = 'MINOR'
            THEN 'MINOR'
            ELSE 'UNCHANGED'
        END,

        'key_findings', ARRAY_CONSTRUCT_COMPACT(
            CASE WHEN pc.premium_change != 0 THEN
                'Premium ' || IFF(pc.premium_change > 0, 'increased', 'decreased')
                || ' by ' || ABS(pc.premium_change_pct) || '% ($'
                || TO_CHAR(ABS(pc.premium_change), '999,999') || '/year)'
            END,
            CASE WHEN pc.deductible_change != 0 THEN
                'General deductible ' || IFF(pc.deductible_change > 0, 'increased', 'decreased')
                || ' by ' || ABS(pc.deductible_change_pct) || '%'
            END,
            CASE WHEN pc.building_change != 0 THEN
                'Building coverage ' || IFF(pc.building_change > 0, 'increased', 'decreased')
                || ' by ' || ABS(pc.building_change_pct) || '%'
            END,
            CASE WHEN pc.contents_change != 0 THEN
                'Contents coverage ' || IFF(pc.contents_change > 0, 'increased', 'decreased')
                || ' by ' || ABS(pc.contents_change_pct) || '%'
            END,
            CASE WHEN pc.flood_cov_change != 0 THEN
                'Flood coverage ' || IFF(pc.flood_cov_change > 0, 'increased', 'decreased')
                || ' by ' || ABS(pc.flood_cov_change_pct) || '%'
            END,
            CASE WHEN pc.flood_ded_change != 0 THEN
                'Flood deductible ' || IFF(pc.flood_ded_change > 0, 'increased', 'decreased')
                || ' by ' || ABS(pc.flood_ded_change_pct) || '%'
            END,
            CASE WHEN pc.exclusions_changed THEN
                'Exclusions changed'
            END
        )

    ) INTO :v_result
    FROM V_POLICY_COMPARISON pc
    WHERE pc.customer_id = :P_CUSTOMER_ID;

    RETURN :v_result;
END;


-- ============================================================
-- 2. SP_ANALYZE_RISK
-- ============================================================
-- Input:  customer_id (VARCHAR)
-- Output: VARIANT (JSON object)
--
-- Uses V_RISK_CHANGE for the risk comparison, then enriches
-- with causal chain (risk → policy impact) and communication
-- points for the agent.
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_ANALYZE_RISK(P_CUSTOMER_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS
DECLARE
    v_result VARIANT;
    v_name VARCHAR;
    v_count NUMBER;
    v_has_comparison BOOLEAN;
    v_policy_impact VARIANT;
BEGIN
    -- Check customer exists
    SELECT COUNT(*) INTO :v_count FROM CUSTOMER WHERE customer_id = :P_CUSTOMER_ID;
    IF (v_count = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'not_found',
            'customer_id', :P_CUSTOMER_ID,
            'message', 'Customer not found'
        );
    END IF;

    SELECT name INTO :v_name FROM CUSTOMER WHERE customer_id = :P_CUSTOMER_ID;

    -- Check risk change exists (needs 2+ assessments)
    SELECT COUNT(*) INTO :v_count FROM V_RISK_CHANGE WHERE customer_id = :P_CUSTOMER_ID;
    IF (v_count = 0) THEN
        -- No risk change — return current risk snapshot instead
        LET v_single VARIANT;
        SELECT OBJECT_CONSTRUCT(
            'status', 'no_risk_change',
            'customer_id', :P_CUSTOMER_ID,
            'customer_name', :v_name,
            'message', 'Only one risk assessment on file — no change to compare',
            'current_risk', OBJECT_CONSTRUCT(
                'flood_risk', h.flood_risk,
                'fire_risk', h.fire_risk,
                'earthquake_risk', h.earthquake_risk,
                'overall_risk_score', h.overall_risk_score,
                'assessment_date', h.assessment_date,
                'risk_reason', h.risk_reason
            )
        ) INTO :v_single
        FROM HOME_RISK_HISTORY h
        JOIN PROPERTY p ON h.property_id = p.property_id
        WHERE p.customer_id = :P_CUSTOMER_ID
        QUALIFY ROW_NUMBER() OVER (PARTITION BY h.property_id ORDER BY h.assessment_date DESC) = 1;

        RETURN :v_single;
    END IF;

    -- Check if policy comparison also exists (for causal chain)
    SELECT COUNT(*) INTO :v_count FROM V_POLICY_COMPARISON WHERE customer_id = :P_CUSTOMER_ID;
    v_has_comparison := (:v_count > 0);

    -- Build policy impact if comparison exists
    IF (v_has_comparison) THEN
        SELECT OBJECT_CONSTRUCT(
            'premium_change_pct', pc.premium_change_pct,
            'premium_change', pc.premium_change,
            'flood_coverage_change_pct', pc.flood_cov_change_pct,
            'flood_coverage_change', pc.flood_cov_change,
            'flood_deductible_change_pct', pc.flood_ded_change_pct,
            'flood_deductible_change', pc.flood_ded_change,
            'exclusions_changed', pc.exclusions_changed,
            'overall_severity', CASE
                WHEN pc.premium_severity = 'MAJOR' OR pc.flood_cov_severity = 'MAJOR'
                  OR pc.flood_ded_severity = 'MAJOR' THEN 'MAJOR'
                WHEN pc.premium_severity = 'MODERATE' OR pc.flood_cov_severity = 'MODERATE'
                  OR pc.flood_ded_severity = 'MODERATE' THEN 'MODERATE'
                ELSE 'MINOR'
            END
        ) INTO :v_policy_impact
        FROM V_POLICY_COMPARISON pc
        WHERE pc.customer_id = :P_CUSTOMER_ID;
    ELSE
        v_policy_impact := OBJECT_CONSTRUCT('message', 'No renewal proposal — policy impact not available');
    END IF;

    -- Build the full risk analysis JSON
    SELECT OBJECT_CONSTRUCT(
        'status', 'ok',
        'customer_id', rc.customer_id,
        'customer_name', rc.name,
        'property_id', rc.property_id,
        'location', rc.location,
        'property_type', rc.property_type,

        'previous_assessment', OBJECT_CONSTRUCT(
            'assessment_id', rc.prev_assessment_id,
            'assessment_date', rc.prev_assessment_date,
            'flood_risk', rc.prev_flood_risk,
            'fire_risk', rc.prev_fire_risk,
            'earthquake_risk', rc.prev_earthquake_risk,
            'overall_risk_score', rc.prev_risk_score,
            'risk_reason', rc.prev_risk_reason
        ),
        'current_assessment', OBJECT_CONSTRUCT(
            'assessment_id', rc.curr_assessment_id,
            'assessment_date', rc.curr_assessment_date,
            'flood_risk', rc.curr_flood_risk,
            'fire_risk', rc.curr_fire_risk,
            'earthquake_risk', rc.curr_earthquake_risk,
            'overall_risk_score', rc.curr_risk_score,
            'risk_reason', rc.curr_risk_reason
        ),

        'changes', OBJECT_CONSTRUCT(
            'flood', OBJECT_CONSTRUCT(
                'previous', rc.prev_flood_risk,
                'current', rc.curr_flood_risk,
                'direction', rc.flood_direction
            ),
            'fire', OBJECT_CONSTRUCT(
                'previous', rc.prev_fire_risk,
                'current', rc.curr_fire_risk,
                'direction', rc.fire_direction
            ),
            'earthquake', OBJECT_CONSTRUCT(
                'previous', rc.prev_earthquake_risk,
                'current', rc.curr_earthquake_risk,
                'direction', rc.earthquake_direction
            ),
            'overall_score', OBJECT_CONSTRUCT(
                'previous', rc.prev_risk_score,
                'current', rc.curr_risk_score,
                'change', rc.risk_score_change,
                'change_pct', rc.risk_score_change_pct,
                'direction', rc.overall_direction
            )
        ),

        'root_cause', rc.curr_risk_reason,

        'causal_chain', ARRAY_CONSTRUCT_COMPACT(
            CASE WHEN rc.flood_direction != 'UNCHANGED' THEN
                'Flood risk changed from ' || rc.prev_flood_risk || ' to ' || rc.curr_flood_risk
            END,
            CASE WHEN rc.fire_direction != 'UNCHANGED' THEN
                'Fire risk changed from ' || rc.prev_fire_risk || ' to ' || rc.curr_fire_risk
            END,
            CASE WHEN rc.earthquake_direction != 'UNCHANGED' THEN
                'Earthquake risk changed from ' || rc.prev_earthquake_risk || ' to ' || rc.curr_earthquake_risk
            END,
            'Overall risk score changed from ' || rc.prev_risk_score || ' to ' || rc.curr_risk_score
                || ' (' || IFF(rc.risk_score_change > 0, '+', '') || rc.risk_score_change_pct || '%)'
        ),

        'policy_impact', :v_policy_impact,

        'communication_points', ARRAY_CONSTRUCT_COMPACT(
            'The risk change is based on external factors, not the customer''s behavior or claims history',
            CASE WHEN rc.flood_direction = 'UP' THEN
                'FEMA or local authority reclassified the area — the customer''s property itself has not changed'
            END,
            CASE WHEN rc.earthquake_direction = 'UP' THEN
                'Seismic models were updated by USGS — this affects all properties in the zone'
            END,
            CASE WHEN rc.fire_direction = 'UP' THEN
                'Wildfire risk models were updated based on recent fire-season data'
            END,
            'The customer may be able to reduce premiums by taking risk-prevention measures',
            CASE WHEN rc.flood_direction = 'UP' THEN
                'Flood mitigation options: sump pump, backflow valve, elevation certificate, flood barriers'
            END,
            CASE WHEN rc.fire_direction = 'UP' THEN
                'Fire mitigation options: defensible space, fire-resistant roofing, ember-resistant vents'
            END
        )

    ) INTO :v_result
    FROM V_RISK_CHANGE rc
    WHERE rc.customer_id = :P_CUSTOMER_ID;

    RETURN :v_result;
END;
