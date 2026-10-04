# Home360 — Full Architecture Flow

## 1. System Overview

Home360 is a Next Best Action copilot for home-insurance renewal.
It turns fragmented customer context into one explainable recommendation.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HOME360 SYSTEM                              │
│                                                                     │
│   STRUCTURED DATA          UNSTRUCTURED DATA         AI LAYER      │
│   ┌────────────┐           ┌──────────────┐    ┌──────────────┐   │
│   │ Customer   │           │ Transcripts  │    │ Cortex       │   │
│   │ Policy     │           │ Emails       │    │ SENTIMENT    │   │
│   │ Claims     │──────────▶│ Chat logs    │───▶│ CLASSIFY     │   │
│   │ Property   │           │ Agent notes  │    │ SUMMARIZE    │   │
│   │ Risk       │           └──────────────┘    │ COMPLETE     │   │
│   └────────────┘                               │ Search       │   │
│         │                                       └──────┬───────┘   │
│         │              ┌───────────────┐               │           │
│         └─────────────▶│ DECISION      │◀──────────────┘           │
│                        │ ENGINE        │                           │
│                        └───────┬───────┘                           │
│                                │                                    │
│                        ┌───────▼───────┐                           │
│                        │ AGENT UI      │                           │
│                        │ (Streamlit)   │                           │
│                        └───────┬───────┘                           │
│                                │                                    │
│                        ┌───────▼───────┐                           │
│                        │ ACTION LOG    │                           │
│                        └───────────────┘                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. End-to-End Flow

The complete journey from customer contact to logged action:

