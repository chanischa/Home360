-- ============================================================
-- Home360 — Phase 7: Action Execution + Logging
-- ============================================================
-- Run after 07_nba_engine.sql.
--
-- Two objects:
--
--   SP_LOG_ACTION(customer_id, interaction_id, recommended_action,
--                 action_taken, status)
--     → Server-side insert into ACTION_LOG with auto-generated
--       action_id and timestamp.
--     → Avoids SQL injection from embedding raw JSON in the
--       Streamlit app's inline SQL.
--     → Returns the created action_id for confirmation.
--
--   V_ACTION_HISTORY
--     → Joined view of ACTION_LOG + CUSTOMER for the UI's
--       action history panel. Shows recent actions with
--       customer name and formatted timestamps.
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

-- ============================================================
-- 1. SP_LOG_ACTION
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_LOG_ACTION(
    P_CUSTOMER_ID VARCHAR,
    P_INTERACTION_ID VARCHAR,
    P_RECOMMENDED_ACTION VARCHAR,
    P_ACTION_TAKEN VARCHAR,
    P_STATUS VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_action_id VARCHAR;
    v_count NUMBER;
BEGIN
    -- Validate customer
    SELECT COUNT(*) INTO :v_count FROM CUSTOMER WHERE customer_id = :P_CUSTOMER_ID;
    IF (v_count = 0) THEN
        RETURN OBJECT_CONSTRUCT('status', 'error', 'message', 'Customer not found');
    END IF;

    -- Generate action_id: ACT-YYYYMMDD-HHMMSS-seq
    v_action_id := 'ACT-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD-HH24MISS') || '-' || UNIFORM(100, 999, RANDOM());

    INSERT INTO ACTION_LOG (
        action_id, customer_id, interaction_id,
        recommended_action, action_taken,
        action_timestamp, status
    ) VALUES (
        :v_action_id,
        :P_CUSTOMER_ID,
        :P_INTERACTION_ID,
        :P_RECOMMENDED_ACTION,
        :P_ACTION_TAKEN,
        CURRENT_TIMESTAMP(),
        :P_STATUS
    );

    RETURN OBJECT_CONSTRUCT(
        'status', 'ok',
        'action_id', :v_action_id,
        'customer_id', :P_CUSTOMER_ID,
        'action_status', :P_STATUS,
        'message', 'Action logged successfully'
    );
END;
$$;


-- ============================================================
-- 2. V_ACTION_HISTORY
-- ============================================================
-- Recent actions with customer name, formatted for the UI.
-- ============================================================
CREATE OR REPLACE VIEW V_ACTION_HISTORY AS
SELECT
    al.action_id,
    al.customer_id,
    c.name AS customer_name,
    al.interaction_id,
    al.action_taken,
    al.status,
    al.action_timestamp,
    al.recommended_action
FROM ACTION_LOG al
JOIN CUSTOMER c ON al.customer_id = c.customer_id
ORDER BY al.action_timestamp DESC;
