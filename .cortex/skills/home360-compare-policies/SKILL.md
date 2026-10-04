---
name: home360-compare-policies
description: "Compare previous vs renewal policy versions for a Home360 customer. Shows absolute and percentage changes for premium, deductible, coverage, and exclusions. Use when: comparing policies, what changed in renewal, why did premium increase, coverage differences, policy comparison. Triggers: compare policies, policy comparison, what changed, premium increase, renewal changes, coverage change, deductible change."
---

# Home360 — Compare Policy Versions

## Purpose

For a customer approaching renewal, compare the CURRENT policy against
the RENEWAL (proposed) policy. Identify and explain every meaningful
change in premium, deductible, coverage limits, and exclusions.

## Database

All tables live in `HOME360_DB.CORE`.

## Workflow

### Step 1: Retrieve both policy versions

```sql
SELECT * FROM HOME360_DB.CORE.POLICY_VERSION
WHERE customer_id = :customer_id
  AND policy_version IN ('CURRENT', 'RENEWAL')
ORDER BY policy_version;
```

If only CURRENT exists, report that no renewal has been proposed yet.

### Step 2: Compute changes

For each numeric field, compute:
- **Absolute change** = RENEWAL value - CURRENT value
- **Percentage change** = ((RENEWAL - CURRENT) / CURRENT) * 100

Fields to compare:
- `annual_premium`
- `deductible`
- `building_coverage`
- `contents_coverage`
- `flood_coverage`
- `flood_deductible`

For `exclusions` (text), identify:
- **Added exclusions**: in RENEWAL but not in CURRENT
- **Removed exclusions**: in CURRENT but not in RENEWAL

### Step 3: Classify change severity

For each changed field, classify as:
- **MAJOR**: premium change > 15%, or any coverage reduction > 20%, or deductible increase > 50%
- **MODERATE**: premium change 5–15%, or coverage change 10–20%, or deductible change 20–50%
- **MINOR**: changes below moderate thresholds

### Step 4: Present comparison

```
POLICY COMPARISON — [Customer Name]

                        CURRENT      RENEWAL      CHANGE       %       SEVERITY
Annual Premium          $8,500       $10,030      +$1,530      +18.0%  MAJOR
General Deductible      $1,500       $1,500       —            —       —
Building Coverage       $250,000     $250,000     —            —       —
Contents Coverage       $75,000      $75,000      —            —       —
Flood Coverage          $50,000      $35,000      -$15,000     -30.0%  MAJOR
Flood Deductible        $2,500       $5,000       +$2,500      +100.0% MAJOR

EXCLUSIONS
  Added:   sewer backup
  Removed: (none)

KEY FINDINGS
  1. Premium increased 18% ($1,530/year)
  2. Flood coverage reduced by 30%
  3. Flood deductible doubled
  4. New exclusion: sewer backup
```

### Step 5: Link to risk context

If risk data is available (from home360-analyze-risk-change or customer-360),
connect the policy changes to the underlying risk change:

"Premium increased because flood risk was reclassified from MEDIUM to HIGH
following the FEMA Zone AE remapping in January 2026."

## Output

A structured comparison with absolute changes, percentage changes,
severity classifications, and a plain-language explanation of the
most impactful changes linked to their root cause.
