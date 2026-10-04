# Home360

**Decision Intelligence for Insurance Frontlines**

Home360 is a Next Best Action copilot that helps frontline insurance agents handle complex home-insurance renewals. It combines customer history, policy changes, property risk, claims, and live interaction context into one explainable recommendation.

---

## The Problem

During home-insurance renewal, agents must manually piece together information from multiple systems:

- Who is this customer and what is their history?
- What changed between the current and renewal policy?
- Why did it change?
- How should I explain the changes?
- What should I offer or do next?

This is slow, inconsistent, and risks losing valuable customers who don't understand why their premium increased.

## The Solution

Home360 turns fragmented context into a single, explainable action:

```
Customer contacts insurer
  -> Identify + classify intent and sentiment
  -> Retrieve full customer context (360 view)
  -> Compare current vs renewal policy
  -> Assess property risk changes
  -> Reason across all signals
  -> Recommend a ranked, explainable action
  -> Agent executes or escalates
  -> Log the outcome
```

### What makes it different

| Generic Customer 360 | Home360 |
|---|---|
| "Who is this customer?" | "What changed, why does it matter, and what should the agent do next?" |

Every recommendation separates **facts** (from data) from **AI interpretation** (derived signals) from **recommended action** (what to do and why).

---

## Hero Scenario: May Chen

May is a loyal customer (6.5 years, excellent payment history) calling about her renewal. Her premium increased 18% because FEMA reclassified her neighborhood as high-risk for flooding.

Home360 automatically:

1. Identifies May and recognizes the renewal intent
2. Detects concerned sentiment and moderate churn risk
3. Retrieves her full 360 context
4. Compares her current vs proposed policy (premium +18%, flood coverage -30%, flood deductible doubled, new sewer backup exclusion)
5. Explains the risk change (FEMA Zone X -> Zone AE, flood risk MEDIUM -> HIGH)
6. Generates candidate actions and selects the best one:

> **Explain the risk change transparently, show how it affected renewal terms, and offer an alternative coverage/deductible configuration that preserves essential protection while managing the premium increase.**

With evidence, talking points, and ranked alternatives — all grounded in data.

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Database | Snowflake (`HOME360_DB.CORE`) | All structured data |
| Compute | `HOME360_WH` (XS) | SQL + views + procedures |
| Sentiment | `CORTEX.SENTIMENT` | Real-time sentiment scoring |
| Classification | `CORTEX.CLASSIFY_TEXT` | Intent detection |
| Summarization | `CORTEX.SUMMARIZE` | Transcript digests |
| Reasoning | `CORTEX.COMPLETE` (llama3.1-70b) | NBA engine + deep signal extraction |
| Search | Cortex Search Service | Semantic interaction retrieval |
| UI | Streamlit in Snowflake | Agent copilot dashboard |
| Development | CoCo (Cortex Code) | AI-assisted development |

---

## Project Structure

```
Home360/
├── README.md                          # This file
├── .gitignore
│
├── sql/                               # All Snowflake DDL + data
│   ├── 01_setup.sql                   # Database, schema, warehouse
│   ├── 02_schema.sql                  # 7 tables
│   ├── 03_seed_data.sql               # 12 customers, May hero scenario
│   ├── 04_views.sql                   # V_CUSTOMER_360, V_POLICY_COMPARISON, V_RISK_CHANGE
│   ├── 05_procedures.sql              # SP_COMPARE_POLICY, SP_ANALYZE_RISK
│   └── 06_interaction_intelligence.sql # SP_ANALYZE_INTERACTION, Cortex Search Service
│
├── streamlit/                         # Agent copilot UI (Phase 6)
│   └── Home360_App.py
│
├── docs/
│   ├── architecture.md                # Full system architecture + data flow
│   ├── plan.md                        # Implementation phases + status
│   ├── data-dictionary.md             # Tables, columns, value domains
│   ├── cortex-ai-reference.md         # Cortex functions, prompts, outputs
│   └── demo-script.md                 # Hackathon demo walkthrough
│
└── .cortex/skills/                    # CoCo reusable skills
    ├── home360-customer-360/
    ├── home360-compare-policies/
    ├── home360-analyze-interaction/
    ├── home360-analyze-risk-change/
    └── home360-next-best-action/
```

---

## Quickstart

### Prerequisites

- Snowflake account with `ACCOUNTADMIN` role
- Cortex AI functions enabled (SENTIMENT, CLASSIFY_TEXT, SUMMARIZE, COMPLETE)
- `llama3.1-70b` model available

### Setup

Run the SQL files in order against your Snowflake account:

```sql
-- 1. Create database, schema, warehouse
@sql/01_setup.sql

-- 2. Create all 7 tables
@sql/02_schema.sql

-- 3. Load synthetic data (12 customers, May hero scenario)
@sql/03_seed_data.sql

-- 4. Create 360, comparison, and risk-change views
@sql/04_views.sql

-- 5. Create policy comparison + risk analysis procedures
@sql/05_procedures.sql

-- 6. Create interaction intelligence procedure + search service
@sql/06_interaction_intelligence.sql
```

### Verify

