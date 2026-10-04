-- ============================================================
-- Home360 — Phase 5: Next Best Action Engine
-- ============================================================
-- Run after 06_interaction_intelligence.sql.
--
--   SP_NEXT_BEST_ACTION(customer_id, interaction_id)
--     → The core decision engine.
--     → Gathers all context by calling:
--         SP_COMPARE_POLICY   (Phase 3)
--         SP_ANALYZE_RISK     (Phase 3)
--         SP_ANALYZE_INTERACTION (Phase 4)
--         V_CUSTOMER_360      (Phase 2)
--     → Assembles a structured mega-prompt with all 6 signal
--       categories (customer, policy, claims, risk, property,
--       interaction).
--     → Sends to CORTEX.COMPLETE (llama3.1-70b) requesting
--       strict JSON output.
--     → Parses the response and returns a VARIANT with:
--         recommended_action, why, evidence, alternatives,
--         talking_points, risk_flags
--     → Retry with llama3.1-8b if first attempt fails to parse.
--
-- Design decisions:
--   • Single procedure entry point so the Streamlit app makes
--     one CALL and gets everything.
--   • The prompt explicitly separates FACTS from INTERPRETATION
--     and instructs the LLM to ground every evidence point in
--     data from the context.
--   • Candidate actions are defined in the prompt (A through G)
--     so the LLM picks from a known menu, making output more
--     predictable and UI-friendly.
--   • The procedure returns the full context alongside the NBA
--     so the UI doesn't need to make separate calls.
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