```
PHASE           STEP                          COMPONENT                    SNOWFLAKE OBJECT / FUNCTION
─────           ────                          ─────────                    ──────────────────────────

TRIGGER         Customer contacts insurer     External event               —
                (call / email / chat)

        ┌───────────────────────────────────────────────────────────────────────────────────────────┐
        │ LAYER 1 — INGEST                                                                         │
        │                                                                                           │
   1    │ Record interaction              Interaction capture              INTERACTION table          │
        │ (transcript, channel,                                            INSERT INTO INTERACTION   │
        │  timestamp)                                                                               │
        └───────────────────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────────────────────────────────────────────────────────────────────────────────┐
        │ LAYER 2 — IDENTIFY                                                                       │
        │                                                                                           │
   2    │ Match customer                  Customer lookup                  CUSTOMER table             │
        │ (by name, ID, phone, policy#)                                    SELECT ... WHERE ...      │
        │                                                                                           │
   3    │ Classify intent                 Cortex AI                        CORTEX.CLASSIFY_TEXT(      │
        │ (renewal / claim / billing /                                       transcript,             │
        │  cancellation / complaint)                                         ['renewal_inquiry',     │
        │                                                                     'claim_status', ...]   │
        │                                                                  )                         │
        │                                                                                           │
   4    │ Measure sentiment               Cortex AI                        CORTEX.SENTIMENT(         │
        │ (-1.0 angry ... +1.0 positive)                                     transcript             │
        │                                                                  )                         │
        │                                                                                           │
   5    │ Estimate urgency + signals      Cortex AI                        CORTEX.COMPLETE(          │
        │ (urgency, churn signal,                                            'llama3.1-70b',         │
        │  pricing concern, coverage                                         structured prompt       │
        │  concern, complaint signal,                                      ) → JSON                  │
        │  key phrases)                                                                             │
        │                                                                                           │
   6    │ Summarize transcript            Cortex AI                        CORTEX.SUMMARIZE(         │
        │ (2-3 sentence digest)                                              transcript             │
        │                                                                  )                         │
        └───────────────────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────────────────────────────────────────────────────────────────────────────────┐
        │ LAYER 3 — RETRIEVE CONTEXT (Customer + Home 360)                                         │
        │                                                                                           │
   7    │ Customer demographics           Customer context                 CUSTOMER table             │
        │ (tenure, value, payment                                          V_CUSTOMER_360 view       │
        │  history, churn score)                                                                    │
        │                                                                                           │
   8    │ Current policy terms            Policy context                   POLICY_VERSION             │
        │ (premium, deductible,                                            WHERE version='CURRENT'   │
        │  coverage, exclusions)                                                                    │
        │                                                                                           │
   9    │ Proposed renewal terms          Policy context                   POLICY_VERSION             │
        │ (same fields, new values)                                        WHERE version='RENEWAL'   │
        │                                                                                           │
  10    │ Claims history                  Claims context                   CLAIM table                │
        │ (count, open, severity,                                          WHERE customer_id = ...   │
        │  recent activity)                                                                         │
        │                                                                                           │
  11    │ Property characteristics        Property context                 PROPERTY table             │
        │ (type, location, age,                                                                     │
        │  construction)                                                                            │
        │                                                                                           │
  12    │ Risk assessment history         Risk context                     HOME_RISK_HISTORY          │
        │ (historical + current,                                           JOIN PROPERTY              │
        │  flood/fire/earthquake,                                          ORDER BY assessment_date   │
        │  overall score, reason)                                                                   │
        │                                                                                           │
  13    │ Past interactions               Interaction history              INTERACTION table           │
        │ (prior calls, emails,                                            Cortex Search Service     │
        │  resolved issues)                                                (semantic retrieval)      │
        └───────────────────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────────────────────────────────────────────────────────────────────────────────┐
        │ LAYER 4 — COMPARE + ANALYZE                                                              │
        │                                                                                           │
  14    │ Policy comparison               Comparison engine                V_POLICY_COMPARISON view   │
        │                                                                                           │
        │   For each field:                                                                         │
        │   ┌─────────────────────┬──────────┬──────────┬──────────┬───────┬──────────┐            │
        │   │ Field               │ CURRENT  │ RENEWAL  │ Change   │  %    │ Severity │            │
        │   ├─────────────────────┼──────────┼──────────┼──────────┼───────┼──────────┤            │
        │   │ Annual Premium      │ $8,500   │ $10,030  │ +$1,530  │ +18%  │ MAJOR    │            │
        │   │ General Deductible  │ $1,500   │ $1,500   │ —        │ —     │ —        │            │
        │   │ Building Coverage   │ $250,000 │ $250,000 │ —        │ —     │ —        │            │
        │   │ Contents Coverage   │ $75,000  │ $75,000  │ —        │ —     │ —        │            │
        │   │ Flood Coverage      │ $50,000  │ $35,000  │ -$15,000 │ -30%  │ MAJOR    │            │
        │   │ Flood Deductible    │ $2,500   │ $5,000   │ +$2,500  │ +100% │ MAJOR    │            │
        │   └─────────────────────┴──────────┴──────────┴──────────┴───────┴──────────┘            │
        │                                                                                           │
        │   Exclusions diff:                                                                        │
        │     Added:   sewer backup                                                                 │
        │     Removed: (none)                                                                       │
        │                                                                                           │
        │   Severity classification:                                                                │
        │     MAJOR    — premium > 15%, coverage reduction > 20%, deductible > 50%                  │
        │     MODERATE — premium 5-15%, coverage 10-20%, deductible 20-50%                          │
        │     MINOR    — below moderate thresholds                                                  │
        │                                                                                           │
  15    │ Risk change analysis            Risk analysis engine             V_RISK_CHANGE view         │
        │                                                                                           │
        │   ┌─────────────────┬──────────────────┬──────────────────┬───────────┐                   │
        │   │ Dimension       │ Previous (2024)  │ Current (2026)   │ Direction │                   │
        │   ├─────────────────┼──────────────────┼──────────────────┼───────────┤                   │
        │   │ Flood Risk      │ MEDIUM           │ HIGH             │ ▲ UP      │                   │
        │   │ Fire Risk       │ LOW              │ LOW              │ —         │                   │
        │   │ Earthquake Risk │ LOW              │ LOW              │ —         │                   │
        │   │ Overall Score   │ 0.42             │ 0.78             │ ▲ +86%    │                   │
        │   └─────────────────┴──────────────────┴──────────────────┴───────────┘                   │
        │                                                                                           │
        │   Root cause: FEMA remapped Cedar Falls to Zone AE (high-risk)                           │
        │                                                                                           │
        │   Causal chain:                                                                           │
        │     External event (FEMA remap)                                                           │
        │       → Flood risk: MEDIUM → HIGH                                                        │
        │         → Premium: +18%                                                                  │
        │         → Flood coverage: -30%                                                           │
        │         → Flood deductible: +100%                                                        │
        │         → New exclusion: sewer backup                                                    │
        │                                                                                           │
  16    │ Interaction intelligence        AI analysis output               (from Layer 2 steps 3-6) │
        │                                                                                           │
        │   ┌───────────────────────────────────────────────────┐                                   │
        │   │ Intent:           renewal_inquiry                 │                                   │
        │   │ Sentiment:        -0.37 (Concerned)               │                                   │
        │   │ Urgency:          MEDIUM                          │                                   │
        │   │ Churn Signal:     MODERATE                        │                                   │
        │   │ Pricing Concern:  YES                             │                                   │
        │   │ Coverage Concern: YES                             │                                   │
        │   │ Complaint:        NO                              │                                   │
        │   │ Key Phrases:                                      │                                   │
        │   │   • "insured with you for years"                  │                                   │
        │   │   • "why has the price increased"                 │                                   │
        │   │   • "haven't made any major claims"               │                                   │
        │   │   • "look at other options"                       │                                   │
        │   └───────────────────────────────────────────────────┘                                   │
        └───────────────────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────────────────────────────────────────────────────────────────────────────────┐
        │ LAYER 5 — REASON (Next Best Action Engine)                                               │
        │                                                                                           │
        │ The NBA engine does NOT use single-rule logic.                                            │
        │ It evaluates 6 signal categories simultaneously.                                          │
        │                                                                                           │
  17    │ Signal assembly                                                                           │
        │                                                                                           │
        │   CUSTOMER SIGNALS          POLICY SIGNALS           CLAIMS SIGNALS                       │
        │   ┌──────────────────┐      ┌──────────────────┐     ┌──────────────────┐                │
        │   │ tenure: 6.5 yr   │      │ premium: +18%    │     │ total: 1         │                │
        │   │ value: $18,500   │      │ deductible: same │     │ open: 0          │                │
        │   │ payment: EXCEL   │      │ flood cov: -30%  │     │ severity: low    │                │
        │   │ churn: 0.35      │      │ flood ded: +100% │     │ recent: none     │                │
        │   └──────────────────┘      │ new excl: yes    │     └──────────────────┘                │
        │                             └──────────────────┘                                          │
        │   PROPERTY SIGNALS          RISK SIGNALS             INTERACTION SIGNALS                  │
        │   ┌──────────────────┐      ┌──────────────────┐     ┌──────────────────┐                │
        │   │ type: SINGLE_FAM │      │ flood: MED→HIGH  │     │ intent: renewal  │                │
        │   │ age: 22 yr       │      │ reason: FEMA     │     │ sentiment: -0.37 │                │
        │   │ construct: WOOD  │      │ score: +86%      │     │ urgency: MEDIUM  │                │
        │   │ location: IA     │      │ direction: UP    │     │ churn: MODERATE  │                │
        │   └──────────────────┘      └──────────────────┘     │ price concern: Y │                │
        │                                                       │ coverage con: Y  │                │
        │                                                       └──────────────────┘                │
        │                                                                                           │
  18    │ Candidate generation                                 CORTEX.COMPLETE(llama3.1-70b)        │
        │                                                                                           │
        │   All signals assembled into a structured prompt.                                         │
        │   The LLM generates and scores 3-5 candidates:                                           │
        │                                                                                           │
        │   ┌──────┬──────────────────────────────────────────────────────┬───────┐                 │
        │   │ Code │ Candidate Action                                    │ Score │                 │
        │   ├──────┼──────────────────────────────────────────────────────┼───────┤                 │
        │   │  C   │ Explain changes + offer alternative deductible/     │  9/10 │ ◀── SELECTED   │
        │   │      │ coverage option to manage premium                   │       │                 │
        │   │  B   │ Explain changes + recommend standard renewal        │  7/10 │                 │
        │   │  D   │ Recommend risk-reduction measures first             │  6/10 │                 │
        │   │  E   │ Escalate to retention specialist                    │  5/10 │                 │
        │   │  A   │ Explain renewal changes only                        │  4/10 │                 │
        │   └──────┴──────────────────────────────────────────────────────┴───────┘                 │
        │                                                                                           │
        │   Full candidate menu:                                                                    │
        │     A — Explain renewal changes only (informational)                                      │
        │     B — Explain + recommend renewal (moderate concern)                                    │
        │     C — Explain + offer alternative option (price-sensitive)                               │
        │     D — Recommend risk-reduction measures (risk-driven)                                   │
        │     E — Escalate to retention specialist (high churn)                                     │
        │     F — Escalate to underwriting specialist (complex risk)                                │
        │     G — Request additional property information (incomplete data)                         │
        │                                                                                           │
  19    │ Ranking + selection                                                                       │
        │                                                                                           │
        │   Scoring criteria (each 1-10):                                                           │
        │     • Customer retention likelihood                                                       │
        │     • Appropriateness for sentiment/urgency                                               │
        │     • Business risk management                                                            │
        │     • Customer satisfaction potential                                                      │
        │                                                                                           │
        │   Selection: highest composite score wins.                                                │
        │                                                                                           │
  20    │ Explainability construction                                                               │
        │                                                                                           │
        │   The output MUST separate:                                                               │
        │                                                                                           │
        │   ┌─────────────────────────────────────────────────────────────────────┐                 │
        │   │ FACTS (from data)                                                   │                 │
        │   │   • May has been a customer for 6.5 years                           │                 │
        │   │   • She has EXCELLENT payment history                               │                 │
        │   │   • Only 1 claim in 6+ years ($1,800 theft, closed 2022)            │                 │
        │   │   • Flood risk reclassified MEDIUM → HIGH (FEMA remap Jan 2026)     │                 │
        │   │   • Premium increased 18% ($8,500 → $10,030)                        │                 │
        │   │   • Flood coverage reduced 30% ($50k → $35k)                        │                 │
        │   │   • Flood deductible doubled ($2,500 → $5,000)                      │                 │
        │   │   • New exclusion: sewer backup                                     │                 │
        │   ├─────────────────────────────────────────────────────────────────────┤                 │
        │   │ AI INTERPRETATION                                                   │                 │
        │   │   • Customer is concerned but not yet hostile (sentiment -0.37)      │                 │
        │   │   • Retention risk is MODERATE — she mentioned other options         │                 │
        │   │   • She values loyalty and expects it to be reciprocated            │                 │
        │   │   • Price and coverage are both concerns                            │                 │
        │   ├─────────────────────────────────────────────────────────────────────┤                 │
        │   │ RECOMMENDED ACTION                                                  │                 │
        │   │   Explain the risk change transparently, show how it affected       │                 │
        │   │   her renewal terms, and offer an alternative coverage/deductible   │                 │
        │   │   configuration that preserves essential protection while           │                 │
        │   │   managing the premium increase.                                    │                 │
        │   └─────────────────────────────────────────────────────────────────────┘                 │
        │                                                                                           │
        │   Also includes:                                                                          │
        │     • WHY alternatives were NOT selected                                                  │
        │     • Agent talking points                                                                │
        │     • Risk flags                                                                          │
        └───────────────────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────────────────────────────────────────────────────────────────────────────────┐
        │ LAYER 6 — PRESENT (Agent Copilot UI)                                                     │
        │                                                                                           │
        │ Streamlit in Snowflake — single-page operational copilot                                  │
        │                                                                                           │
  21    │ ┌─────────────────────────────────────────────────────────────────────────────────────┐   │
        │ │                         HOME360 COPILOT                                             │   │
        │ │  ┌─────────────────────────────────────────────────────────────────────────────┐   │   │
        │ │  │ SECTION 1 — CUSTOMER CONTEXT                                                │   │   │
        │ │  │ May Chen │ 6.5 yr │ $18,500 value │ EXCELLENT payment │ 1 claim │ Churn: ▲ │   │   │
        │ │  └─────────────────────────────────────────────────────────────────────────────┘   │   │
        │ │  ┌─────────────────────────────────────────────────────────────────────────────┐   │   │
        │ │  │ SECTION 2 — RENEWAL COMPARISON                                              │   │   │
        │ │  │                                                                              │   │   │
        │ │  │   CURRENT          RENEWAL           CHANGE                                  │   │   │
        │ │  │   $8,500    ──▶    $10,030           +18%  ██████████ MAJOR                  │   │   │
        │ │  │   $50,000   ──▶    $35,000           -30%  ████████   MAJOR                  │   │   │
        │ │  │   $2,500    ──▶    $5,000           +100%  ██████████ MAJOR                  │   │   │
        │ │  │   + New exclusion: sewer backup                                              │   │   │
        │ │  └─────────────────────────────────────────────────────────────────────────────┘   │   │
        │ │  ┌─────────────────────────────────────────────────────────────────────────────┐   │   │
        │ │  │ SECTION 3 — PROPERTY RISK                                                   │   │   │
        │ │  │                                                                              │   │   │
        │ │  │   Flood Risk:   MEDIUM ─────▶ HIGH   (FEMA remap Jan 2026)                  │   │   │
        │ │  │   Overall:      0.42  ─────▶ 0.78   (+86%)                                  │   │   │
        │ │  │   Root cause:   FEMA Zone X → Zone AE, Cedar River projections              │   │   │
        │ │  └─────────────────────────────────────────────────────────────────────────────┘   │   │
        │ │  ┌─────────────────────────────────────────────────────────────────────────────┐   │   │
        │ │  │ SECTION 4 — CURRENT INTERACTION                                             │   │   │
        │ │  │                                                                              │   │   │
        │ │  │   Channel: CALL │ 2026-10-03 09:14                                          │   │   │
        │ │  │   Intent: renewal_inquiry │ Sentiment: Concerned (-0.37)                    │   │   │
        │ │  │   Churn signal: MODERATE │ Urgency: MEDIUM                                  │   │   │
        │ │  │   Key: "insured for years" · "price increased" · "look at other options"    │   │   │
        │ │  │                                                                              │   │   │
        │ │  │   ┌──────────────────────────────────────────────────────────────────────┐  │   │   │
        │ │  │   │ "I've been insured with you for years now and I'm calling because   │  │   │   │
        │ │  │   │ I got my renewal letter. I want to renew my home insurance but I'm  │  │   │   │
        │ │  │   │ confused — why has the price increased this year?"                   │  │   │   │
        │ │  │   └──────────────────────────────────────────────────────────────────────┘  │   │   │
        │ │  └─────────────────────────────────────────────────────────────────────────────┘   │   │
        │ │  ┌─────────────────────────────────────────────────────────────────────────────┐   │   │
        │ │  │ SECTION 5 — NEXT BEST ACTION                               Priority: HIGH  │   │   │
        │ │  │                                                                              │   │   │
        │ │  │ ▶ Explain risk change + offer alternative coverage option                   │   │   │
        │ │  │                                                                              │   │   │
        │ │  │ WHY: May is a loyal, high-value customer who has never filed a major        │   │   │
        │ │  │ claim. The premium increase is driven by an external risk reclassification, │   │   │
        │ │  │ not her behavior. Offering an adjusted coverage option shows the insurer    │   │   │
        │ │  │ values the relationship and reduces the chance she shops competitors.       │   │   │
        │ │  │                                                                              │   │   │
        │ │  │ EVIDENCE                                                                     │   │   │
        │ │  │   • 6.5 years tenure, EXCELLENT payment                                     │   │   │
        │ │  │   • Only 1 minor claim in entire history                                    │   │   │
        │ │  │   • Flood risk changed due to FEMA remap (not customer behavior)            │   │   │
        │ │  │   • She explicitly mentioned looking at other options                       │   │   │
        │ │  │                                                                              │   │   │
        │ │  │ TALKING POINTS                                                               │   │   │
        │ │  │   1. Acknowledge her loyalty and clean history                              │   │   │
        │ │  │   2. Explain the FEMA flood-zone change clearly                             │   │   │
        │ │  │   3. Walk through each policy change and why                                │   │   │
        │ │  │   4. Present the alternative option with adjusted deductible                │   │   │
        │ │  │   5. Mention risk-reduction steps she can take                              │   │   │
        │ │  │                                                                              │   │   │
        │ │  │ ALTERNATIVES                                                                 │   │   │
        │ │  │   [B] Explain + standard renewal (7/10) — misses retention opportunity     │   │   │
        │ │  │   [D] Risk-reduction first (6/10) — delays resolution, urgency is medium   │   │   │
        │ │  │   [E] Escalate retention (5/10) — premature, agent can handle              │   │   │
        │ │  │                                                                              │   │   │
        │ │  │ ┌─────────────┐  ┌─────────────┐  ┌──────────────┐                         │   │   │
        │ │  │ │ TAKE ACTION │  │   MODIFY    │  │  ESCALATE   │                         │   │   │
        │ │  │ └─────────────┘  └─────────────┘  └──────────────┘                         │   │   │
        │ │  └─────────────────────────────────────────────────────────────────────────────┘   │   │
        │ └─────────────────────────────────────────────────────────────────────────────────────┘   │
        └───────────────────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────────────────────────────────────────────────────────────────────────────────┐
        │ LAYER 7 — ACT + LOG                                                                      │
        │                                                                                           │
  22    │ Agent clicks [ TAKE ACTION ]                                                              │
        │                                                                                           │
        │   → System simulates execution:                                                           │
        │     "Renewal explanation prepared. Alternative coverage option                            │
        │      with adjusted flood deductible sent to May Chen."                                   │
        │                                                                                           │
  23    │ Insert into ACTION_LOG:                                          ACTION_LOG table          │
        │                                                                                           │
        │   ┌────────────────────┬────────────────────────────────────────────────────────┐         │
        │   │ action_id          │ ACT-20261003-001                                      │         │
        │   │ customer_id        │ C001                                                  │         │
        │   │ interaction_id     │ INT001                                                │         │
        │   │ recommended_action │ {full NBA JSON output}                                │         │
        │   │ action_taken       │ "Explained risk change, presented alternative option" │         │
        │   │ action_timestamp   │ 2026-10-03 09:22:00                                   │         │
        │   │ status             │ EXECUTED                                               │         │
        │   └────────────────────┴────────────────────────────────────────────────────────┘         │
        │                                                                                           │
        │   This closes the feedback loop. Future iterations could use                              │
        │   ACTION_LOG data to evaluate which recommendations lead to                               │
        │   successful renewals and tune the engine accordingly.                                    │
        └───────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Snowflake Technical Architecture

### Compute

```
┌────────────────────────────────────────────────────────────────┐
│                    SNOWFLAKE ACCOUNT (JK62080)                 │
│                                                                 │
│  WAREHOUSE: HOME360_WH (XS, auto-suspend 60s, auto-resume)    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Runs: SQL queries, view materialization, Streamlit app   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  CORTEX AI (Snowflake-managed compute, no user warehouse)      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ SENTIMENT    — per-transcript, ~100ms                    │  │
│  │ CLASSIFY_TEXT — per-transcript, ~200ms                   │  │
│  │ SUMMARIZE    — per-transcript, ~300ms                    │  │
│  │ COMPLETE     — llama3.1-70b, structured prompts, ~2-5s   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  CORTEX SEARCH SERVICE (Snowflake-managed)                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Index on INTERACTION.raw_transcript                      │  │
│  │ Enables: "has this customer raised this before?"         │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

