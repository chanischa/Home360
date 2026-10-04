import streamlit as st
import json
import os

# ─────────────────────────────────────────────────────────
# Home360 — Next Best Action Copilot for Home Insurance
# Community Cloud version (public URL)
# ─────────────────────────────────────────────────────────

st.set_page_config(page_title="Home360 Copilot", page_icon="🏠", layout="wide")

# ── Connection ───────────────────────────────────────────
conn = st.connection("snowflake")


def run_query(sql):
    return conn.query(sql)


def call_procedure(sql):
    df = conn.query(sql)
    raw = df.iloc[0, 0]
    return json.loads(raw) if isinstance(raw, str) else raw


# ── Styling ──────────────────────────────────────────────
st.markdown("""
<style>
    [data-testid="stMetric"] {
        background-color: #f0f2f6;
        border-radius: 8px;
        padding: 12px 16px;
    }
    .nba-card {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        color: white;
        border-radius: 12px;
        padding: 24px;
        margin: 8px 0;
    }
    .nba-card h3 { color: #29B5E8; margin-top: 0; }
    .nba-card .priority-high { color: #ff6b6b; font-weight: bold; }
    .nba-card .priority-medium { color: #ffd93d; font-weight: bold; }
    .nba-card .priority-low { color: #6bcb77; font-weight: bold; }
    .severity-major { color: #ff4444; font-weight: bold; }
    .severity-moderate { color: #ff8c00; font-weight: bold; }
    .severity-minor { color: #ffd700; }
    .severity-unchanged { color: #888888; }
    .risk-up { color: #ff4444; font-weight: bold; }
    .risk-down { color: #6bcb77; font-weight: bold; }
    .risk-unchanged { color: #888888; }
    div[data-testid="stExpander"] details summary p { font-size: 1rem; }
</style>
""", unsafe_allow_html=True)

# ── Header ───────────────────────────────────────────────
st.title("Home360 Copilot")
st.caption("Decision Intelligence for Insurance Frontlines")

# ── Customer Selector ────────────────────────────────────
customers = run_query("""
    SELECT customer_id, name, churn_risk_label, has_renewal_proposal, tenure_years
    FROM HOME360_DB.CORE.V_CUSTOMER_360
    ORDER BY customer_id
""")

col_sel, col_info = st.columns([2, 3])
with col_sel:
    options = [f"{r['CUSTOMER_ID']} — {r['NAME']}" for _, r in customers.iterrows()]
    selected = st.selectbox("Select Customer", options, index=0)
    cust_id = selected.split(" — ")[0]

# ── Load all data for selected customer ──────────────────
c360 = run_query(f"SELECT * FROM HOME360_DB.CORE.V_CUSTOMER_360 WHERE customer_id = '{cust_id}'")
if c360.empty:
    st.error("Customer not found.")
    st.stop()

c = c360.iloc[0]

with col_info:
    st.markdown(f"**{c['NAME']}** | {c['LOCATION']} | {c['PROPERTY_TYPE'].replace('_', ' ').title()}")
    st.markdown(f"Policy: `{c['POLICY_ID']}` | Status: **{c['POLICY_STATUS']}** | Renewal proposal: **{'Yes' if c['HAS_RENEWAL_PROPOSAL'] else 'No'}**")

st.divider()

# ═════════════════════════════════════════════════════════
# SECTION 1 — CUSTOMER CONTEXT
# ═════════════════════════════════════════════════════════
st.subheader("Customer Context")

m1, m2, m3, m4, m5, m6 = st.columns(6)
m1.metric("Tenure", f"{c['TENURE_YEARS']} yr")
m2.metric("Value", f"${c['CUSTOMER_VALUE']:,.0f}")
m3.metric("Payment", c['PAYMENT_HISTORY'])
m4.metric("Claims", f"{c['TOTAL_CLAIMS']} ({c['OPEN_CLAIMS']} open)")
m5.metric("Risk Score", f"{c['CURRENT_RISK_SCORE']:.2f}")

churn_label = c['CHURN_RISK_LABEL']
churn_color = {"HIGH": "🔴", "MODERATE": "🟡", "LOW": "🟢", "MINIMAL": "⚪"}.get(churn_label, "⚪")
m6.metric("Churn Risk", f"{churn_color} {churn_label}")

prop_cols = st.columns(4)
prop_cols[0].markdown(f"**Property:** {c['PROPERTY_TYPE'].replace('_', ' ').title()}")
prop_cols[1].markdown(f"**Location:** {c['LOCATION']}")
prop_cols[2].markdown(f"**Building Age:** {c['BUILDING_AGE']} years")
prop_cols[3].markdown(f"**Construction:** {c['CONSTRUCTION_TYPE'].replace('_', ' ').title()}")

