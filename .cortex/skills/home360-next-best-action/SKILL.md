---
name: home360-next-best-action
description: "Generate an explainable Next Best Action recommendation for a Home360 customer. Combines all context signals (customer, policy, claims, risk, interaction) to produce ranked candidate actions with evidence. Use when: what should the agent do, next best action, NBA, recommend action, what to do next, renewal recommendation. Triggers: next best action, NBA, recommend, what should I do, action recommendation, what to do, renewal action, agent guidance."
---

# Home360 — Next Best Action Engine

## Purpose

The core decision engine. Consumes the full customer context (360 view,
policy comparison, risk analysis, interaction intelligence) and produces
a ranked, explainable recommendation for the frontline agent.

## Principle

Do NOT use single-rule logic. Evaluate MULTIPLE signals together.

The output must clearly separate:
- **FACTS** (data from tables)
- **AI INTERPRETATION** (derived signals)
- **RECOMMENDED ACTION** (what to do and why)

## Signal Categories

### Customer Signals
- tenure_years, customer_value, payment_history, churn_risk_score

### Policy Signals
- premium change (%), deductible change, coverage changes, new exclusions
- renewal status (PROPOSED / not yet)

### Claims Signals
- claim count, open claims, claim severity, recent claim activity

### Property Signals
- property_type, building_age, construction_type, location

### Risk Signals
- historical vs current risk, risk change direction, risk reason

### Interaction Signals
- intent, sentiment, urgency, churn_signal, pricing_concern, coverage_concern

## Candidate Actions

The engine must generate and evaluate multiple candidates:

| Code | Action | When Appropriate |
|------|--------|-----------------|
| A | Explain renewal changes only | Low concern, informational query |
| B | Explain + recommend renewal | Moderate concern, loyal customer |
| C | Explain + offer alternative deductible/coverage option | Price-sensitive, retention risk |
| D | Recommend risk-reduction measures | Risk change is main driver |
| E | Escalate to retention specialist | High churn risk, high value |
| F | Escalate to underwriting specialist | Complex risk, coverage gap |
| G | Request additional property information | Incomplete data |

## Workflow

### Step 1: Gather all context

Use the home360-customer-360 skill output, or query directly:

1. Customer demographics + value
2. Both policy versions (CURRENT + RENEWAL)
3. Claims history
4. Property + risk history
5. Latest interaction intelligence

### Step 2: Build the NBA prompt

Construct a structured prompt for CORTEX.COMPLETE (llama3.1-70b):

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-70b',
    '## Task
You are a decision engine for an insurance agent copilot. Given the full
customer context below, generate a Next Best Action recommendation.

## Customer Context
[Insert all 360 data here as structured text]

## Policy Comparison
[Insert comparison output here]

## Risk Change
[Insert risk analysis here]

## Interaction Intelligence
[Insert interaction analysis here]

## Instructions
1. Generate 3-5 candidate actions from this list:
   A. Explain renewal changes only
   B. Explain changes and recommend renewal
   C. Explain changes and offer alternative coverage/deductible option
   D. Recommend risk-reduction measures before final renewal
   E. Escalate to retention specialist
   F. Escalate to underwriting specialist
   G. Request additional property information

2. Score each candidate 1-10 based on:
   - Customer retention likelihood
   - Appropriateness given sentiment/urgency
   - Business risk management
   - Customer satisfaction potential

3. Select the TOP recommendation.

4. Return ONLY valid JSON with this structure:
{
  "recommended_action": {
    "code": "C",
    "title": "short title",
    "description": "detailed description of what to do",
    "priority": "HIGH/MEDIUM/LOW",
    "score": 9
  },
  "why_this_action": "2-3 sentence explanation",
  "evidence": [
    "fact 1 that supports this recommendation",
    "fact 2 ...",
    "..."
  ],
  "alternative_actions": [
    {
      "code": "B",
      "title": "...",
      "score": 7,
      "why_not_selected": "reason"
    }
  ],
  "agent_talking_points": [
    "point 1 the agent should communicate",
    "point 2 ...",
    "..."
  ],
  "risk_flags": [
    "any risks or concerns to be aware of"
  ]
}
'
) AS nba_result;
```

### Step 3: Parse and validate

Parse the JSON response. Validate:
- recommended_action exists and has required fields
- At least 2 alternative_actions
- Evidence array is non-empty
- Scores are between 1-10

If parsing fails, retry once with llama3.1-8b as fallback.

### Step 4: Present the recommendation

```
══════════════════════════════════════════════
  NEXT BEST ACTION — [Customer Name]
══════════════════════════════════════════════

  ▶ [Action Title]
    Priority: [HIGH]

  WHY THIS ACTION
    [2-3 sentence explanation]

  EVIDENCE (FACTS)
    • [fact 1]
    • [fact 2]
    • [fact 3]

  AGENT TALKING POINTS
    1. [point 1]
    2. [point 2]
    3. [point 3]

  ALTERNATIVE ACTIONS
    [B] [title] (score: 7) — not selected because: [reason]
    [E] [title] (score: 6) — not selected because: [reason]

  RISK FLAGS
    ⚠ [any concerns]

  [ TAKE ACTION ]    [ MODIFY ]    [ ESCALATE ]
══════════════════════════════════════════════
```

### Step 5: Log the action

When the agent confirms, insert into ACTION_LOG:

```sql
INSERT INTO HOME360_DB.CORE.ACTION_LOG
    (action_id, customer_id, interaction_id,
     recommended_action, action_taken, action_timestamp, status)
VALUES
    (:new_id, :customer_id, :interaction_id,
     :recommended_json, :action_taken, CURRENT_TIMESTAMP(), 'EXECUTED');
```

## Output

A complete, explainable NBA recommendation with:
- One primary recommended action with priority and score
- Evidence grounded in data facts
- Agent-ready talking points
- Ranked alternatives with reasons for non-selection
- Risk flags
- Audit trail via ACTION_LOG