### Storage

```
HOME360_DB
└── CORE (schema)
    │
    │  ── BASE TABLES ──────────────────────────────────────────
    │
    ├── CUSTOMER              12 rows    Demographics + value
    ├── PROPERTY              12 rows    Physical characteristics
    ├── POLICY_VERSION        17 rows    Versioned policy snapshots
    ├── HOME_RISK_HISTORY     14 rows    Time-series risk assessments
    ├── CLAIM                  8 rows    Claims history
    ├── INTERACTION            8 rows    Transcripts + notes
    ├── ACTION_LOG             0 rows    Audit trail (written by app)
    │
    │  ── VIEWS (Phase 2) ──────────────────────────────────────
    │
    ├── V_CUSTOMER_360        Unified context per customer
    ├── V_POLICY_COMPARISON   CURRENT vs RENEWAL side-by-side
    └── V_RISK_CHANGE         Previous vs current risk assessment
```

### Data Flow Diagram

```
                    ┌──────────────┐
                    │   CUSTOMER   │
                    └──────┬───────┘
                           │ customer_id
              ┌────────────┼────────────┬──────────────┬───────────────┐
              ▼            ▼            ▼              ▼               ▼
       ┌──────────┐ ┌───────────┐ ┌─────────┐ ┌────────────┐ ┌────────────┐
       │ PROPERTY │ │ POLICY_   │ │  CLAIM  │ │INTERACTION │ │ACTION_LOG  │
       │          │ │ VERSION   │ │         │ │            │ │            │
       └────┬─────┘ └───────────┘ └─────────┘ └─────┬──────┘ └────────────┘
            │                                        │
            ▼                                        │
       ┌──────────────┐                              │
       │ HOME_RISK_   │                              │
       │ HISTORY      │◀─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┘ (via ACTION_LOG FK)
       └──────────────┘

  FK relationships:
    PROPERTY.customer_id         → CUSTOMER.customer_id
    POLICY_VERSION.customer_id   → CUSTOMER.customer_id
    CLAIM.customer_id            → CUSTOMER.customer_id
    INTERACTION.customer_id      → CUSTOMER.customer_id
    ACTION_LOG.customer_id       → CUSTOMER.customer_id
    ACTION_LOG.interaction_id    → INTERACTION.interaction_id
    HOME_RISK_HISTORY.property_id → PROPERTY.property_id
```