CREATE OR REPLACE PROCEDURE SP_NEXT_BEST_ACTION(
    P_CUSTOMER_ID VARCHAR,
    P_INTERACTION_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_customer_360 VARIANT;
    v_policy_comparison VARIANT;
    v_risk_analysis VARIANT;
    v_interaction_intel VARIANT;
    v_prompt VARCHAR;
    v_nba_raw VARCHAR;
    v_nba VARIANT;
    v_result VARIANT;
    v_count NUMBER;
BEGIN
    -- ========================================================
    -- 1. Validate customer exists
    -- ========================================================
    SELECT COUNT(*) INTO :v_count FROM CUSTOMER WHERE customer_id = :P_CUSTOMER_ID;
    IF (v_count = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'not_found',
            'customer_id', :P_CUSTOMER_ID,
            'message', 'Customer not found'
        );
    END IF;

    -- ========================================================
    -- 2. Gather all context
    -- ========================================================

    -- 2a. Customer 360
    SELECT OBJECT_CONSTRUCT(
        'customer_id', customer_id,
        'name', name,
        'age', age,
        'tenure_years', tenure_years,
        'customer_value', customer_value,
        'payment_history', payment_history,
        'churn_risk_score', churn_risk_score,
        'churn_risk_label', churn_risk_label,
        'property_type', property_type,
        'location', location,
        'building_age', building_age,
        'construction_type', construction_type,
        'policy_id', policy_id,
        'policy_status', policy_status,
        'annual_premium', annual_premium,
        'deductible', deductible,
        'building_coverage', building_coverage,
        'contents_coverage', contents_coverage,
        'flood_coverage', flood_coverage,
        'flood_deductible', flood_deductible,
        'exclusions', exclusions,
        'has_renewal_proposal', has_renewal_proposal,
        'total_claims', total_claims,
        'open_claims', open_claims,
        'total_claim_amount', total_claim_amount,
        'current_flood_risk', current_flood_risk,
        'current_fire_risk', current_fire_risk,
        'current_earthquake_risk', current_earthquake_risk,
        'current_risk_score', current_risk_score
    ) INTO :v_customer_360
    FROM V_CUSTOMER_360
    WHERE customer_id = :P_CUSTOMER_ID;

    -- 2b. Policy comparison (may return no_renewal)
    CALL SP_COMPARE_POLICY(:P_CUSTOMER_ID);
    v_policy_comparison := (SELECT SP_COMPARE_POLICY FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    -- 2c. Risk analysis (may return no_risk_change)
    CALL SP_ANALYZE_RISK(:P_CUSTOMER_ID);
    v_risk_analysis := (SELECT SP_ANALYZE_RISK FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    -- 2d. Interaction intelligence (skip if no interaction_id)
    IF (:P_INTERACTION_ID IS NOT NULL) THEN
        CALL SP_ANALYZE_INTERACTION(:P_INTERACTION_ID);
        v_interaction_intel := (SELECT SP_ANALYZE_INTERACTION FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    ELSE
        v_interaction_intel := OBJECT_CONSTRUCT('status', 'no_interaction', 'message', 'No interaction provided');
    END IF;

    -- ========================================================
    -- 3. Build the NBA prompt
    -- ========================================================
    v_prompt := '## Task
You are a Next Best Action engine for an insurance agent copilot called Home360.
Given the full customer context below, generate ONE recommended action with
complete explainability.

IMPORTANT RULES:
- Ground every evidence point in specific data from the context (numbers, dates, percentages).
- Clearly separate FACTS (from data) from INTERPRETATION (your analysis).
- The recommendation must serve both the customer AND the insurer.
- Do NOT recommend actions the data does not support.

## Customer Context
' || v_customer_360::VARCHAR || '

## Policy Comparison
' || v_policy_comparison::VARCHAR || '

## Risk Analysis
' || v_risk_analysis::VARCHAR || '

## Interaction Intelligence
' || v_interaction_intel::VARCHAR || '

## Candidate Actions (pick from this menu)
A. Explain renewal changes only (informational, no offer)
B. Explain changes and recommend standard renewal at new terms
C. Explain changes and offer alternative deductible/coverage option to manage premium
D. Recommend risk-reduction measures before finalizing renewal
E. Escalate to retention specialist (high churn risk, high-value customer)
F. Escalate to underwriting specialist (complex risk or coverage gap)
G. Request additional property information before proceeding

## Instructions
Generate a JSON response with EXACTLY this structure. Return ONLY valid JSON, no markdown, no explanation outside the JSON:

{
  "recommended_action": {
    "code": "A-G letter",
    "title": "short descriptive title",
    "description": "2-3 sentence description of what the agent should do",
    "priority": "HIGH or MEDIUM or LOW"
  },
  "why_this_action": "2-3 sentences explaining why this is the best action for this specific customer",
  "evidence": [
    "specific fact 1 from the data that supports this recommendation",
    "specific fact 2",
    "specific fact 3",
    "specific fact 4"
  ],
  "alternative_actions": [
    {
      "code": "letter",
      "title": "short title",
      "why_not_selected": "1 sentence explaining why this was ranked lower"
    },
    {
      "code": "letter",
      "title": "short title",
      "why_not_selected": "1 sentence explaining why this was ranked lower"
    }
  ],
  "agent_talking_points": [
    "point 1 the agent should communicate to the customer",
    "point 2",
    "point 3",
    "point 4",
    "point 5"
  ],
  "risk_flags": [
    "any risks or important considerations for the agent"
  ]
}';

    -- ========================================================
    -- 4. Call CORTEX.COMPLETE (primary: 70b)
    -- ========================================================
    SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', :v_prompt) INTO :v_nba_raw;

    -- ========================================================
    -- 5. Parse JSON (with 8b fallback on failure)
    -- ========================================================
    BEGIN
        v_nba := PARSE_JSON(:v_nba_raw);
    EXCEPTION
        WHEN OTHER THEN
            -- Retry with 8b model
            BEGIN
                SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b', :v_prompt) INTO :v_nba_raw;
                v_nba := PARSE_JSON(:v_nba_raw);
            EXCEPTION
                WHEN OTHER THEN
                    v_nba := OBJECT_CONSTRUCT(
                        'parse_error', TRUE,
                        'raw_output', :v_nba_raw,
                        'recommended_action', OBJECT_CONSTRUCT(
                            'code', 'B',
                            'title', 'Explain changes and recommend renewal',
                            'description', 'Review the renewal changes with the customer and recommend proceeding.',
                            'priority', 'MEDIUM'
                        ),
                        'why_this_action', 'Fallback recommendation — AI response could not be parsed.',
                        'evidence', ARRAY_CONSTRUCT('Fallback due to parsing failure'),
                        'alternative_actions', ARRAY_CONSTRUCT(),
                        'agent_talking_points', ARRAY_CONSTRUCT('Review the policy changes with the customer'),
                        'risk_flags', ARRAY_CONSTRUCT('AI parsing failed — review recommendation manually')
                    );
            END;
    END;

    -- ========================================================
    -- 6. Assemble final result with context + NBA
    -- ========================================================
    v_result := OBJECT_CONSTRUCT(
        'status', 'ok',
        'customer_id', :P_CUSTOMER_ID,
        'interaction_id', :P_INTERACTION_ID,
        'customer_name', v_customer_360:name::VARCHAR,

        'context', OBJECT_CONSTRUCT(
            'customer_360', :v_customer_360,
            'policy_comparison', :v_policy_comparison,
            'risk_analysis', :v_risk_analysis,
            'interaction_intelligence', :v_interaction_intel
        ),

        'nba', :v_nba
    );

    RETURN :v_result;
END;
$$;
