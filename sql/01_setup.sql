-- ============================================================
-- Home360 — Phase 1: Environment Setup
-- ============================================================
-- Creates the HOME360_DB database, CORE schema, and a dedicated
-- XS warehouse. Run this first with ACCOUNTADMIN.
--
-- Objects created:
--   DATABASE  HOME360_DB       — all Home360 objects live here
--   SCHEMA    HOME360_DB.CORE  — operational data model
--   WAREHOUSE HOME360_WH       — dedicated XS compute (auto-suspend 60s)
-- ============================================================

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS HOME360_DB;
CREATE SCHEMA IF NOT EXISTS HOME360_DB.CORE;

CREATE WAREHOUSE IF NOT EXISTS HOME360_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE HOME360_WH;
USE DATABASE HOME360_DB;
USE SCHEMA CORE;
