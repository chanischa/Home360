# Home360 — Demo Script

3-minute hackathon walkthrough using May Chen (C001) as the hero scenario.

---

## Setup

- Open the Home360 copilot (Streamlit app)
- Ensure HOME360_DB.CORE is populated (all 6 SQL scripts executed)

---

## Walkthrough

### 1. Open the Copilot (0:00 – 0:15)

> "This is Home360 — a Next Best Action copilot for home-insurance renewal conversations."

Select **May Chen** from the customer dropdown.

> "May just called. She wants to renew her policy but is confused about a price increase. Let's see what the copilot shows the agent."

---

### 2. Customer Context (0:15 – 0:40)

Point to Section 1:

> "First, the agent sees May's full context at a glance:
> - She's been a customer for **6.5 years**
> - **Excellent** payment history
> - High lifetime value — **$18,500**
> - Only **1 claim** in her entire history — a small theft in 2022
> - She's a customer worth keeping."

---

### 3. Renewal Comparison (0:40 – 1:15)

Point to Section 2:

> "Here's where it gets interesting. The copilot compares her current policy against the renewal proposal side-by-side:
>
> - Annual premium: **$8,500 → $10,030** — that's an **18% increase**, flagged as MAJOR
> - Flood coverage: **$50,000 → $35,000** — a **30% reduction**
> - Flood deductible: **$2,500 → $5,000** — it **doubled**
> - And there's a **new exclusion**: sewer backup
>
> Building and contents coverage are unchanged. So the changes are all flood-related. Why?"

---

### 4. Property Risk (1:15 – 1:40)

Point to Section 3:

> "This is the answer. May's property in Cedar Falls, Iowa was reassessed:
>
> - Flood risk went from **MEDIUM to HIGH**
> - Overall risk score jumped **86%** — from 0.42 to 0.78
>
> The root cause: **FEMA remapped her neighborhood to Zone AE** following a 2025 watershed study. The Cedar River flood-stage projections increased. Flood frequency in her zip code went from a 1-in-100 year event to 1-in-50.
>
> This is not about May. She didn't do anything wrong. It's an external reclassification."

---

### 5. Current Interaction (1:40 – 2:05)

Point to Section 4:

> "Now look at what May is actually saying on this call:
>
> - Intent: **renewal inquiry**
> - Sentiment: **concerned**
> - She said: *'I've been insured with you for years'* and *'I might have to look at other options'*
> - Churn signal: **moderate** — retention risk is **elevated**
>
> Without the copilot, the agent might not connect the dots between her sentiment, the FEMA remap, and the policy changes. With Home360, it's all in one place."

---

### 6. Next Best Action (2:05 – 2:40)

Point to Section 5:

> "And here's the recommendation — the core of Home360:
>
> **Explain the risk change transparently and offer an alternative coverage option.**
>
> Priority: HIGH
>
> The evidence is grounded in facts:
> - 6.5 years tenure, excellent payment
> - Only 1 minor claim ever
> - Risk change was external (FEMA), not her fault
> - She explicitly mentioned looking at other options
>
> The agent gets ready-made talking points:
> 1. Acknowledge her loyalty
> 2. Explain the FEMA flood-zone change
> 3. Walk through each policy change
> 4. Present an alternative option with adjusted deductible
> 5. Mention risk-reduction steps she can take
>
> And the copilot shows why alternatives were NOT selected — for example, escalating to retention was scored lower because the agent can handle this directly."

---

### 7. Take Action (2:40 – 3:00)

Click **[ TAKE ACTION ]**:

> "The agent clicks Take Action. The system logs:
> - What was recommended
> - What the agent did
> - When
> - Outcome status
>
> This closes the feedback loop. Over time, these logs tell us which recommendations actually lead to successful renewals."

---

### Closing

> "That's Home360.
>
> A generic Customer 360 tells you *who* the customer is.
> Home360 tells you *what changed, why it matters, and what to do next.*
>
> One copilot. One screen. One recommendation — with evidence."

---

## Backup Scenarios

If time permits or questions arise, these customers demonstrate different NBA paths:

| Customer | Quick Demo Point |
|---|---|
| Linda Okafor (C003) | High churn risk — NBA recommends escalation to retention specialist |
| Robert Diaz (C002) | Open flood claim — NBA focuses on claim status update, not renewal |
| James Park (C004) | Low risk, billing question — NBA gives informational response only |
| Carlos Mendez (C007) | 3 claims in 18 months — NBA flags non-renewal risk, underwriting escalation |
| Priya Singh (C005) | Post-fire rebuild — NBA recommends coverage increase to match rebuild cost |
