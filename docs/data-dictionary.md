# Home360 — Data Dictionary

All objects live in `HOME360_DB.CORE`.

---

## CUSTOMER

Demographics, tenure, value, and churn signals for each customer.

| Column | Type | Nullable | Description | Value Domain |
|---|---|---|---|---|
| customer_id | VARCHAR(20) | NO | Primary key | `C001` – `C012` |
| name | VARCHAR(100) | NO | Full name | Free text |
| age | NUMBER(3,0) | YES | Age in years | 29 – 63 |
| tenure_years | NUMBER(4,1) | YES | Years as customer | 0.8 – 10.0 |
| customer_value | NUMBER(12,2) | YES | Lifetime value estimate (USD) | 5,200 – 31,000 |
| payment_history | VARCHAR(20) | YES | Payment track record | `EXCELLENT` / `GOOD` / `FAIR` / `POOR` |
| churn_risk_score | NUMBER(3,2) | YES | Probability of churn | 0.00 (low) – 1.00 (high) |

**Row count:** 12

---

## PROPERTY

Physical property tied to a customer. One property per customer.

| Column | Type | Nullable | Description | Value Domain |
|---|---|---|---|---|
| property_id | VARCHAR(20) | NO | Primary key | `P001` – `P012` |
| customer_id | VARCHAR(20) | NO | FK → CUSTOMER | |
| property_type | VARCHAR(30) | YES | Structure type | `SINGLE_FAMILY` / `CONDO` / `TOWNHOME` |
| location | VARCHAR(100) | YES | City, state | e.g. "Cedar Falls, IA" |
| building_age | NUMBER(4,0) | YES | Age in years | 2 – 55 |
| construction_type | VARCHAR(30) | YES | Construction material | `WOOD_FRAME` / `BRICK` / `CONCRETE` / `MIXED` |

**Row count:** 12

---

## POLICY_VERSION

Versioned policy snapshots. Each customer has at least a `CURRENT` row. Customers approaching renewal also have a `RENEWAL` row, enabling side-by-side comparison.

| Column | Type | Nullable | Description | Value Domain |
|---|---|---|---|---|
| policy_id | VARCHAR(20) | NO | PK (compound with policy_version) | `POL001` – `POL012` |
| customer_id | VARCHAR(20) | NO | FK → CUSTOMER | |
| policy_version | VARCHAR(20) | NO | Snapshot type | `CURRENT` / `RENEWAL` / `HISTORICAL` |
| policy_type | VARCHAR(30) | YES | Product type | `HOME` |
| policy_status | VARCHAR(20) | YES | Current state | `ACTIVE` / `PROPOSED` / `LAPSED` / `CANCELLED` |
| effective_date | DATE | YES | Policy start date | |
| expiry_date | DATE | YES | Policy end date | |
| annual_premium | NUMBER(12,2) | YES | Annual cost (USD) | 3,800 – 18,500 |
| deductible | NUMBER(12,2) | YES | General deductible (USD) | 750 – 5,000 |
| building_coverage | NUMBER(12,2) | YES | Dwelling limit (USD) | 120,000 – 950,000 |
| contents_coverage | NUMBER(12,2) | YES | Contents limit (USD) | 35,000 – 150,000 |
| flood_coverage | NUMBER(12,2) | YES | Flood-specific limit (USD) | 0 (not included) – 100,000 |
| flood_deductible | NUMBER(12,2) | YES | Flood-specific deductible (USD) | 0 – 10,000 |
| exclusions | VARCHAR(500) | YES | Comma-separated exclusion list | e.g. "Earthquake, intentional damage" |
| renewal_date | DATE | YES | Next renewal date | |

**Row count:** 17 (12 CURRENT + 5 RENEWAL)

**Customers with RENEWAL proposals:** C001 (May), C003 (Linda), C005 (Priya), C006 (Sarah), C008 (Aisha)

---

## HOME_RISK_HISTORY

Time-series risk assessments per property. Multiple rows per property allow tracking of risk changes over time.

| Column | Type | Nullable | Description | Value Domain |
|---|---|---|---|---|
| risk_assessment_id | VARCHAR(20) | NO | Primary key | `RA001` – `RA014` |
| property_id | VARCHAR(20) | NO | FK → PROPERTY | |
| assessment_date | DATE | NO | When assessed | |
| flood_risk | VARCHAR(10) | YES | Flood risk rating | `LOW` / `MEDIUM` / `HIGH` |
| fire_risk | VARCHAR(10) | YES | Fire risk rating | `LOW` / `MEDIUM` / `HIGH` |
| earthquake_risk | VARCHAR(10) | YES | Earthquake risk rating | `LOW` / `MEDIUM` / `HIGH` |
| overall_risk_score | NUMBER(3,2) | YES | Composite risk score | 0.00 – 1.00 |
| risk_reason | VARCHAR(500) | YES | Human-readable explanation | Free text describing the assessment basis |

**Row count:** 14

**Properties with multiple assessments (risk changes):**
- P001 (May Chen): flood MEDIUM → HIGH (FEMA remap)
- P006 (Sarah Thompson): earthquake MEDIUM → HIGH (USGS update)

---

## CLAIM

Claims history. Links customer to policy and tracks type, status, and amount.

