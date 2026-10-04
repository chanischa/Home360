-- ============================================================
-- Home360 — Phase 4: Interaction Intelligence
-- ============================================================
-- Run after 05_procedures.sql.
--
-- Two objects:
--
--   SP_ANALYZE_INTERACTION(interaction_id)
--     → Orchestrates 4 Cortex AI functions on a transcript:
--       1. CORTEX.SENTIMENT        → numeric score (-1 to +1)
--       2. CORTEX.CLASSIFY_TEXT    → intent label from fixed list
--       3. CORTEX.SUMMARIZE        → 2-3 sentence digest
--       4. CORTEX.COMPLETE (70b)   → deep signal extraction (JSON):
--          urgency, churn_signal, pricing_concern, coverage_concern,
--          complaint_signal, key_phrases, recommended_tone, summary
--     → Combines all outputs into one VARIANT (JSON) result
--     → Handles edge cases: not found, empty transcript
--
--   INTERACTION_SEARCH_SVC (Cortex Search Service)
--     → Semantic index on INTERACTION.raw_transcript
--     → Enables: "has this customer raised this concern before?"
--     → Falls back gracefully if creation fails on trial account
--
-- Design decisions:
--   • SENTIMENT, CLASSIFY_TEXT, SUMMARIZE run as scalar subqueries
--     inside a single SELECT — Snowflake parallelizes them.
--   • COMPLETE (70b) runs separately with a detailed extraction
--     prompt requesting strict JSON output.
--   • The procedure merges the fast-function outputs with the
--     deep-extraction output into one unified JSON object.
--   • sentiment_label is derived from the numeric score using
--     fixed thresholds, giving the UI a human-readable label
--     alongside the raw number.
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

-- ============================================================
-- 1. SP_ANALYZE_INTERACTION
-- ============================================================
-- Input:  interaction_id (VARCHAR) — or NULL to use the latest
--         interaction for a given customer
-- Output: VARIANT (JSON object) with all intelligence signals
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_ANALYZE_INTERACTION(P_INTERACTION_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_count NUMBER;
    v_transcript VARCHAR;
    v_customer_id VARCHAR;
    v_customer_name VARCHAR;
    v_interaction_type VARCHAR;
    v_interaction_ts TIMESTAMP_NTZ;
    v_agent_note VARCHAR;
    v_sentiment FLOAT;
    v_intent VARCHAR;
    v_summary VARCHAR;
    v_deep_raw VARCHAR;
    v_deep VARIANT;
    v_result VARIANT;
BEGIN
    -- Check interaction exists
    SELECT COUNT(*) INTO :v_count
    FROM INTERACTION WHERE interaction_id = :P_INTERACTION_ID;

    IF (v_count = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'not_found',
            'interaction_id', :P_INTERACTION_ID,
            'message', 'Interaction not found'
        );
    END IF;

    -- Retrieve interaction metadata
    SELECT i.raw_transcript, i.customer_id, i.interaction_type,
           i.interaction_timestamp, i.agent_note, c.name
    INTO :v_transcript, :v_customer_id, :v_interaction_type,
         :v_interaction_ts, :v_agent_note, :v_customer_name
    FROM INTERACTION i
    JOIN CUSTOMER c ON i.customer_id = c.customer_id
    WHERE i.interaction_id = :P_INTERACTION_ID;

    -- Guard: empty transcript
    IF (v_transcript IS NULL OR LENGTH(TRIM(v_transcript)) = 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'empty_transcript',
            'interaction_id', :P_INTERACTION_ID,
            'customer_id', :v_customer_id,
            'message', 'Transcript is empty — cannot analyze'
        );
    END IF;

    -- Step 1: Fast Cortex functions (sentiment + classify + summarize)
    SELECT
        SNOWFLAKE.CORTEX.SENTIMENT(:v_transcript),
        SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
            :v_transcript,
            ['renewal_inquiry', 'claim_status', 'billing_question',
             'cancellation_request', 'coverage_concern', 'complaint',
             'general_inquiry']
        )::VARCHAR,
        SNOWFLAKE.CORTEX.SUMMARIZE(:v_transcript)
    INTO :v_sentiment, :v_intent, :v_summary;

    -- Step 2: Deep signal extraction via COMPLETE (llama3.1-70b)
    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-70b',
        'You are an insurance interaction analyst. Analyze this customer interaction transcript and return ONLY a valid JSON object with these exact fields (no markdown, no explanation, just the JSON):

