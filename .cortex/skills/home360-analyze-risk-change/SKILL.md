---
name: home360-analyze-risk-change
description: "Analyze property risk changes for a Home360 customer. Compares historical vs current risk assessments and explains what changed and why. Use when: risk changed, why did risk increase, flood risk, fire risk, earthquake risk, property risk assessment, what happened to risk. Triggers: risk change, risk analysis, flood risk, fire risk, earthquake risk, why did risk change, property risk, risk assessment, FEMA, risk reason."
---

# Home360 — Analyze Risk Change

## Purpose

Compare historical and current property risk assessments for a customer's
property. Identify which risk dimensions changed, by how much, and why.
Connect risk changes to their impact on policy terms and premium.

## Database

Risk data in `HOME360_DB.CORE.HOME_RISK_HISTORY`, linked via
`HOME360_DB.CORE.PROPERTY`.

## Workflow

### Step 1: Retrieve risk history

```sql
SELECT h.risk_assessment_id, h.assessment_date,
       h.flood_risk, h.fire_risk, h.earthquake_risk,
       h.overall_risk_score, h.risk_reason,
       p.location, p.property_type, p.building_age, p.construction_type
FROM HOME360_DB.CORE.HOME_RISK_HISTORY h
JOIN HOME360_DB.CORE.PROPERTY p ON h.property_id = p.property_id
WHERE p.customer_id = :customer_id
ORDER BY h.assessment_date;
```

### Step 2: Identify changes

If multiple assessments exist, compare the most recent against the
previous one:

For each risk dimension (flood, fire, earthquake):
- Did the rating change? (e.g., MEDIUM → HIGH)
- Map to numeric for comparison: LOW=1, MEDIUM=2, HIGH=3

For overall_risk_score:
- Absolute change
- Percentage change

### Step 3: Explain the root cause

The `risk_reason` field contains the explanation. Extract:
- What external event or data source triggered the change
- When the reassessment happened
- Geographic or regulatory context (FEMA remapping, USGS update, etc.)

### Step 4: Connect to policy impact

If policy comparison data is available, link the risk change to
specific policy term changes:

```
RISK CHANGE → POLICY IMPACT

  Flood risk: MEDIUM → HIGH
    → Annual premium: +$1,530 (+18%)
    → Flood coverage limit: -$15,000 (-30%)
    → Flood deductible: +$2,500 (+100%)
    → New exclusion: sewer backup
```

### Step 5: Present risk analysis

```
RISK CHANGE ANALYSIS — [Customer Name]
Property: [location]

                    PREVIOUS        CURRENT         CHANGE
                    ([date])        ([date])
Flood Risk          MEDIUM          HIGH            UPGRADED ▲
Fire Risk           LOW             LOW             —
Earthquake Risk     LOW             LOW             —
Overall Score       0.42            0.78            +0.36 (+86%)

ROOT CAUSE
  [risk_reason from latest assessment]

POLICY IMPACT
  [List of policy terms affected by this risk change]

CUSTOMER COMMUNICATION POINTS
  - The risk change is based on [external factor], not the customer's behavior
  - [Specific data point, e.g., "FEMA remapped the area to Zone AE"]
  - The customer can take [risk-reduction steps] to potentially improve terms
```

## Output

A structured risk change analysis with before/after comparison, root
cause explanation, policy impact linkage, and ready-to-use communication
points for the agent.
