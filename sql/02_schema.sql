-- ============================================================
-- Home360 — Phase 1: Core Schema
-- ============================================================
-- Run after 01_setup.sql.
--
-- 7 tables that model the full renewal journey:
--
--   CUSTOMER          — demographics, tenure, value, payment history
--   POLICY_VERSION    — every policy snapshot (CURRENT vs RENEWAL)
--   CLAIM             — claims history per customer/policy
--   PROPERTY          — physical property characteristics
--   HOME_RISK_HISTORY — time-series risk assessments per property
--   INTERACTION       — call/email/chat transcripts + agent notes
--   ACTION_LOG        — audit trail of recommended & executed actions
--
-- Design decisions:
--   • POLICY_VERSION replaces a single POLICY table so we can store
--     both the current and renewal policy side-by-side and compare them.
--   • HOME_RISK_HISTORY allows multiple assessments per property so we
--     can show "flood risk changed from Medium to High" with dates.
--   • ACTION_LOG captures both what the NBA engine recommended and
--     what the agent actually did, enabling feedback loops.
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

-- ============================================================
-- 1. CUSTOMER
-- ============================================================
-- One row per customer. Core demographic and value fields that
-- feed the retention/churn signals in the NBA engine.
-- ============================================================
CREATE OR REPLACE TABLE CUSTOMER (
    customer_id      VARCHAR(20)   PRIMARY KEY,
    name             VARCHAR(100)  NOT NULL,
    age              NUMBER(3,0),
    tenure_years     NUMBER(4,1),
    customer_value   NUMBER(12,2),                -- lifetime value estimate (USD)
    payment_history  VARCHAR(20),                  -- EXCELLENT / GOOD / FAIR / POOR
    churn_risk_score NUMBER(3,2)                   -- 0.00 (low) – 1.00 (high)
);

-- ============================================================
-- 2. PROPERTY
-- ============================================================
-- Physical property tied to a customer. Location, age, and
-- construction type feed the risk-assessment context.
-- ============================================================
CREATE OR REPLACE TABLE PROPERTY (
    property_id       VARCHAR(20)  PRIMARY KEY,
    customer_id       VARCHAR(20)  NOT NULL REFERENCES CUSTOMER(customer_id),
    property_type     VARCHAR(30),                 -- SINGLE_FAMILY / CONDO / TOWNHOME
    location          VARCHAR(100),                -- city, state
    building_age      NUMBER(4,0),                 -- years
    construction_type VARCHAR(30)                   -- WOOD_FRAME / BRICK / CONCRETE / MIXED
);

-- ============================================================
-- 3. POLICY_VERSION
-- ============================================================
-- Each row is one snapshot of a policy. A customer approaching
-- renewal has at least two rows: policy_version = 'CURRENT'
-- (the active policy) and 'RENEWAL' (the proposed terms).
--
-- This enables side-by-side comparison of premium, deductible,
-- coverage limits, and exclusions without self-joins on dates.
-- ============================================================
CREATE OR REPLACE TABLE POLICY_VERSION (
    policy_id               VARCHAR(20),
    customer_id             VARCHAR(20)  NOT NULL REFERENCES CUSTOMER(customer_id),
    policy_version          VARCHAR(20)  NOT NULL,  -- CURRENT / RENEWAL / HISTORICAL
    policy_type             VARCHAR(30),             -- HOME
    policy_status           VARCHAR(20),             -- ACTIVE / PROPOSED / LAPSED / CANCELLED
    effective_date          DATE,
    expiry_date             DATE,
    annual_premium          NUMBER(12,2),
    deductible              NUMBER(12,2),
    building_coverage       NUMBER(12,2),
    contents_coverage       NUMBER(12,2),
    flood_coverage          NUMBER(12,2),
    flood_deductible        NUMBER(12,2),
    exclusions              VARCHAR(500),
    renewal_date            DATE,
    PRIMARY KEY (policy_id, policy_version)
);

-- ============================================================
-- 4. HOME_RISK_HISTORY
-- ============================================================
-- Time-series risk assessments per property. Multiple rows per
-- property allow the system to detect and explain risk changes
-- (e.g. "flood risk upgraded from MEDIUM to HIGH on 2026-08-15
-- due to updated FEMA flood-zone mapping").
-- ============================================================
CREATE OR REPLACE TABLE HOME_RISK_HISTORY (
    risk_assessment_id  VARCHAR(20)  PRIMARY KEY,
    property_id         VARCHAR(20)  NOT NULL REFERENCES PROPERTY(property_id),
    assessment_date     DATE         NOT NULL,
    flood_risk          VARCHAR(10),               -- LOW / MEDIUM / HIGH
    fire_risk           VARCHAR(10),
    earthquake_risk     VARCHAR(10),
    overall_risk_score  NUMBER(3,2),               -- 0.00 – 1.00
    risk_reason         VARCHAR(500)               -- human-readable explanation
);

-- ============================================================
-- 5. CLAIM
-- ============================================================
-- Claims history. Links to both customer and the specific
-- policy version. Claim frequency and severity are key NBA signals.
-- ============================================================
CREATE OR REPLACE TABLE CLAIM (
    claim_id      VARCHAR(20)  PRIMARY KEY,
    customer_id   VARCHAR(20)  NOT NULL REFERENCES CUSTOMER(customer_id),
    policy_id     VARCHAR(20),
    claim_type    VARCHAR(30),                     -- FLOOD / FIRE / THEFT / LIABILITY / OTHER
    claim_status  VARCHAR(20),                     -- OPEN / CLOSED / DENIED
    claim_amount  NUMBER(12,2),
    claim_date    DATE
);

-- ============================================================
-- 6. INTERACTION
-- ============================================================
-- Every customer touchpoint: calls, emails, chats, internal notes.
-- raw_transcript holds the verbatim text that Cortex AI will
-- analyze for sentiment, intent, urgency, and churn signals.
-- ============================================================
CREATE OR REPLACE TABLE INTERACTION (
    interaction_id        VARCHAR(20)    PRIMARY KEY,
    customer_id           VARCHAR(20)    NOT NULL REFERENCES CUSTOMER(customer_id),
    interaction_type      VARCHAR(20),              -- CALL / EMAIL / CHAT / NOTE
    interaction_timestamp TIMESTAMP_NTZ,
    raw_transcript        VARCHAR(5000),            -- verbatim transcript or message body
    agent_note            VARCHAR(2000)             -- optional agent-written summary
);

-- ============================================================
-- 7. ACTION_LOG
-- ============================================================
-- Audit trail for the NBA engine. Each row records:
--   • what the engine recommended
--   • what the agent actually did (may differ)
--   • outcome status
-- This closes the feedback loop and enables future model tuning.
-- ============================================================
CREATE OR REPLACE TABLE ACTION_LOG (
    action_id          VARCHAR(40)    PRIMARY KEY,
    customer_id        VARCHAR(20)    NOT NULL REFERENCES CUSTOMER(customer_id),
    interaction_id     VARCHAR(20)    REFERENCES INTERACTION(interaction_id),
    recommended_action VARCHAR(16000),
    action_taken       VARCHAR(4000),
    action_timestamp   TIMESTAMP_NTZ,
    status             VARCHAR(20)                  -- PENDING / EXECUTED / DECLINED / ESCALATED
);
