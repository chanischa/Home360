---
name: home360-analyze-interaction
description: "Analyze a customer interaction transcript using Cortex AI. Extracts intent, sentiment, urgency, churn signals, pricing concern, coverage concern, and key phrases. Use when: analyzing a call, understanding customer sentiment, detecting churn risk, interaction intelligence. Triggers: analyze interaction, sentiment, intent, churn signal, customer concern, what is the customer feeling, interaction intelligence, transcript analysis."
---

# Home360 — Analyze Customer Interaction

## Purpose

Take a raw interaction transcript (call, email, chat) and extract
structured intelligence using Snowflake Cortex AI functions. This
intelligence feeds the NBA engine's interaction signals.

## Database

Interactions stored in `HOME360_DB.CORE.INTERACTION`.

## Cortex Functions Used

| Function              | Purpose                           |
|-----------------------|-----------------------------------|
| CORTEX.SENTIMENT      | Numeric sentiment (-1 to +1)      |
| CORTEX.CLASSIFY_TEXT   | Intent classification             |
| CORTEX.SUMMARIZE      | Concise transcript summary        |
| CORTEX.COMPLETE (70b) | Deep signal extraction (JSON)     |

## Workflow

### Step 1: Retrieve the interaction

```sql
SELECT interaction_id, customer_id, interaction_type,
       interaction_timestamp, raw_transcript, agent_note
FROM HOME360_DB.CORE.INTERACTION
WHERE interaction_id = :interaction_id;
```

Or retrieve the most recent interaction for a customer:

```sql
SELECT * FROM HOME360_DB.CORE.INTERACTION
WHERE customer_id = :customer_id
ORDER BY interaction_timestamp DESC
LIMIT 1;
```

### Step 2: Run Cortex sentiment + classification

```sql
SELECT
    SNOWFLAKE.CORTEX.SENTIMENT(raw_transcript) AS sentiment_score,
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        raw_transcript,
        ['renewal_inquiry', 'claim_status', 'billing_question',
         'cancellation_request', 'coverage_concern', 'complaint']
    ) AS intent_classification,
    SNOWFLAKE.CORTEX.SUMMARIZE(raw_transcript) AS summary
FROM HOME360_DB.CORE.INTERACTION
WHERE interaction_id = :interaction_id;
```

### Step 3: Deep signal extraction via CORTEX.COMPLETE

Use llama3.1-70b to extract structured signals:

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-70b',
    'Analyze this insurance customer interaction transcript and return a JSON object with these fields:
    - intent: primary reason for contact (one of: renewal, claim, billing, cancellation, coverage_review, complaint, general_inquiry)
    - sentiment: one of positive, neutral, concerned, frustrated, angry
    - urgency: one of low, medium, high, critical
    - churn_signal: one of none, low, moderate, high (likelihood customer may leave)
    - pricing_concern: true/false
    - coverage_concern: true/false
    - complaint_signal: true/false
    - key_phrases: array of up to 5 important direct quotes from the customer
    - recommended_tone: how the agent should respond (one of: reassuring, empathetic, urgent, informational, retention-focused)
    - summary: 2-3 sentence summary of the interaction

    Return ONLY valid JSON, no other text.

    Transcript:
    ' || raw_transcript
) AS deep_analysis
FROM HOME360_DB.CORE.INTERACTION
WHERE interaction_id = :interaction_id;
```

### Step 4: Interpret sentiment score

Map the numeric sentiment to a label:
- **> 0.3**: Positive
- **0.0 to 0.3**: Neutral
- **-0.3 to 0.0**: Mildly concerned
- **-0.6 to -0.3**: Concerned / frustrated
- **< -0.6**: Angry / very negative

### Step 5: Present interaction intelligence

```
INTERACTION INTELLIGENCE — [Customer Name]

Date:       [timestamp]
Channel:    [CALL/EMAIL/CHAT]

SENTIMENT
  Score:    [numeric]
  Label:    [Concerned]

INTENT
  Primary:  [renewal_inquiry]

SIGNALS
  Urgency:         [Medium]
  Churn Risk:      [Moderate]
  Pricing Concern: [Yes]
  Coverage Concern: [Yes]
  Complaint:       [No]

KEY PHRASES
  - "I've been insured with you for years"
  - "why has the price increased"
  - "I might have to look at other options"

RECOMMENDED TONE
  [Empathetic + retention-focused]

SUMMARY
  [2-3 sentence summary]
```

## Output

A structured interaction intelligence object combining Cortex function
outputs with interpreted labels, ready for the NBA engine to consume
as interaction signals.
