"""Data Detective: AI-powered data quality investigator (Streamlit in Snowflake)."""
import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Data Detective", layout="wide")
session = get_active_session()
CORE = "DATA_DETECTIVE.CORE"
SEV_ORDER = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
MODELS = ["claude-sonnet-4-5", "claude-opus-4-5", "claude-haiku-4-5"]


def q(sql: str, params: list | None = None) -> pd.DataFrame:
    return session.sql(sql, params or []).to_pandas()


def as_obj(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return {}
    return json.loads(v) if isinstance(v, str) else v


@st.cache_data(ttl=600)
def datasets() -> pd.DataFrame:
    return q(f"SELECT dataset_id, display_name, description FROM {CORE}.DATASET_REGISTRY ORDER BY dataset_id")


def runs(dataset_id: str) -> pd.DataFrame:
    return q(f"""SELECT run_id, as_of_date, window_start, finished_at, n_findings FROM {CORE}.CHECK_RUNS
                 WHERE dataset_id = ? AND finished_at IS NOT NULL ORDER BY started_at DESC LIMIT 20""", [dataset_id])


def findings(run_id: str) -> pd.DataFrame:
    df = q(f"""SELECT r.result_id, r.check_type, r.severity, r.metric, r.obs_date, r.affected_count, r.observed, r.expected,
                      r.summary, r.details,
                      (SELECT MAX(i.investigation_id) FROM {CORE}.INVESTIGATIONS i WHERE i.result_id = r.result_id AND i.status = 'COMPLETED') investigation_id
               FROM {CORE}.CHECK_RESULTS r WHERE r.run_id = ?""", [run_id])
    df["_sev"] = df["SEVERITY"].map(SEV_ORDER)
    return df.sort_values(["_sev", "CHECK_TYPE"]).drop(columns="_sev")


def render_report(inv_id: str):
    inv = q(f"SELECT * FROM {CORE}.INVESTIGATIONS WHERE investigation_id = ?", [inv_id])
    if inv.empty:
        st.warning("Investigation not found.")
        return
    row = inv.iloc[0]
    rep = as_obj(row["REPORT"])
    steps = q(f"""SELECT step_no, hypothesis, reasoning, tool, args, sql_text, row_count, result_sample, error
                  FROM {CORE}.INVESTIGATION_STEPS WHERE investigation_id = ? ORDER BY step_no""", [inv_id])

    verdict = rep.get("verdict", "INCONCLUSIVE")
    icon = {"DATA_ERROR": "🔴", "REAL_EVENT": "🟢"}.get(verdict, "🟡")
    st.subheader(f"{icon} {rep.get('title', 'Investigation report')}")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Verdict", verdict.replace("_", " ").title())
    c2.metric("Severity", rep.get("severity", "-"))
    c3.metric("Analyses run", int(row["N_STEPS"] or 0))
    c4.metric("Model", row["MODEL"])
    st.write(rep.get("summary", ""))

    aff = rep.get("affected") or {}
    if aff:
        with st.container(border=True):
            st.markdown("**Affected scope**")
            st.write({k: v for k, v in aff.items() if v})

    left, right = st.columns(2)
    with left:
        st.markdown("#### ✅ Confirmed findings")
        st.caption("Each is directly supported by the cited analysis steps.")
        for f in rep.get("confirmed_findings") or []:
            st.success(f"{f.get('finding')}  \n*Evidence: step(s) {', '.join(map(str, f.get('evidence_steps', [])))}*")
        if rep.get("ruled_out"):
            st.markdown("#### ❌ Ruled out")
            for r in rep["ruled_out"]:
                st.write(f"- {r.get('hypothesis')} *(steps {', '.join(map(str, r.get('evidence_steps', [])))})*")
    with right:
        st.markdown("#### 🔎 Likely causes (not yet confirmed)")
        for c in rep.get("likely_causes") or []:
            st.warning(f"**{c.get('cause')}**  \nConfidence: {c.get('confidence')} · supporting steps: "
                       f"{', '.join(map(str, c.get('supporting_steps', []))) or '-'}  \n"
                       f"*How to confirm:* {c.get('how_to_confirm', '')}")
        st.markdown("#### 🛠️ Recommended actions")
        acts = rep.get("recommended_actions") or []
        if acts:
            st.dataframe(pd.DataFrame(acts), hide_index=True, use_container_width=True)

    if rep.get("suggested_check_sql"):
        with st.expander("Suggested recurrence check (SQL)"):
            st.code(rep["suggested_check_sql"], language="sql")

    st.markdown("#### 🧾 Evidence trail")
    for _, s in steps.iterrows():
        label = f"Step {s['STEP_NO']}: {s['TOOL'] or 'model error'}"
        if s["ERROR"]:
            label += "  ⚠️"
        with st.expander(label):
            if s["HYPOTHESIS"]:
                st.markdown(f"**Hypothesis:** {s['HYPOTHESIS']}")
            if s["REASONING"]:
                st.markdown(f"**Why this analysis:** {s['REASONING']}")
            if s["ERROR"]:
                st.error(s["ERROR"])
            if s["SQL_TEXT"]:
                st.code(s["SQL_TEXT"], language="sql")
            sample = as_obj(s["RESULT_SAMPLE"])
            if sample:
                st.caption(f"{s['ROW_COUNT']} row(s) returned")
                st.dataframe(pd.json_normalize(sample), hide_index=True, use_container_width=True)

    md = [f"# {rep.get('title', 'Investigation')}", f"Verdict: {verdict} · Severity: {rep.get('severity')}", "",
          rep.get("summary", ""), "", "## Confirmed findings"]
    md += [f"- {f.get('finding')} (steps {f.get('evidence_steps')})" for f in rep.get("confirmed_findings") or []]
    md += ["", "## Likely causes"] + [f"- {c.get('cause')} [{c.get('confidence')}]" for c in rep.get("likely_causes") or []]
    md += ["", "## Recommended actions"] + [f"- [{a.get('priority')}] {a.get('action')}" for a in rep.get("recommended_actions") or []]
    st.download_button("Download report (Markdown)", "\n".join(md), file_name=f"data_detective_{inv_id[:8]}.md")


# ---------------- Sidebar ----------------
st.sidebar.title("🕵️ Data Detective")
ds = datasets()
dataset_id = st.sidebar.selectbox("Dataset", ds["DATASET_ID"],
                                  format_func=lambda d: ds.set_index("DATASET_ID").loc[d, "DISPLAY_NAME"])
st.sidebar.caption(ds.set_index("DATASET_ID").loc[dataset_id, "DESCRIPTION"])
lookback = st.sidebar.slider("Lookback window (days)", 7, 60, 21)
model = st.sidebar.selectbox("Investigator model", MODELS)
max_steps = st.sidebar.slider("Max analysis steps", 2, 10, 6)

if st.sidebar.button("▶ Run checks", type="primary", use_container_width=True):
    with st.spinner("Profiling dataset: nulls, duplicates, staleness, volume, outliers, flatlines…"):
        rid = session.sql(f"CALL {CORE}.RUN_CHECKS(?, NULL, ?)", [dataset_id, lookback]).collect()[0][0]
    st.session_state["run_id"] = rid
    st.sidebar.success("Checks complete.")

tab_checks, tab_inv, tab_hist = st.tabs(["📋 Findings", "🔍 Investigation", "🗂️ History"])

# ---------------- Findings ----------------
with tab_checks:
    rdf = runs(dataset_id)
    if rdf.empty:
        st.info("No check runs yet. Click **Run checks** in the sidebar.")
    else:
        ids = list(rdf["RUN_ID"])
        default = ids.index(st.session_state["run_id"]) if st.session_state.get("run_id") in ids else 0
        run_id = st.selectbox("Check run", ids, index=default,
                              format_func=lambda r: (lambda x: f"{x['FINISHED_AT']:%Y-%m-%d %H:%M} · as of {x['AS_OF_DATE']} · {x['N_FINDINGS']} findings")(rdf.set_index('RUN_ID').loc[r]))
        f = findings(run_id)
        cols = st.columns(6)
        for i, ct in enumerate(["STALE", "VOLUME_DROP", "NULL_VALUES", "DUPLICATE", "OUTLIER", "FLATLINE"]):
            sub = f[f["CHECK_TYPE"] == ct]
            cols[i].metric(ct.replace("_", " ").title(), len(sub), f"{(sub['SEVERITY'] == 'HIGH').sum()} high", delta_color="off")

        c1, c2 = st.columns([1, 1])
        types = c1.multiselect("Check type", sorted(f["CHECK_TYPE"].unique()), default=sorted(f["CHECK_TYPE"].unique()))
        sevs = c2.multiselect("Severity", ["HIGH", "MEDIUM", "LOW"], default=["HIGH", "MEDIUM"])
        view = f[f["CHECK_TYPE"].isin(types) & f["SEVERITY"].isin(sevs)].copy()
        view["Investigated"] = view["INVESTIGATION_ID"].notna().map({True: "✅", False: ""})
        event = st.dataframe(view[["Investigated", "SEVERITY", "CHECK_TYPE", "METRIC", "OBS_DATE", "SUMMARY"]],
                             hide_index=True, use_container_width=True, on_select="rerun", selection_mode="single-row",
                             height=420)
        sel = event.selection.rows if event and hasattr(event, "selection") else []
        if sel:
            chosen = view.iloc[sel[0]]
            st.session_state["result_id"] = chosen["RESULT_ID"]
            with st.container(border=True):
                st.markdown(f"**Selected:** {chosen['SUMMARY']}")
                st.json(as_obj(chosen["DETAILS"]), expanded=False)
                b1, b2 = st.columns(2)
                if b1.button("🕵️ Investigate with Claude", type="primary"):
                    with st.spinner(f"{model} is investigating (up to {max_steps} read-only analyses)…"):
                        inv = session.sql(f"CALL {CORE}.INVESTIGATE(?, ?, ?)",
                                          [chosen["RESULT_ID"], model, max_steps]).collect()[0][0]
                    st.session_state["investigation_id"] = inv
                    st.success("Investigation complete. Open the **Investigation** tab.")
                if pd.notna(chosen["INVESTIGATION_ID"]) and b2.button("View latest report"):
                    st.session_state["investigation_id"] = chosen["INVESTIGATION_ID"]
                    st.info("Open the **Investigation** tab.")

# ---------------- Investigation ----------------
with tab_inv:
    inv_id = st.session_state.get("investigation_id")
    if not inv_id:
        st.info("Select a finding and click **Investigate with Claude**, or pick one from History.")
    else:
        render_report(inv_id)

# ---------------- History ----------------
with tab_hist:
    h = q(f"""SELECT i.investigation_id, i.started_at, i.model, i.status, i.n_steps,
                     r.check_type, r.summary, i.report:verdict::string verdict, i.report:title::string title
              FROM {CORE}.INVESTIGATIONS i JOIN {CORE}.CHECK_RESULTS r ON r.result_id = i.result_id
              WHERE i.dataset_id = ? ORDER BY i.started_at DESC LIMIT 100""", [dataset_id])
    if h.empty:
        st.info("No investigations yet.")
    else:
        ev = st.dataframe(h.drop(columns="INVESTIGATION_ID"), hide_index=True, use_container_width=True,
                          on_select="rerun", selection_mode="single-row")
        if ev.selection.rows:
            st.session_state["investigation_id"] = h.iloc[ev.selection.rows[0]]["INVESTIGATION_ID"]
            st.info("Loaded. Open the **Investigation** tab.")