| Column | Type | Nullable | Description | Value Domain |
|---|---|---|---|---|
| claim_id | VARCHAR(20) | NO | Primary key | `CLM001` – `CLM008` |
| customer_id | VARCHAR(20) | NO | FK → CUSTOMER | |
| policy_id | VARCHAR(20) | YES | Policy reference | |
| claim_type | VARCHAR(30) | YES | Type of claim | `FLOOD` / `FIRE` / `THEFT` / `LIABILITY` / `OTHER` |
| claim_status | VARCHAR(20) | YES | Current state | `OPEN` / `CLOSED` / `DENIED` |
| claim_amount | NUMBER(12,2) | YES | Claim value (USD) | 1,200 – 52,000 |
| claim_date | DATE | YES | Date filed | |

**Row count:** 8

**Claim distribution by customer:**
- C001 (May): 1 closed theft — minor, old
- C002 (Robert): 1 open flood — active, large
- C004 (James): 1 closed theft — minor
- C005 (Priya): 1 closed fire — large
- C007 (Carlos): 3 claims (2 flood + 1 liability) — high frequency
- C011 (Tom): 1 denied flood

---

## INTERACTION

Customer touchpoints with verbatim transcripts. Analyzed by Cortex AI for sentiment, intent, urgency, and churn signals.

| Column | Type | Nullable | Description | Value Domain |
|---|---|---|---|---|
| interaction_id | VARCHAR(20) | NO | Primary key | `INT001` – `INT008` |
| customer_id | VARCHAR(20) | NO | FK → CUSTOMER | |
| interaction_type | VARCHAR(20) | YES | Channel | `CALL` / `EMAIL` / `CHAT` / `NOTE` |
| interaction_timestamp | TIMESTAMP_NTZ | YES | When it happened | |
| raw_transcript | VARCHAR(5000) | YES | Verbatim text | Multi-turn conversation or message body |
| agent_note | VARCHAR(2000) | YES | Agent-written summary | Free text (NULL if not yet written) |

**Row count:** 8

**Interaction types:**
- CALL: INT001 (May), INT002 (Robert), INT005 (Priya), INT006 (Sarah), INT007 (Carlos)
- CHAT: INT003 (Linda)
- EMAIL: INT004 (James), INT008 (Tom)

---

## ACTION_LOG

Audit trail for the NBA engine. Records what the engine recommended and what the agent actually did.

| Column | Type | Nullable | Description | Value Domain |
|---|---|---|---|---|
| action_id | VARCHAR(20) | NO | Primary key | `ACT-{date}-{seq}` |
| customer_id | VARCHAR(20) | NO | FK → CUSTOMER | |
| interaction_id | VARCHAR(20) | YES | FK → INTERACTION | |
| recommended_action | VARCHAR(2000) | YES | What the NBA engine suggested | JSON or plain text |
| action_taken | VARCHAR(2000) | YES | What the agent actually did | Free text |
| action_timestamp | TIMESTAMP_NTZ | YES | When the action occurred | |
| status | VARCHAR(20) | YES | Outcome | `PENDING` / `EXECUTED` / `DECLINED` / `ESCALATED` |

**Row count:** 0 (populated by Streamlit app in Phase 7)

---

## Views

### V_CUSTOMER_360

One row per customer joining all 6 data domains.

**Key columns:** All CUSTOMER fields + PROPERTY fields + current policy summary + claim aggregates (total_claims, open_claims, total_claim_amount) + latest risk assessment + has_renewal_proposal flag + latest interaction.

**Derived column:** `churn_risk_label` — mapped from churn_risk_score: HIGH (>=0.7), MODERATE (>=0.4), LOW (>=0.2), MINIMAL (<0.2)

**Row count:** 12 (all customers)

### V_POLICY_COMPARISON

One row per customer with BOTH CURRENT and RENEWAL policy versions. Shows absolute change, percentage change, and severity per field.

**Severity thresholds:**
- MAJOR: premium >15%, coverage reduction >20%, deductible increase >50%
- MODERATE: premium 5-15%, coverage 10-20%, deductible 20-50%
- MINOR: below moderate thresholds
- UNCHANGED: no change

**Row count:** 5 (May, Linda, Priya, Sarah, Aisha)

### V_RISK_CHANGE

One row per property with 2+ risk assessments. Compares most recent vs previous.

**Direction values:** UP / DOWN / UNCHANGED (per risk dimension), INCREASED / DECREASED / UNCHANGED (overall)

**Row count:** 2 (May flood UP, Sarah earthquake UP)

---

## Stored Procedures

### SP_COMPARE_POLICY(customer_id VARCHAR) → VARIANT

Returns JSON with: status, premium/deductible/coverage comparisons (each with current, renewal, change, change_pct, severity), exclusion diff, overall_severity, key_findings array.

Edge cases: `status: "not_found"`, `status: "no_renewal"`

### SP_ANALYZE_RISK(customer_id VARCHAR) → VARIANT

Returns JSON with: previous/current assessment, changes per dimension with direction, root_cause, causal_chain array, policy_impact (cross-linked), communication_points array.

Edge cases: `status: "not_found"`, `status: "no_risk_change"` (returns current risk snapshot)

### SP_ANALYZE_INTERACTION(interaction_id VARCHAR) → VARIANT

Returns JSON with: sentiment (score + label), intent (label), summary, signals (urgency, churn_signal, pricing_concern, coverage_concern, complaint_signal, recommended_tone, customer_emotion), key_phrases array, retention_risk.

Edge cases: `status: "not_found"`, `status: "empty_transcript"`

---

## Cortex Search Service

### INTERACTION_SEARCH_SVC

Semantic search index on `INTERACTION.raw_transcript`. Attributes: customer_id, interaction_type, interaction_timestamp. Target lag: 1 hour.
