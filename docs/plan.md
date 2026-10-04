# Home360 — Implementation Plan

## Phase Overview

| Phase | Description                     | Status      | Depends On |
|-------|---------------------------------|-------------|------------|
| 1     | Synthetic data + schema         | COMPLETE    | —          |
| 2     | Customer + Home 360 views       | COMPLETE    | Phase 1    |
| 3     | Policy + risk comparison logic  | COMPLETE    | Phase 2    |
| 4     | Interaction intelligence        | COMPLETE    | Phase 1    |
| 5     | Next Best Action engine         | COMPLETE    | Phase 3, 4 |
| 6     | Agent copilot UI (Streamlit)    | COMPLETE    | Phase 5    |
| 7     | Action execution + logging      | COMPLETE    | Phase 6    |
| 8     | Testing + demo prep             | COMPLETE    | Phase 7    |

---

## Phase 1 — Synthetic Data + Schema (COMPLETE)

**Objective:** Stand up the database, schema, tables, and seed data.

**Deliverables:**
- [x] `HOME360_DB` database created
- [x] `HOME360_DB.CORE` schema created
- [x] `HOME360_WH` warehouse created (XS, 60s auto-suspend)
- [x] 7 tables: CUSTOMER, PROPERTY, POLICY_VERSION, HOME_RISK_HISTORY, CLAIM, INTERACTION, ACTION_LOG
- [x] 12 customers seeded with distinct NBA paths
- [x] May Chen (C001) hero scenario fully populated: 2 policy versions, 2 risk assessments, 1 renewal call transcript
- [x] All tables validated (row counts, FKs, May's data, Cortex AI test on transcript)

**Files:**
- `sql/01_setup.sql`
- `sql/02_schema.sql`
- `sql/03_seed_data.sql`

---

## Phase 2 — Customer + Home 360 Views

**Objective:** Create SQL views that assemble the unified customer context, policy comparison, and risk change analysis. These views are the read layer that the UI and NBA engine will query.

**Deliverables:**
- [x] `V_CUSTOMER_360` — one row per customer joining all 6 domains (12 rows, all customers)
- [x] `V_POLICY_COMPARISON` — CURRENT vs RENEWAL side-by-side with absolute change, percentage change, and severity (5 rows: May, Priya, Sarah, Linda, Aisha)
- [x] `V_RISK_CHANGE` — previous vs current risk assessment with direction and root cause (2 rows: May flood UP, Sarah earthquake UP)
- [x] `sql/04_views.sql` — all view DDL (400 lines)
- [x] Validation: May 360 — all fields populated, has_renewal=TRUE, 1 claim, flood=HIGH
- [x] Validation: V_POLICY_COMPARISON — May premium +18% MAJOR, flood cov -30% MAJOR, flood ded +100% MAJOR, exclusions changed
- [x] Validation: V_RISK_CHANGE — May flood MEDIUM→HIGH (+85.7%), Sarah earthquake MEDIUM→HIGH (+77.1%)

**Design notes:**

`V_CUSTOMER_360`:
- Joins CUSTOMER + PROPERTY + latest POLICY_VERSION (CURRENT) + claim aggregates + latest risk + latest interaction
- Single row per customer — aggregates claims (count, total amount, open count)
- Includes latest interaction summary fields
- Does NOT include RENEWAL policy (that's in V_POLICY_COMPARISON)

`V_POLICY_COMPARISON`:
- Only customers who have BOTH CURRENT and RENEWAL rows in POLICY_VERSION
- Pivots into one row: current_premium, renewal_premium, premium_change, premium_change_pct, etc.
- Classifies each change as MAJOR / MODERATE / MINOR / UNCHANGED
- Diffs exclusions text to find added/removed

`V_RISK_CHANGE`:
- Only properties with 2+ assessments in HOME_RISK_HISTORY
- Compares most recent vs second-most-recent assessment
- Shows direction (UP / DOWN / UNCHANGED) per risk dimension
- Includes risk_reason from the latest assessment

---

## Phase 3 — Policy + Risk Comparison Logic

**Objective:** Build the comparison and analysis logic that goes beyond the views — severity classification, causal chain linking, and formatted output for the UI.

**Deliverables:**
- [x] Stored procedure: `SP_COMPARE_POLICY(customer_id)` — returns structured JSON with all comparison fields + severity
- [x] Stored procedure: `SP_ANALYZE_RISK(customer_id)` — returns structured JSON with risk change + causal chain
- [x] `sql/05_procedures.sql` — procedure DDL (376 lines)
- [x] Validation: May — premium +18% MAJOR, flood cov -30% MAJOR, flood ded +100% MAJOR, exclusions changed, 4 key_findings
- [x] Validation: May risk — flood MEDIUM→HIGH, causal chain 2 items, policy_impact linked, 4 communication points
- [x] Validation: edge cases — C004 no_renewal, C002 no_risk_change, C999 not_found, C006 earthquake UP

**Design notes:**
- Procedures return VARIANT (JSON) so they can be consumed by both the Streamlit app and the NBA engine
- Severity thresholds: MAJOR (premium >15%, coverage reduction >20%, deductible >50%), MODERATE (5-15%, 10-20%, 20-50%), MINOR (below moderate)
- Causal chain: risk_reason → which policy fields were affected → by how much

---

## Phase 4 — Interaction Intelligence

**Objective:** Build the Cortex AI pipeline that extracts structured signals from raw transcripts.

**Deliverables:**
- [x] Stored procedure: `SP_ANALYZE_INTERACTION(interaction_id)` — runs all 4 Cortex functions, returns combined JSON
- [x] Cortex Search Service `INTERACTION_SEARCH_SVC` on INTERACTION.raw_transcript — semantic retrieval working
- [x] `sql/06_interaction_intelligence.sql` — procedure + search service DDL (229 lines)
- [x] Validation: May (INT001) — intent=renewal_inquiry, churn=moderate, retention_risk=ELEVATED, pricing+coverage concern both TRUE
- [x] Validation: Robert (INT002) — intent=claim_status, emotion=anxious, churn=low, retention=LOW
- [x] Validation: Linda (INT003) — intent=renewal_inquiry, churn=high, retention=HIGH, tone=retention-focused
- [x] Validation: James (INT004) — intent=billing_question, churn=none, retention=MINIMAL, tone=informational
- [x] Validation: Search — "premium increase renewal" returns C006, C001, C003 (correct top 3)
- [x] Validation: Search — "flood water damage" returns C002, C007, C005 (correct top 3)

**Design notes:**
- Calls SENTIMENT, CLASSIFY_TEXT, SUMMARIZE in parallel (independent)
- Calls COMPLETE (70b) for deep signal extraction (urgency, churn, key phrases)
- Combines all outputs into one JSON object
- Cortex Search Service: `TARGET_LAG = '1 hour'`, `EMBEDDING_MODEL = 'snowflake-arctic-embed-m-v1.5'`
- Fallback: if Search Service creation fails (trial account limits), degrade to SQL ILIKE search

---

## Phase 5 — Next Best Action Engine

**Objective:** Build the core reasoning engine that consumes all context and produces explainable, ranked recommendations.

**Deliverables:**
- [x] Stored procedure: `SP_NEXT_BEST_ACTION(customer_id, interaction_id)` — main NBA entry point
- [x] `sql/07_nba_engine.sql` — procedure DDL (260 lines)
- [x] Validation: May (C001/INT001) — action D (risk-reduction), HIGH priority, 4 evidence points, 5 talking points, 2 alternatives
- [x] Validation: Linda (C003/INT003) — action C (offer alternative), HIGH priority, E (retention) as fallback
- [x] Validation: Robert (C002/INT002) — action D (risk-reduction), claim delay flagged, no renewal context handled
- [x] Validation: James (C004/INT004) — action C, MEDIUM priority, evidence cites billing intent + excellent payment
- [x] Validation: David Kim (C009/NULL) — works with no interaction, no renewal, no risk change — still produces valid NBA
- [x] JSON parsing: all 5 calls returned valid parseable JSON from llama3.1-70b (no fallback to 8b needed)
- [x] Retry logic: 8b fallback + hardcoded safe default both implemented

**Design notes:**
- SP_NEXT_BEST_ACTION calls SP_COMPARE_POLICY, SP_ANALYZE_RISK, SP_ANALYZE_INTERACTION internally
- Assembles the mega-prompt with all signals
- Single CORTEX.COMPLETE call with structured JSON output instruction
- Parses JSON, validates required fields, returns VARIANT
- The prompt must instruct the LLM to ground recommendations in FACTS (from data) and separate them from INTERPRETATION

---

## Phase 6 — Agent Copilot UI (Streamlit)

**Objective:** Build the single-page Streamlit-in-Snowflake app that frontline agents use.

**Deliverables:**
- [ ] `streamlit/Home360_App.py` — single-file Streamlit app
- [ ] Section 1: Customer context (from V_CUSTOMER_360)
- [ ] Section 2: Renewal comparison (from V_POLICY_COMPARISON) with visual diff bars
- [ ] Section 3: Property risk (from V_RISK_CHANGE) with direction arrows
- [ ] Section 4: Current interaction (transcript + AI signals)
- [ ] Section 5: Next Best Action (prominently displayed recommendation)
- [ ] Customer selector dropdown at top
- [ ] [ TAKE ACTION ] / [ MODIFY ] / [ ESCALATE ] buttons
- [ ] Deploy to Snowflake
- [ ] Validation: walkthrough May's scenario end-to-end in the UI

**Design notes:**
- Single page, not tabs — one scroll gives the full picture
- Use st.columns for side-by-side layouts (current vs renewal)
- Use st.metric for key numbers with deltas
- Use st.expander for transcript (collapsed by default)
- NBA section uses st.container with colored background/border
- Customer selector triggers full reload of all sections
- Minimal custom CSS — use Streamlit defaults where possible

---

## Phase 7 — Action Execution + Logging

**Objective:** Complete the feedback loop — agent confirms or modifies the action, system logs it.

**Deliverables:**
- [ ] [ TAKE ACTION ] button writes to ACTION_LOG with status=EXECUTED
- [ ] [ MODIFY ] allows free-text override, logs with modified action_taken
- [ ] [ ESCALATE ] logs with status=ESCALATED and different action_taken
- [ ] Success confirmation displayed in UI
- [ ] Validation: after clicking TAKE ACTION for May, confirm ACTION_LOG row exists with correct data

**Design notes:**
- action_id generated as `ACT-{date}-{sequence}`
- recommended_action stores the full NBA JSON output
- action_taken stores the human-readable description of what the agent did
- status: PENDING (before click) → EXECUTED / DECLINED / ESCALATED

---

## Phase 8 — Testing + Demo Preparation

**Objective:** Validate all scenarios, polish the demo, prepare the walkthrough script.

**Deliverables:**
- [ ] Test all 12 customer scenarios through the full pipeline
- [ ] Verify May's hero scenario produces correct NBA output end-to-end
- [ ] Verify edge cases: customer with no renewal (C004), lapsed policy (C011), open claim (C002)
- [ ] Demo script: 3-minute walkthrough of May's scenario
- [ ] UI polish: spacing, colors, loading states
- [ ] Performance check: full pipeline for May completes in <10 seconds

**Demo script outline:**
1. Open Home360 copilot
2. Select May Chen from dropdown
3. Point out: 6.5 years, excellent payment, low claims
4. Show: premium +18%, flood coverage -30%, deductible doubled
5. Show: flood risk MEDIUM → HIGH, FEMA remap explanation
6. Show: transcript with sentiment, intent, churn signal highlighted
7. Show: NBA recommendation — explain + offer alternative option
8. Show: evidence grounded in facts, alternatives with reasons
9. Click TAKE ACTION
10. Show: ACTION_LOG entry created
11. Close: "This is how Home360 turns fragmented context into the next best action."

---

## Dependency Graph

```
Phase 1 (data + schema)
    │
    ├──▶ Phase 2 (360 views)
    │        │
    │        └──▶ Phase 3 (comparison procedures)
    │                 │
    │                 └──────────┐
    │                            ▼
    └──▶ Phase 4 (interaction) ──▶ Phase 5 (NBA engine)
                                       │
                                       ▼
                                  Phase 6 (Streamlit UI)
                                       │
                                       ▼
                                  Phase 7 (action logging)
                                       │
                                       ▼
                                  Phase 8 (testing + demo)
```

Note: Phases 2 and 4 can run in parallel (no dependency between them).
Phases 3 and 4 must both complete before Phase 5 can start.