st.divider()

# ═════════════════════════════════════════════════════════
# SECTION 2 — RENEWAL COMPARISON
# ═════════════════════════════════════════════════════════
st.subheader("Renewal Comparison")

if c['HAS_RENEWAL_PROPOSAL']:
    policy_cmp = call_procedure(f"CALL HOME360_DB.CORE.SP_COMPARE_POLICY('{cust_id}')")

    if policy_cmp.get("status") == "ok":
        sev = policy_cmp.get("overall_severity", "UNCHANGED")
        sev_class = f"severity-{sev.lower()}"
        st.markdown(f"Overall change severity: <span class='{sev_class}'>{sev}</span>", unsafe_allow_html=True)

        def fmt_change(field_data):
            ch = field_data.get("change", 0)
            pct = field_data.get("change_pct", 0)
            sev = field_data.get("severity", "UNCHANGED")
            if ch == 0:
                return "—", "—", sev
            sign = "+" if ch > 0 else ""
            return f"{sign}${ch:,.0f}", f"{sign}{pct}%", sev

        fields = [
            ("Annual Premium", "premium"),
            ("General Deductible", "deductible"),
            ("Building Coverage", "building_coverage"),
            ("Contents Coverage", "contents_coverage"),
            ("Flood Coverage", "flood_coverage"),
            ("Flood Deductible", "flood_deductible"),
        ]

        header = st.columns([2, 1.5, 1.5, 1.2, 1, 1])
        header[0].markdown("**Field**")
        header[1].markdown("**Current**")
        header[2].markdown("**Renewal**")
        header[3].markdown("**Change**")
        header[4].markdown("**%**")
        header[5].markdown("**Severity**")

        for label, key in fields:
            fd = policy_cmp.get(key, {})
            ch_abs, ch_pct, sev = fmt_change(fd)
            sev_class = f"severity-{sev.lower()}"
            cols = st.columns([2, 1.5, 1.5, 1.2, 1, 1])
            cols[0].markdown(f"**{label}**")
            cols[1].markdown(f"${fd.get('current', 0):,.0f}")
            cols[2].markdown(f"${fd.get('renewal', 0):,.0f}")
            cols[3].markdown(ch_abs)
            cols[4].markdown(ch_pct)
            cols[5].markdown(f"<span class='{sev_class}'>{sev}</span>", unsafe_allow_html=True)

        excl = policy_cmp.get("exclusions", {})
        if excl.get("changed"):
            st.markdown(f"**Exclusions changed:**  \n"
                        f"Current: _{excl.get('current', '')}_  \n"
                        f"Renewal: _{excl.get('renewal', '')}_")

        findings = policy_cmp.get("key_findings", [])
        if findings:
            with st.expander("Key Findings", expanded=True):
                for f in findings:
                    st.markdown(f"- {f}")
    else:
        st.info(policy_cmp.get("message", "No comparison data available."))
else:
    st.info("No renewal proposal on file for this customer.")

st.divider()

# ═════════════════════════════════════════════════════════
# SECTION 3 — PROPERTY RISK
# ═════════════════════════════════════════════════════════
st.subheader("Property Risk")

risk = call_procedure(f"CALL HOME360_DB.CORE.SP_ANALYZE_RISK('{cust_id}')")

if risk.get("status") == "ok":
    changes = risk.get("changes", {})

    r1, r2, r3, r4 = st.columns(4)

    def risk_arrow(direction):
        return {"UP": "▲", "DOWN": "▼", "UNCHANGED": "—"}.get(direction, "—")

    def risk_color(direction):
        return {"UP": "risk-up", "DOWN": "risk-down", "UNCHANGED": "risk-unchanged"}.get(direction, "risk-unchanged")

    for col, dim_key, dim_label in [
        (r1, "flood", "Flood"),
        (r2, "fire", "Fire"),
        (r3, "earthquake", "Earthquake"),
    ]:
        dim = changes.get(dim_key, {})
        prev = dim.get("previous", "—")
        curr = dim.get("current", "—")
        direction = dim.get("direction", "UNCHANGED")
        arrow = risk_arrow(direction)
        cls = risk_color(direction)
        col.markdown(
            f"**{dim_label} Risk**  \n"
            f"{prev} → <span class='{cls}'>{curr} {arrow}</span>",
            unsafe_allow_html=True,
        )

    overall = changes.get("overall_score", {})
    curr_score = overall.get("current", 0)
    change_pct = overall.get("change_pct", 0)
    r4.metric("Overall Score", f"{curr_score:.2f}", f"{change_pct:+.1f}%", delta_color="inverse")

    root = risk.get("root_cause", "")
    if root:
        with st.expander("Root Cause", expanded=True):
            st.markdown(root)

    comm_points = risk.get("communication_points", [])
    if comm_points:
        with st.expander("Agent Communication Points"):
            for pt in comm_points:
                st.markdown(f"- {pt}")