---

## 4. Cortex AI Integration Map

```
                        INTERACTION.raw_transcript
                                    │
                 ┌──────────────────┼──────────────────┬─────────────────┐
                 ▼                  ▼                  ▼                 ▼
          ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
          │  SENTIMENT  │   │  CLASSIFY   │   │  SUMMARIZE  │   │  COMPLETE   │
          │             │   │  _TEXT      │   │             │   │  (70b)      │
          │ Returns:    │   │ Returns:    │   │ Returns:    │   │ Returns:    │
          │ float       │   │ {label}     │   │ string      │   │ JSON        │
          │ -1.0 to 1.0│   │ from list   │   │ 2-3 lines   │   │ structured  │
          └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
                 │                 │                  │                 │
                 │    sentiment    │    intent        │    summary      │   urgency, churn,
                 │    score        │    label         │    text         │   key phrases,
                 │                 │                  │                 │   signals (JSON)
                 └────────────────┬┴──────────────────┴─────────────────┘
                                  │
                                  ▼
                     ┌────────────────────────┐
                     │  INTERACTION SIGNALS   │
                     │  (combined output)     │
                     └────────────┬───────────┘
                                  │
                                  ▼
         ┌──────────────────────────────────────────────────┐
         │              NBA ENGINE PROMPT                    │
         │                                                   │
         │  Customer signals    (from CUSTOMER table)        │
         │  + Policy signals    (from V_POLICY_COMPARISON)   │
         │  + Claims signals    (from CLAIM table)           │
         │  + Property signals  (from PROPERTY table)        │
         │  + Risk signals      (from V_RISK_CHANGE)         │
         │  + Interaction signals (from above)               │
         │                                                   │
         └──────────────────────┬───────────────────────────┘
                                │
                                ▼
                   ┌────────────────────────┐
                   │  CORTEX.COMPLETE       │
                   │  (llama3.1-70b)        │
                   │                        │
                   │  Input: all 6 signal   │
                   │  categories as          │
                   │  structured text        │
                   │                        │
                   │  Output: JSON with     │
                   │  • recommended_action  │
                   │  • why_this_action     │
                   │  • evidence[]          │
                   │  • alternatives[]      │
                   │  • talking_points[]    │
                   │  • risk_flags[]        │
                   └────────────────────────┘
```

