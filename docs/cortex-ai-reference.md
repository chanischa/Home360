# Home360 — Cortex AI Reference

Every Cortex AI function used in Home360, with the exact call pattern, prompt (where applicable), and expected output.

---

## 1. CORTEX.SENTIMENT

**Used in:** `SP_ANALYZE_INTERACTION`

**Purpose:** Score the emotional tone of an interaction transcript.

**Call:**
```sql
SELECT SNOWFLAKE.CORTEX.SENTIMENT(:transcript) AS sentiment_score;
```

**Input:** Raw transcript text (VARCHAR, up to 5000 chars).

**Output:** FLOAT between -1.0 (very negative) and +1.0 (very positive).

**Label mapping (used in procedure):**

| Score Range | Label |
|---|---|
| > 0.3 | Positive |
| 0.0 to 0.3 | Neutral |
| -0.3 to 0.0 | Mildly Concerned |
| -0.6 to -0.3 | Concerned |
| < -0.6 | Very Negative |

**Observed results on seed data:**

| Interaction | Sentiment | Label |
|---|---|---|
| INT001 (May renewal) | 0.5234 | Positive (note: polite tone despite concern) |
| INT002 (Robert claim) | 0.1484 | Neutral |
| INT003 (Linda churn) | 0.2266 | Neutral |
| INT004 (James billing) | 0.4141 | Positive |

**Note:** SENTIMENT scores the linguistic tone, not the underlying emotion. Polite but concerned transcripts (like May's) can score positive. The deep extraction via COMPLETE captures the actual customer emotion more accurately.

---

## 2. CORTEX.CLASSIFY_TEXT

**Used in:** `SP_ANALYZE_INTERACTION`

**Purpose:** Classify the primary intent of the interaction.

**Call:**
```sql
SELECT SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
    :transcript,
    ['renewal_inquiry', 'claim_status', 'billing_question',
     'cancellation_request', 'coverage_concern', 'complaint',
     'general_inquiry']
) AS intent;
```

**Input:** Raw transcript text + array of candidate labels.

**Output:** JSON object `{"label": "selected_label"}`.

**Intent categories:**

| Label | Description |
|---|---|
| renewal_inquiry | Customer asking about renewal terms, premium changes |
| claim_status | Customer checking on an existing claim |
| billing_question | Invoice, payment, autopay questions |
| cancellation_request | Customer wants to cancel or not renew |
| coverage_concern | Questions about what's covered |
| complaint | General dissatisfaction or formal complaint |
| general_inquiry | Anything else |

**Observed results on seed data:**

| Interaction | Classified As |
|---|---|
| INT001 (May) | renewal_inquiry |
| INT002 (Robert) | claim_status |
| INT003 (Linda) | renewal_inquiry |
| INT004 (James) | billing_question |

---

## 3. CORTEX.SUMMARIZE

**Used in:** `SP_ANALYZE_INTERACTION`

**Purpose:** Generate a 2-3 sentence summary of the interaction.

**Call:**
```sql
SELECT SNOWFLAKE.CORTEX.SUMMARIZE(:transcript) AS summary;
```

**Input:** Raw transcript text.

**Output:** VARCHAR — concise summary.

**Example output (May):**
> "Customer inquired about an increase in home insurance renewal price and expressed concern. Agent promised to review the policy details and explain the reasons behind the price change."

---

## 4. CORTEX.COMPLETE (llama3.1-70b)

**Used in:** `SP_ANALYZE_INTERACTION` (deep signal extraction), `SP_NEXT_BEST_ACTION` (NBA reasoning — Phase 5)

### 4a. Deep Signal Extraction (Phase 4)

**Purpose:** Extract structured signals that SENTIMENT and CLASSIFY_TEXT cannot capture: urgency, churn probability, specific concerns, key phrases, recommended agent tone.

**Call:**
```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-70b',
    :structured_prompt
) AS deep_analysis;
```

**Prompt template:**
```
You are an insurance interaction analyst. Analyze this customer
interaction transcript and return ONLY a valid JSON object with
these exact fields (no markdown, no explanation, just the JSON):

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
{transcript}
```

**Output:** JSON string (parsed with PARSE_JSON, fallback on parse failure).

**Signal definitions:**

| Field | Values | Description |
|---|---|---|
| urgency | low / medium / high / critical | How quickly the agent needs to act |
| churn_signal | none / low / moderate / high | Likelihood customer may leave |
| pricing_concern | true / false | Customer raised price/cost issues |
| coverage_concern | true / false | Customer asked about coverage gaps |
| complaint_signal | true / false | Customer expressed formal dissatisfaction |
| key_phrases | array of strings | Direct quotes capturing customer intent |
| recommended_tone | reassuring / empathetic / urgent / informational / retention-focused | How the agent should respond |
| customer_emotion | calm / concerned / frustrated / angry / anxious / satisfied | Actual customer emotional state |

**Observed results (May):**
```json
{
  "urgency": "medium",
  "churn_signal": "moderate",
  "pricing_concern": true,
  "coverage_concern": true,
  "complaint_signal": false,
  "key_phrases": [
    "why has the price increased this year?",
    "If the price keeps going up I might have to look at other options"
  ],
  "recommended_tone": "reassuring",
  "customer_emotion": "concerned"
}
```

### 4b. NBA Reasoning (Phase 5 — not yet implemented)

**Purpose:** Generate ranked candidate actions with evidence and explainability.

**Model:** llama3.1-70b

**Prompt:** Assembles all 6 signal categories (customer, policy, claims, property, risk, interaction) into a structured prompt. Requests JSON output with: recommended_action, why_this_action, evidence, alternative_actions, agent_talking_points, risk_flags.

**Fallback:** If JSON parsing fails, retry once with llama3.1-8b.

---

## 5. Cortex Search Service

**Service:** `INTERACTION_SEARCH_SVC`

**Purpose:** Semantic search over past interaction transcripts. Enables "has this customer raised this concern before?" and "which customers complained about premium increases?"

**Call:**
```sql
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'HOME360_DB.CORE.INTERACTION_SEARCH_SVC',
        '{
            "query": "your natural language query",
            "columns": ["customer_id", "interaction_type", "raw_transcript"],
            "limit": 5
        }'
    )
) AS results;
```

**Configuration:**
- Source: `INTERACTION.raw_transcript`
- Attributes: customer_id, interaction_type, interaction_timestamp
- Warehouse: HOME360_WH
- Target lag: 1 hour

**Output:** JSON with `results` array, each containing the requested columns plus `@scores` (cosine_similarity, reranker_score, text_match).

---

## Retention Risk Derivation

The `retention_risk` field in SP_ANALYZE_INTERACTION is derived by combining the LLM churn signal with the numeric sentiment score:

```
IF churn_signal = 'high'                          → HIGH
IF churn_signal = 'moderate' OR sentiment < -0.3  → ELEVATED
IF churn_signal = 'low' OR sentiment < 0.0        → LOW
ELSE                                              → MINIMAL
```

This hybrid approach uses the LLM's contextual understanding (churn_signal) cross-checked against the quantitative sentiment score for more reliable risk classification.
