"""Data Detective: AI-powered data quality investigator (Streamlit in Snowflake)."""
import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Data Detective", layout="wide")
session = get_active_session()
CORE = "DATA_DETECTIVE.CORE"  # active schema; reassigned from the sidebar Environment toggle
SEV_ORDER = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
MODELS = ["claude-sonnet-4-5", "claude-opus-4-5", "claude-haiku-4-5"]


def q(sql: str, params: list | None = None) -> pd.DataFrame:
    return session.sql(sql, params or []).to_pandas()


def as_obj(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return {}
    return json.loads(v) if isinstance(v, str) else v


@st.cache_data(ttl=600)
def datasets(schema: str) -> pd.DataFrame:
    return q(f"SELECT dataset_id, display_name, description FROM {schema}.DATASET_REGISTRY ORDER BY dataset_id")


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
env = st.sidebar.radio("Environment", ["CORE", "DEMO"], horizontal=True,
                       help="CORE = live Marketplace data. DEMO = California-only 2024+ snapshot with labeled MOCK anomalies.")
CORE = f"DATA_DETECTIVE.{env}"
if st.session_state.get("env") != env:
    for k in ("run_id", "result_id", "investigation_id"):
        st.session_state.pop(k, None)
    st.session_state["env"] = env
if env == "DEMO":
    st.warning("🧪 **Demo environment** — California only, 2024-present snapshot. Contains labeled **MOCK** data "
               "(see DATA_DETECTIVE.DEMO.MOCK_GROUND_TRUTH).")
ds = datasets(CORE)
dataset_id = st.sidebar.selectbox("Dataset", ds["DATASET_ID"],
                                  format_func=lambda d: ds.set_index("DATASET_ID").loc[d, "DISPLAY_NAME"])
st.sidebar.caption(ds.set_index("DATASET_ID").loc[dataset_id, "DESCRIPTION"])
lookback = st.sidebar.slider("Lookback window (days)", 7, 60, 21)
model = st.sidebar.selectbox("Investigator model", MODELS)
max_steps = st.sidebar.slider("Max analysis steps", 2, 10, 6)

if st.sidebar.button("▶ Run checks", type="primary", use_container_width=True):
    with st.spinner("Profiling dataset: nulls, duplicates, staleness, volume, outliers, flatlines…"):
        if dataset_id == "WFR_V4A":
            rid = session.sql(f"CALL {CORE}.RUN_WFR_SCORE_CHECKS(NULL, ?, 20)", [lookback]).collect()[0][0]
        else:
            rid = session.sql(f"CALL {CORE}.RUN_CHECKS(?, NULL, ?)", [dataset_id, lookback]).collect()[0][0]
    st.session_state["run_id"] = rid
    st.sidebar.success("Checks complete.")

tab_checks, tab_inv, tab_hist, tab_fire = st.tabs(["📋 Findings", "🔍 Investigation", "🗂️ History", "🔥 Wildfire Risk"])

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
        check_types = (["SCORE_JUMP", "DEGRADED_HIGH_SCORE", "ISOLATED_ALERT", "SCORE_REVIEW"] if dataset_id == "WFR_V4A"
                       else ["STALE", "VOLUME_DROP", "NULL_VALUES", "DUPLICATE", "OUTLIER", "FLATLINE"])
        cols = st.columns(len(check_types))
        for i, ct in enumerate(check_types):
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

# ---------------- Wildfire Risk (wfr-v4a) ----------------
BAND_COLORS = {"Low": "#2e7d32", "Moderate": "#f9a825", "High": "#ef6c00", "Very High": "#c62828", "Extreme": "#6a1b9a"}
BAND_RGBA = {"Low": "#2e7d32aa", "Moderate": "#f9a825cc", "High": "#ef6c00dd", "Very High": "#c62828ee", "Extreme": "#6a1b9aff"}
TRUST_ICON = {"OK": "🟢 OK", "DEGRADED": "🟡 DEGRADED", "UNRELIABLE": "🔴 UNRELIABLE"}


@st.cache_data(ttl=600)
def wfr_dates(schema: str):
    return q(f"SELECT MIN(local_day) d0, MAX(local_day) d1 FROM {schema}.WFR_SCORES WHERE config_id = 'wfr-v4a'")


@st.cache_data(ttl=600)
def wfr_config(schema: str):
    return as_obj(q(f"SELECT params FROM {schema}.WFR_CONFIG WHERE config_id = 'wfr-v4a'").iloc[0]["PARAMS"])


def wfr_day(day) -> pd.DataFrame:
    return q(f"""SELECT t.zone_id, COALESCE(z.zone_name, t.zone_id) zone_name, z.latitude, z.longitude, t.score, t.band,
                        t.input_trust, t.n_stations, t.alert_types, t.trust_reasons, z.counties
                 FROM {CORE}.V_WFR_SCORES_TRUST t JOIN {CORE}.V_WFR_ZONES z ON z.zone_id = t.zone_id
                 WHERE t.local_day = ? ORDER BY t.score DESC""", [day])


with tab_fire:
    cfg = wfr_config(CORE)
    rng = wfr_dates(CORE)
    if rng.empty or pd.isna(rng.iloc[0]["D1"]):
        st.info("No wildfire scores yet. Run CALL DATA_DETECTIVE.CORE.SCORE_WILDFIRE_RISK(...).")
    else:
        st.caption(f"Model **wfr-v4a** · {cfg.get('unit')} · out-of-sample AUC {cfg.get('test_auc_10ac_3d')} "
                   f"(Red Flag Warning baseline {cfg.get('rfw_auc_10ac_3d')}) · verdict: **{cfg.get('verdict')}**. "
                   "No live fuel-moisture or ignition data. Scores are relative to each zone's own history.")
        c1, c2, c3 = st.columns([1, 2, 2])
        day = c1.date_input("Date", value=rng.iloc[0]["D1"], min_value=rng.iloc[0]["D0"], max_value=rng.iloc[0]["D1"])
        bands = c2.multiselect("Bands", list(BAND_COLORS), default=list(BAND_COLORS))
        search = c3.text_input("Search zone / name / county FIPS (e.g. CAZ264, Santa, 06037)")
        zdf = wfr_day(day)
        view = zdf[zdf["BAND"].isin(bands)].copy()
        if search:
            m = (view["ZONE_ID"].str.contains(search, case=False) | view["ZONE_NAME"].str.contains(search, case=False, na=False)
                 | view["COUNTIES"].astype(str).str.contains(search, case=False))
            view = view[m]

        k = st.columns(6)
        for i, b in enumerate(BAND_COLORS):
            k[i].metric(b, int((zdf["BAND"] == b).sum()))
        k[5].metric("Low-trust zones", int((zdf["INPUT_TRUST"] != "OK").sum()))

        left, right = st.columns([3, 2])
        with left:
            mp = view.dropna(subset=["LATITUDE", "LONGITUDE"]).copy()
            mp["color"] = mp["BAND"].map(BAND_RGBA)
            mp["size"] = 3000 + mp["SCORE"] * 120
            st.map(mp, latitude="LATITUDE", longitude="LONGITUDE", color="color", size="size")
            st.caption(" · ".join(f"<span style='color:{c}'>●</span> {b}" for b, c in BAND_COLORS.items()), unsafe_allow_html=True)
        with right:
            tbl = view[["ZONE_ID", "ZONE_NAME", "SCORE", "BAND", "INPUT_TRUST", "N_STATIONS"]].copy()
            tbl["INPUT_TRUST"] = tbl["INPUT_TRUST"].map(TRUST_ICON)
            ev = st.dataframe(tbl, hide_index=True, use_container_width=True, height=460, on_select="rerun",
                              selection_mode="single-row",
                              column_config={"SCORE": st.column_config.ProgressColumn("Score", min_value=0, max_value=100, format="%.1f")})
        sel_rows = ev.selection.rows if ev and hasattr(ev, "selection") else []
        if sel_rows:
            zone = view.iloc[sel_rows[0]]["ZONE_ID"]
            d = q(f"""SELECT * FROM {CORE}.V_WFR_SCORES_TRUST WHERE zone_id = ? AND local_day = ?""", [zone, day]).iloc[0]
            hist = q(f"""SELECT local_day, score, input_trust FROM {CORE}.V_WFR_SCORES_TRUST
                         WHERE zone_id = ? AND local_day BETWEEN DATEADD(day, -30, ?::DATE) AND ? ORDER BY local_day""", [zone, day, day])
            st.divider()
            st.subheader(f"{zone} · {view.iloc[sel_rows[0]]['ZONE_NAME']} · {day}")
            a, b, c, e = st.columns(4)
            a.metric("Score", f"{d['SCORE']:.1f}")
            b.markdown(f"**Band**<br><span style='font-size:1.6em;color:{BAND_COLORS.get(d['BAND'])}'>{d['BAND']}</span>", unsafe_allow_html=True)
            c.metric("Input trust", TRUST_ICON.get(d["INPUT_TRUST"], d["INPUT_TRUST"]))
            e.metric("Reporting stations", int(d["N_STATIONS"]))

            w = cfg["weights"]
            factors = pd.DataFrame([
                ("Dryness", f"{d['DRYNESS_RH']:.1f} % min RH" if pd.notna(d["DRYNESS_RH"]) else "missing", d["P_DRYNESS"], w["dryness"]),
                ("Wind", f"{d['WIND_MPH']:.1f} mph" if pd.notna(d["WIND_MPH"]) else "missing", d["P_WIND"], w["wind"]),
                ("Heat", f"{d['HEAT_F']:.1f} °F max" if pd.notna(d["HEAT_F"]) else "missing", d["P_HEAT"], w["heat"]),
                ("Alert", ", ".join(as_obj(d["ALERT_TYPES"]) or []) or "none", d["P_ALERT"], w["alert"]),
                ("Fire history (all)", f"{int(d['N_FIRES_ALL'] or 0)} fires ≥10 ac (2020–Jul 2024)", d["P_HIST_ALL"], w["hist_all"]),
                ("Fire history (season)", f"{int(d['N_FIRES_SEASON'] or 0)} fires in month ±1", d["P_HIST_SEASON"], w["hist_season"]),
            ], columns=["Factor", "Raw value", "Percentile", "Weight"])
            factors["Points"] = (100 * factors["Percentile"] * factors["Weight"] / cfg["weight_total"]).round(1)
            fl, fr = st.columns([3, 2])
            fl.dataframe(factors, hide_index=True, use_container_width=True,
                         column_config={"Percentile": st.column_config.ProgressColumn(min_value=0, max_value=1, format="%.2f")})
            fr.bar_chart(factors.set_index("Factor")["Points"], horizontal=True, height=250)

            st.markdown("**Last 30 days**")
            st.line_chart(hist.set_index("LOCAL_DAY")["SCORE"], height=200)

            reasons = as_obj(d["TRUST_REASONS"]) or []
            if reasons and d["INPUT_TRUST"] != "OK":
                st.warning("**Why input trust is not OK:**  \n" + "  \n".join(f"- {r}" for r in reasons))
            elif reasons:
                st.info(f"**Minor data-quality notes** ({int(d['N_BAD_STATIONS'])} of {int(d['N_STATIONS'])} stations; "
                        "the zone median is robust to these):  \n" + "  \n".join(f"- {r}" for r in reasons))
            with st.expander("Stations used"):
                st.dataframe(q(f"""SELECT d.station_id, s.station_name, ROUND(d.min_rh, 1) min_rh, ROUND(d.max_wind_mph, 1) wind_mph,
                                          ROUND(d.max_temp_f, 1) max_temp_f, d.n_hours
                                   FROM {CORE}.WFR_STATION_DAY d JOIN {CORE}.V_WFR_STATIONS s ON s.station_id = d.station_id
                                   WHERE s.zone_id = ? AND d.local_day = ? ORDER BY d.station_id""", [zone, day]),
                             hide_index=True, use_container_width=True)

            if st.button("🕵️ Investigate this score with Claude", type="primary"):
                with st.spinner(f"{model} is explaining {zone} on {day}…"):
                    fid = session.sql(f"CALL {CORE}.CREATE_WFR_REVIEW(?, ?)", [zone, day]).collect()[0][0]
                    inv = session.sql(f"CALL {CORE}.INVESTIGATE(?, ?, ?)", [fid, model, max_steps]).collect()[0][0]
                st.session_state["investigation_id"] = inv
                st.success("Done. Open the **Investigation** tab for the evidence-backed report.")