elif risk.get("status") == "no_risk_change":
    cr = risk.get("current_risk", {})
    r1, r2, r3, r4 = st.columns(4)
    r1.metric("Flood", cr.get("flood_risk", "—"))
    r2.metric("Fire", cr.get("fire_risk", "—"))
    r3.metric("Earthquake", cr.get("earthquake_risk", "—"))
    r4.metric("Overall Score", f"{cr.get('overall_risk_score', 0):.2f}")
    st.caption("Only one risk assessment on file — no change to compare.")
else:
    st.info("No risk data available.")

st.divider()

# ═════════════════════════════════════════════════════════
# SECTION 4 — CURRENT INTERACTION
# ═════════════════════════════════════════════════════════
st.subheader("Current Interaction")

interaction_id = c.get("LAST_INTERACTION_ID")

if interaction_id:
    interaction = call_procedure(f"CALL HOME360_DB.CORE.SP_ANALYZE_INTERACTION('{interaction_id}')")

    if interaction.get("status") == "ok":
        i1, i2, i3, i4 = st.columns(4)
        i1.markdown(f"**Channel:** {interaction.get('interaction_type', '—')}")
        i2.markdown(f"**Date:** {str(interaction.get('interaction_timestamp', ''))[:16]}")

        sentiment = interaction.get("sentiment", {})
        sent_score = sentiment.get("score", 0)
        sent_label = sentiment.get("label", "—")
        i3.markdown(f"**Sentiment:** {sent_label} ({sent_score:+.2f})")

        intent = interaction.get("intent", {})
        i4.markdown(f"**Intent:** {intent.get('label', '—').replace('_', ' ').title()}")

        signals = interaction.get("signals", {})
        s1, s2, s3, s4 = st.columns(4)

        urgency = signals.get("urgency", "—")
        s1.markdown(f"**Urgency:** {urgency.upper()}")

        churn_sig = signals.get("churn_signal", "—")
        s2.markdown(f"**Churn Signal:** {churn_sig.upper()}")

        retention = interaction.get("retention_risk", "—")
        ret_icon = {"HIGH": "🔴", "ELEVATED": "🟡", "LOW": "🟢", "MINIMAL": "⚪"}.get(retention, "⚪")
        s3.markdown(f"**Retention Risk:** {ret_icon} {retention}")

        tone = signals.get("recommended_tone", "—")
        s4.markdown(f"**Rec. Tone:** {tone.replace('-', ' ').title()}")

        phrases = interaction.get("key_phrases", [])
        if phrases:
            st.markdown("**Key Phrases:** " + " | ".join([f'_"{p}"_' for p in phrases]))

        transcript = c.get("LAST_INTERACTION_TRANSCRIPT", "")
        if transcript:
            with st.expander("Full Transcript"):
                st.text(transcript)

        note = interaction.get("agent_note")
        if note:
            st.caption(f"Agent Note: {note}")
    else:
        st.info("Could not analyze interaction.")
else:
    st.info("No interaction on file for this customer.")

st.divider()

# ═════════════════════════════════════════════════════════
# SECTION 5 — NEXT BEST ACTION
# ═════════════════════════════════════════════════════════
st.subheader("Next Best Action")

if "nba_result" not in st.session_state or st.session_state.get("nba_customer") != cust_id:
    with st.spinner("Generating recommendation..."):
        interaction_arg = f"'{interaction_id}'" if interaction_id else "NULL"
        nba_full = call_procedure(
            f"CALL HOME360_DB.CORE.SP_NEXT_BEST_ACTION('{cust_id}', {interaction_arg})"
        )
        st.session_state["nba_result"] = nba_full
        st.session_state["nba_customer"] = cust_id

nba_full = st.session_state["nba_result"]
nba = nba_full.get("nba", {})

rec = nba.get("recommended_action", {})
code = rec.get("code", "?")
title = rec.get("title", "No recommendation")
desc = rec.get("description", "")
priority = rec.get("priority", "MEDIUM")