---

## 5. Skill Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      CoCo SKILLS (.cortex/skills/)                 │
│                                                                     │
│  ┌─────────────────────┐                                           │
│  │ home360-customer-360│  Assembles unified context from all       │
│  │                     │  6 data domains for one customer.         │
│  └──────────┬──────────┘  Foundation for all downstream skills.    │
│             │                                                       │
│     ┌───────┴───────┬───────────────┬───────────────┐              │
│     ▼               ▼               ▼               │              │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐      │              │
│  │ compare- │  │ analyze- │  │ analyze-     │      │              │
│  │ policies │  │ risk-    │  │ interaction  │      │              │
│  │          │  │ change   │  │              │      │              │
│  │ CURRENT  │  │ Previous │  │ SENTIMENT    │      │              │
│  │ vs       │  │ vs       │  │ CLASSIFY     │      │              │
│  │ RENEWAL  │  │ Current  │  │ SUMMARIZE    │      │              │
│  │          │  │ risk     │  │ COMPLETE     │      │              │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘      │              │
│       │              │               │              │              │
│       └──────────────┴───────────────┴──────────────┘              │
│                              │                                      │
│                              ▼                                      │
│                    ┌──────────────────┐                             │
│                    │ home360-next-    │  Consumes all upstream      │
│                    │ best-action      │  outputs. Generates ranked  │
│                    │                  │  candidates via COMPLETE.   │
│                    │                  │  Returns explainable NBA.   │
│                    └──────────────────┘                             │
└─────────────────────────────────────────────────────────────────────┘

  Invocation chain (typical):
    1. home360-customer-360      → gather all data
    2. home360-compare-policies  → policy diff
    3. home360-analyze-risk-change → risk diff + root cause
    4. home360-analyze-interaction → transcript intelligence
    5. home360-next-best-action   → combine all → NBA output