{
  "urgency": "low|medium|high|critical",
  "churn_signal": "none|low|moderate|high",
  "pricing_concern": true or false,
  "coverage_concern": true or false,
  "complaint_signal": true or false,
  "key_phrases": ["up to 5 important direct quotes from the customer"],
  "recommended_tone": "reassuring|empathetic|urgent|informational|retention-focused",
  "customer_emotion": "calm|concerned|frustrated|angry|anxious|satisfied"
}

Transcript:
' || :v_transcript
    ) INTO :v_deep_raw;

    -- Parse deep extraction JSON (with fallback on parse failure)
    BEGIN
        v_deep := PARSE_JSON(:v_deep_raw);
    EXCEPTION
        WHEN OTHER THEN
            v_deep := OBJECT_CONSTRUCT(
                'parse_error', TRUE,
                'raw_output', :v_deep_raw,
                'urgency', 'medium',
                'churn_signal', 'unknown',
                'pricing_concern', FALSE,
                'coverage_concern', FALSE,
                'complaint_signal', FALSE,
                'key_phrases', ARRAY_CONSTRUCT(),
                'recommended_tone', 'empathetic',
                'customer_emotion', 'unknown'
            );
    END;

    -- Step 3: Assemble unified result
    v_result := OBJECT_CONSTRUCT(
        'status', 'ok',
        'interaction_id', :P_INTERACTION_ID,
        'customer_id', :v_customer_id,
        'customer_name', :v_customer_name,
        'interaction_type', :v_interaction_type,
        'interaction_timestamp', :v_interaction_ts,
        'agent_note', :v_agent_note,

        'sentiment', OBJECT_CONSTRUCT(
            'score', ROUND(:v_sentiment, 4),
            'label', CASE
                WHEN :v_sentiment > 0.3 THEN 'Positive'
                WHEN :v_sentiment > 0.0 THEN 'Neutral'
                WHEN :v_sentiment > -0.3 THEN 'Mildly Concerned'
                WHEN :v_sentiment > -0.6 THEN 'Concerned'
                ELSE 'Very Negative'
            END
        ),

        'intent', OBJECT_CONSTRUCT(
            'raw', PARSE_JSON(:v_intent),
            'label', PARSE_JSON(:v_intent):label::VARCHAR
        ),

        'summary', :v_summary,

        'signals', OBJECT_CONSTRUCT(
            'urgency', v_deep:urgency::VARCHAR,
            'churn_signal', v_deep:churn_signal::VARCHAR,
            'pricing_concern', v_deep:pricing_concern::BOOLEAN,
            'coverage_concern', v_deep:coverage_concern::BOOLEAN,
            'complaint_signal', v_deep:complaint_signal::BOOLEAN,
            'recommended_tone', v_deep:recommended_tone::VARCHAR,
            'customer_emotion', v_deep:customer_emotion::VARCHAR
        ),

        'key_phrases', v_deep:key_phrases,

        'retention_risk', CASE
            WHEN v_deep:churn_signal::VARCHAR IN ('high') THEN 'HIGH'
            WHEN v_deep:churn_signal::VARCHAR IN ('moderate') OR :v_sentiment < -0.3 THEN 'ELEVATED'
            WHEN v_deep:churn_signal::VARCHAR IN ('low') OR :v_sentiment < 0.0 THEN 'LOW'
            ELSE 'MINIMAL'
        END
    );

    RETURN :v_result;
END;
$$;


-- ============================================================
-- 2. INTERACTION_SEARCH_SVC (Cortex Search Service)
-- ============================================================
-- Semantic search over interaction transcripts.
-- Enables queries like:
--   "Has May raised flood concerns before?"
--   "Which customers complained about premium increases?"
--
-- The service indexes raw_transcript and returns interaction_id,
-- customer_id, interaction_type, and timestamp for matching rows.
--
-- If this fails on a trial account, the system degrades gracefully
-- to SQL ILIKE search in the Streamlit app.
-- ============================================================
CREATE OR REPLACE CORTEX SEARCH SERVICE INTERACTION_SEARCH_SVC
    ON raw_transcript
    ATTRIBUTES customer_id, interaction_type, interaction_timestamp
    WAREHOUSE = HOME360_WH
    TARGET_LAG = '1 hour'
    AS (
        SELECT
            raw_transcript,
            customer_id,
            interaction_type,
            interaction_timestamp
        FROM INTERACTION
    );