priority_class = f"priority-{priority.lower()}"

st.markdown(f"""
<div class="nba-card">
    <h3>▶ [{code}] {title}</h3>
    <p>{desc}</p>
    <p>Priority: <span class="{priority_class}">{priority}</span></p>
</div>
""", unsafe_allow_html=True)

why = nba.get("why_this_action", "")
if why:
    st.markdown(f"**Why this action:** {why}")

evidence = nba.get("evidence", [])
if evidence:
    with st.expander("Evidence (Facts)", expanded=True):
        for e in evidence:
            st.markdown(f"- {e}")

talking = nba.get("agent_talking_points", [])
if talking:
    with st.expander("Agent Talking Points", expanded=True):
        for i, tp in enumerate(talking, 1):
            st.markdown(f"{i}. {tp}")

alts = nba.get("alternative_actions", [])
if alts:
    with st.expander("Alternative Actions"):
        for alt in alts:
            st.markdown(
                f"**[{alt.get('code', '?')}] {alt.get('title', '')}** — "
                f"_{alt.get('why_not_selected', '')}_"
            )

flags = nba.get("risk_flags", [])
if flags:
    with st.expander("Risk Flags"):
        for f in flags:
            st.markdown(f"⚠️ {f}")

st.divider()

# ═════════════════════════════════════════════════════════
# ACTION EXECUTION
# ═════════════════════════════════════════════════════════

def log_action(action_taken_text, status_val):
    nba_summary = {
        "recommended_action": nba.get("recommended_action", {}),
        "why_this_action": nba.get("why_this_action", ""),
        "evidence": nba.get("evidence", []),
    }
    nba_json = json.dumps(nba_summary, ensure_ascii=False)[:15000].replace("'", "''")
    action_text = action_taken_text[:3500].replace("'", "''")
    int_arg = f"'{interaction_id}'" if interaction_id else "NULL"
    result = call_procedure(
        f"CALL HOME360_DB.CORE.SP_LOG_ACTION("
        f"'{cust_id}', {int_arg}, "
        f"'{nba_json}', '{action_text}', '{status_val}')"
    )
    return result

modify_text = st.text_input(
    "Modify action (optional — override or add notes before executing):",
    placeholder="e.g. Offered 10% loyalty discount on top of standard renewal",
    key="modify_input"
)

btn1, btn2, btn3, btn4 = st.columns(4)

with btn1:
    if st.button("Take Action", type="primary", use_container_width=True):
        action_desc = modify_text if modify_text else f"Executed: {title}"
        result = log_action(action_desc, "EXECUTED")
        if result.get("status") == "ok":
            st.success(f"Action logged ({result['action_id']}): {action_desc}")
        else:
            st.error(result.get("message", "Failed to log action"))

with btn2:
    if st.button("Escalate", use_container_width=True):
        action_desc = modify_text if modify_text else f"Escalated: {title}"
        result = log_action(action_desc, "ESCALATED")
        if result.get("status") == "ok":
            st.success(f"Escalated ({result['action_id']}): {action_desc}")
        else:
            st.error(result.get("message", "Failed to log"))

with btn3:
    if st.button("Decline", use_container_width=True):
        action_desc = modify_text if modify_text else f"Declined: {title}"
        result = log_action(action_desc, "DECLINED")
        if result.get("status") == "ok":
            st.info(f"Declined ({result['action_id']}). Logged for review.")
        else:
            st.error(result.get("message", "Failed to log"))

with btn4:
    if st.button("Pending", use_container_width=True):
        action_desc = modify_text if modify_text else f"Pending review: {title}"
        result = log_action(action_desc, "PENDING")
        if result.get("status") == "ok":
            st.info(f"Saved as pending ({result['action_id']}).")
        else:
            st.error(result.get("message", "Failed to log"))

st.divider()

# ═════════════════════════════════════════════════════════
# ACTION HISTORY
# ═════════════════════════════════════════════════════════

with st.expander("Action History"):
    history = run_query(f"""
        SELECT action_id, customer_name, action_taken, status, action_timestamp
        FROM HOME360_DB.CORE.V_ACTION_HISTORY
        WHERE customer_id = '{cust_id}'
        ORDER BY action_timestamp DESC
        LIMIT 10
    """)
    if history.empty:
        st.caption("No actions recorded yet for this customer.")
    else:
        st.dataframe(history, use_container_width=True, hide_index=True)

# Footer
st.divider()
st.caption("Home360 — Decision Intelligence for Insurance Frontlines | Powered by Snowflake Cortex AI")