```sql
-- Check May's 360 context
SELECT * FROM HOME360_DB.CORE.V_CUSTOMER_360 WHERE customer_id = 'C001';

-- Compare May's policy
CALL HOME360_DB.CORE.SP_COMPARE_POLICY('C001');

-- Analyze May's risk change
CALL HOME360_DB.CORE.SP_ANALYZE_RISK('C001');

-- Analyze May's interaction
CALL HOME360_DB.CORE.SP_ANALYZE_INTERACTION('INT001');
```

---

## Data Model

```
CUSTOMER (1) ──── (1) PROPERTY ──── (*) HOME_RISK_HISTORY
    │
    ├──── (*) POLICY_VERSION  [CURRENT / RENEWAL]
    ├──── (*) CLAIM
    ├──── (*) INTERACTION
    └──── (*) ACTION_LOG
```

7 tables, 12 synthetic customers, each exercising a distinct NBA path:

| ID | Customer | Scenario |
|---|---|---|
| C001 | May Chen | **HERO** — flood-risk upgrade, premium +18%, concerned |
| C002 | Robert Diaz | Active open flood claim, anxious |
| C003 | Linda Okafor | High churn risk, actively shopping competitors |
| C004 | James Park | Low risk, routine billing question |
| C005 | Priya Singh | Post-fire rebuild, coverage gap |
| C006 | Sarah Thompson | Earthquake risk reclassification |
| C007 | Carlos Mendez | Multiple claims, non-renewal risk |
| C008 | Aisha Patel | First renewal, no history |
| C009 | David Kim | High-value property, loyalty candidate |
| C010 | Maria Garcia | Recently moved, property transfer |
| C011 | Tom Williams | Lapsed policy, win-back opportunity |
| C012 | Yuki Tanaka | Condo, HOA coverage overlap |

See `docs/data-dictionary.md` for complete column definitions and value domains.

---

## Snowflake Objects

### Tables (HOME360_DB.CORE)
| Table | Rows | Purpose |
|---|---|---|
| CUSTOMER | 12 | Demographics, tenure, value, payment history |
| PROPERTY | 12 | Physical characteristics, location, construction |
| POLICY_VERSION | 17 | Versioned policy snapshots (CURRENT + RENEWAL) |
| HOME_RISK_HISTORY | 14 | Time-series risk assessments with reasons |
| CLAIM | 8 | Claims history |
| INTERACTION | 8 | Transcripts + agent notes |
| ACTION_LOG | 0 | Audit trail (populated by app) |

### Views
| View | Purpose |
|---|---|
| V_CUSTOMER_360 | Unified context per customer (one row) |
| V_POLICY_COMPARISON | CURRENT vs RENEWAL with changes + severity |
| V_RISK_CHANGE | Previous vs current risk with direction + cause |

### Stored Procedures
| Procedure | Purpose |
|---|---|
| SP_COMPARE_POLICY(customer_id) | JSON: policy comparison + severity + key findings |
| SP_ANALYZE_RISK(customer_id) | JSON: risk change + causal chain + policy impact + communication points |
| SP_ANALYZE_INTERACTION(interaction_id) | JSON: sentiment + intent + urgency + churn signals + key phrases |

### Services
| Service | Purpose |
|---|---|
| INTERACTION_SEARCH_SVC | Semantic search over interaction transcripts |

---

## Implementation Status

| Phase | Description | Status |
|---|---|---|
| 1 | Synthetic data + schema | COMPLETE |
| 2 | Customer + Home 360 views | COMPLETE |
| 3 | Policy + risk comparison procedures | COMPLETE |
| 4 | Interaction intelligence | COMPLETE |
| 5 | Next Best Action engine | NOT STARTED |
| 6 | Agent copilot UI (Streamlit) | NOT STARTED |
| 7 | Action execution + logging | NOT STARTED |
| 8 | Testing + demo prep | NOT STARTED |

See `docs/plan.md` for detailed phase deliverables and dependency graph.

---

## CoCo Skills

Five project-local skills for AI-assisted development:

| Skill | Trigger Examples |
|---|---|
| `home360-customer-360` | "who is May", "customer context", "build 360" |
| `home360-compare-policies` | "compare policies", "what changed in renewal" |
| `home360-analyze-interaction` | "analyze this call", "customer sentiment" |
| `home360-analyze-risk-change` | "why did risk increase", "flood risk change" |
| `home360-next-best-action` | "what should the agent do", "recommend action" |

---

## Business Impact

The prototype demonstrates potential to:

- Reduce time agents spend searching across systems
- Improve consistency of renewal conversations
- Make pricing changes more transparent
- Identify retention risk earlier
- Reduce avoidable policy cancellations
- Help insurers balance customer retention with risk discipline

These are pilot hypotheses — not validated performance claims.

---

## Scalability

Home insurance renewal is the first use case. The same architecture (context -> compare -> assess -> reason -> recommend -> act -> log) extends to:

- Home insurance: claims, prevention, coverage review
- Motor insurance: renewal, risk changes, claims
- SME insurance
- Life insurance
- Lending

---

## License

Hackathon project. Internal use only.