```

---

## 6. Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     LOCAL DEVELOPMENT                               │
│                                                                     │
│  VS Code + Snowflake Extension + CoCo                              │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  Snowflake/                                               │      │
│  │  ├── .cortex/skills/     (5 CoCo skills)                 │      │
│  │  ├── docs/               (architecture documentation)    │      │
│  │  ├── sql/                (DDL + seed data scripts)       │      │
│  │  └── streamlit/          (copilot app — Phase 6)         │      │
│  └──────────────────────────────────────────────────────────┘      │
│           │                                                         │
│           │  sql_execute / snow streamlit deploy                    │
│           ▼                                                         │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │              SNOWFLAKE ACCOUNT (JK62080)                  │      │
│  │                                                           │      │
│  │  HOME360_DB.CORE                                          │      │
│  │  ├── 7 tables (base data)                                │      │
│  │  ├── 3 views (360, comparison, risk change)              │      │
│  │  └── Cortex Search Service (on INTERACTION)              │      │
│  │                                                           │      │
│  │  HOME360_WH (XS warehouse)                               │      │
│  │                                                           │      │
│  │  Streamlit App (in-Snowflake, Phase 6)                   │      │
│  │  └── Calls: views + Cortex AI functions                  │      │
│  └──────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 7. Security & Access

```
ROLE: ACCOUNTADMIN (hackathon / trial account)

  In production, this would decompose to:
  ┌────────────────────────────────────────────────┐
  │ HOME360_ADMIN      — DDL, schema changes       │
  │ HOME360_WRITER     — INSERT into ACTION_LOG    │
  │ HOME360_READER     — SELECT on all tables/views│
  │ HOME360_APP_ROLE   — Streamlit execution       │
  └────────────────────────────────────────────────┘

  Cortex AI functions run under caller's role.
  No external access integrations needed for MVP.
