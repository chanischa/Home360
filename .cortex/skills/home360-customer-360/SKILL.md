---
name: home360-customer-360
description: "Build or query the Home360 Customer 360 view. Combines customer demographics, policy versions, claims, property, risk history, and interactions into a unified context for a given customer. Use when: building 360 view, querying customer context, preparing NBA input. Triggers: customer 360, customer context, who is this customer, customer profile, build 360, unified view."
---

# Home360 — Customer 360

## Purpose

Assemble a complete context picture for a single customer by joining all
six data domains: customer demographics, policy versions, claims history,
property characteristics, risk assessments, and interaction history.

This is the foundation that every downstream module (policy comparison,
risk analysis, interaction intelligence, NBA engine) consumes.

## Database

All tables live in `HOME360_DB.CORE`.

## Workflow

### Step 1: Identify the customer

Determine the target customer. Accept any of:
- `customer_id` (e.g. C001)
- `name` (e.g. May Chen)
- Description (e.g. "the customer who called about flood risk")

If ambiguous, query CUSTOMER table and ask user to confirm.

### Step 2: Retrieve structured context

Run this query (substitute the customer_id):

```sql
-- Customer + Property
SELECT c.*, p.property_id, p.property_type, p.location,
       p.building_age, p.construction_type
FROM HOME360_DB.CORE.CUSTOMER c
LEFT JOIN HOME360_DB.CORE.PROPERTY p ON c.customer_id = p.customer_id
WHERE c.customer_id = :customer_id;

-- Policy versions (CURRENT + RENEWAL if exists)
SELECT * FROM HOME360_DB.CORE.POLICY_VERSION
WHERE customer_id = :customer_id
ORDER BY policy_version;

-- Claims history
SELECT * FROM HOME360_DB.CORE.CLAIM
WHERE customer_id = :customer_id
ORDER BY claim_date DESC;

-- Risk assessment history
SELECT h.* FROM HOME360_DB.CORE.HOME_RISK_HISTORY h
JOIN HOME360_DB.CORE.PROPERTY p ON h.property_id = p.property_id
WHERE p.customer_id = :customer_id
ORDER BY h.assessment_date;

-- Interactions
SELECT * FROM HOME360_DB.CORE.INTERACTION
WHERE customer_id = :customer_id
ORDER BY interaction_timestamp DESC;

-- Action log
SELECT * FROM HOME360_DB.CORE.ACTION_LOG
WHERE customer_id = :customer_id
ORDER BY action_timestamp DESC;
```

### Step 3: Summarize the 360 context

Present a structured summary:

```
CUSTOMER CONTEXT
  Name: ...
  Tenure: ... years
  Value: $...
  Payment History: ...
  Churn Risk: ... (LOW/MEDIUM/HIGH based on score)

PROPERTY
  Type: ...
  Location: ...
  Age: ... years
  Construction: ...

POLICY STATUS
  Current Policy: [key terms]
  Renewal Proposed: YES/NO [key changes if yes]

CLAIMS HISTORY
  Total claims: ...
  Open claims: ...
  Summary: ...

RISK PROFILE
  Current: flood=... fire=... earthquake=... overall=...
  Previous: [if multiple assessments exist, show change]

RECENT INTERACTIONS
  Last contact: [date, type, brief summary]
```

## Output

A structured customer context object that downstream skills
(compare-policies, analyze-interaction, next-best-action) can consume
without re-querying the database.