```

---

## 8. Scalability Path

```
HOME INSURANCE — RENEWAL (this MVP)
│
├── HOME INSURANCE — CLAIMS
│   Same architecture, different trigger:
│   claim filed → context → compare → assess → recommend → act
│
├── HOME INSURANCE — PREVENTION
│   Proactive: risk change detected → reach out before renewal
│
├── MOTOR INSURANCE — RENEWAL
│   Same flow, different data model:
│   VEHICLE replaces PROPERTY, DRIVING_RISK replaces HOME_RISK
│
├── SME INSURANCE
│   BUSINESS_PROPERTY replaces PROPERTY
│   Add REVENUE_RISK, EMPLOYEE_COUNT signals
│
└── CROSS-PRODUCT
    Unified CUSTOMER table, product-specific context tables,
    shared NBA engine with product-specific candidate actions.

    The reusable core:
    CONTEXT → COMPARE → ASSESS → REASON → RECOMMEND → ACT → LOG
```

---

## 9. Implementation Phase Tracker

| Phase | Description                          | Status      | Key Deliverables                        |
|-------|--------------------------------------|-------------|-----------------------------------------|
| 1     | Synthetic data + schema              | COMPLETE    | 7 tables, 12 customers, May hero data   |
| 2     | Customer + Home 360 views            | NOT STARTED | V_CUSTOMER_360, V_POLICY_COMPARISON, V_RISK_CHANGE |
| 3     | Policy + risk comparison logic       | NOT STARTED | Comparison queries, severity classification |
| 4     | Interaction intelligence             | NOT STARTED | Cortex AI pipeline, Search Service      |
| 5     | Next Best Action engine              | NOT STARTED | Stored procedure, prompt engineering     |
| 6     | Agent copilot UI (Streamlit)         | NOT STARTED | Single-page app with 5 sections         |
| 7     | Action execution + logging           | NOT STARTED | ACTION_LOG writes, confirmation flow    |
| 8     | Testing + demo prep                  | NOT STARTED | All 12 customer scenarios validated     |
