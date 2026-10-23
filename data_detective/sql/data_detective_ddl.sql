create or replace database DATA_DETECTIVE;

create or replace schema DATA_DETECTIVE.CORE;

create or replace TABLE DATA_DETECTIVE.CORE.BASELINES (
	DATASET_ID VARCHAR(16777216),
	ENTITY_ID VARCHAR(16777216),
	METRIC VARCHAR(16777216),
	MONTH_OF_YEAR NUMBER(38,0),
	N_OBS NUMBER(38,0),
	MEDIAN_VALUE FLOAT,
	P25 FLOAT,
	P75 FLOAT,
	P01 FLOAT,
	P99 FLOAT,
	BUILT_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.CORE.CHECK_RESULTS (
	RESULT_ID VARCHAR(16777216),
	RUN_ID VARCHAR(16777216),
	DATASET_ID VARCHAR(16777216),
	CHECK_TYPE VARCHAR(16777216),
	METRIC VARCHAR(16777216),
	OBS_DATE DATE,
	SEVERITY VARCHAR(16777216),
	AFFECTED_COUNT NUMBER(38,0),
	OBSERVED FLOAT,
	EXPECTED FLOAT,
	SUMMARY VARCHAR(16777216),
	DETAILS VARIANT,
	CREATED_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.CORE.CHECK_RUNS (
	RUN_ID VARCHAR(16777216),
	DATASET_ID VARCHAR(16777216),
	AS_OF_DATE DATE,
	WINDOW_START DATE,
	STARTED_AT TIMESTAMP_LTZ(9),
	FINISHED_AT TIMESTAMP_LTZ(9),
	N_FINDINGS NUMBER(38,0)
);
create or replace TABLE DATA_DETECTIVE.CORE.DATASET_REGISTRY (
	DATASET_ID VARCHAR(16777216) NOT NULL,
	DISPLAY_NAME VARCHAR(16777216),
	OBS_VIEW VARCHAR(16777216),
	ENTITY_VIEW VARCHAR(16777216),
	DESCRIPTION VARCHAR(16777216),
	STALE_DAYS NUMBER(38,0),
	MISSING_DROP_PCT FLOAT,
	OUTLIER_Z FLOAT,
	BASELINE_DATASET VARCHAR(16777216),
	primary key (DATASET_ID)
);
create or replace TABLE DATA_DETECTIVE.CORE.DEMO_GROUND_TRUTH (
	ISSUE_ID NUMBER(38,0),
	EXPECTED_CHECK VARCHAR(16777216),
	ENTITY_SCOPE VARCHAR(16777216),
	METRIC VARCHAR(16777216),
	DATE_FROM DATE,
	DATE_TO DATE,
	TRUE_ROOT_CAUSE VARCHAR(16777216)
);
create or replace TABLE DATA_DETECTIVE.CORE.INVESTIGATIONS (
	INVESTIGATION_ID VARCHAR(16777216),
	RESULT_ID VARCHAR(16777216),
	DATASET_ID VARCHAR(16777216),
	MODEL VARCHAR(16777216),
	STATUS VARCHAR(16777216),
	STARTED_AT TIMESTAMP_LTZ(9),
	FINISHED_AT TIMESTAMP_LTZ(9),
	N_STEPS NUMBER(38,0),
	REPORT VARIANT
);
create or replace TABLE DATA_DETECTIVE.CORE.INVESTIGATION_STEPS (
	INVESTIGATION_ID VARCHAR(16777216),
	STEP_NO NUMBER(38,0),
	HYPOTHESIS VARCHAR(16777216),
	REASONING VARCHAR(16777216),
	TOOL VARCHAR(16777216),
	ARGS VARIANT,
	SQL_TEXT VARCHAR(16777216),
	ROW_COUNT NUMBER(38,0),
	RESULT_SAMPLE VARIANT,
	ERROR VARCHAR(16777216),
	CREATED_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.CORE.METRIC_BOUNDS (
	METRIC VARCHAR(16777216),
	MIN_VALUE FLOAT,
	MAX_VALUE FLOAT,
	UNIT VARCHAR(16777216)
);
create or replace view DATA_DETECTIVE.CORE.V_DEMO_EVAL(
	ISSUE_ID,
	EXPECTED_CHECK,
	ENTITY_SCOPE,
	TRUE_ROOT_CAUSE,
	DETECTED,
	VERDICT,
	INVESTIGATOR_TITLE,
	INVESTIGATOR_SUMMARY
) as
WITH last_run AS (
  SELECT run_id FROM CHECK_RUNS WHERE dataset_id = 'NOAA_DAILY_DEMO' AND finished_at IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (ORDER BY started_at DESC) = 1),
hits AS (
  SELECT g.issue_id, r.result_id
  FROM DEMO_GROUND_TRUTH g
  JOIN CHECK_RESULTS r ON r.run_id = (SELECT run_id FROM last_run) AND r.check_type = g.expected_check
   AND (SPLIT_PART(g.entity_scope, ' ', 1) = r.details:entity_id::STRING
        OR (g.expected_check = 'STALE' AND r.details:segment::STRING = 'Colorado | COOP'))),
inv AS (
  SELECT result_id, report FROM INVESTIGATIONS WHERE status = 'COMPLETED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY result_id ORDER BY started_at DESC) = 1)
SELECT g.issue_id, g.expected_check, g.entity_scope, g.true_root_cause,
       h.result_id IS NOT NULL AS detected,
       inv.report:verdict::STRING AS verdict,
       inv.report:title::STRING AS investigator_title,
       inv.report:summary::STRING AS investigator_summary
FROM DEMO_GROUND_TRUTH g
LEFT JOIN hits h ON h.issue_id = g.issue_id
LEFT JOIN inv ON inv.result_id = h.result_id
ORDER BY g.issue_id;
create or replace view DATA_DETECTIVE.CORE.V_NOAA_ENTITIES(
	ENTITY_ID,
	ENTITY_NAME,
	REGION,
	COUNTRY_NAME,
	LATITUDE,
	LONGITUDE,
	ELEVATION,
	NETWORK,
	SEGMENT
) as
SELECT noaa_weather_station_id AS entity_id, noaa_weather_station_name AS entity_name,
  COALESCE(state_name, country_name) AS region, country_name, latitude, longitude, elevation,
  CASE WHEN weather_station_network ILIKE '%CoCoRaHS%' THEN 'CoCoRaHS'
       WHEN weather_station_network ILIKE '%Cooperative Network%' THEN 'COOP'
       WHEN weather_station_network ILIKE '%SNOTEL%' THEN 'SNOTEL'
       WHEN weather_station_network ILIKE '%RAWS%' THEN 'RAWS'
       WHEN weather_station_network ILIKE '%WBAN%' THEN 'WBAN'
       WHEN weather_station_network ILIKE '%WMO%' THEN 'WMO'
       ELSE COALESCE(LEFT(weather_station_network, 40), 'UNKNOWN') END AS network,
  COALESCE(state_name, country_name) || ' | ' || network AS segment
FROM SNOWFLAKE_CURATED_DATA_CORE_WEATHER_DATA.PUBLIC_DATA.NOAA_WEATHER_STATION_INDEX;
create or replace view DATA_DETECTIVE.CORE.V_NOAA_OBS(
	ENTITY_ID,
	METRIC,
	OBS_DATE,
	VALUE,
	UNIT
) as
SELECT noaa_weather_station_id AS entity_id, variable AS metric, date AS obs_date, value, unit
FROM SNOWFLAKE_CURATED_DATA_CORE_WEATHER_DATA.PUBLIC_DATA.NOAA_WEATHER_METRICS_TIMESERIES
WHERE variable IN ('precipitation','snowfall','snow_depth','minimum_temperature','maximum_temperature','average_daily_wind_speed');
create or replace view DATA_DETECTIVE.CORE.V_NOAA_OBS_DEMO(
	ENTITY_ID,
	METRIC,
	OBS_DATE,
	VALUE,
	UNIT
) as
WITH base AS (
  SELECT o.* FROM V_NOAA_OBS o
  WHERE o.obs_date >= '2026-08-05'
    AND NOT (o.obs_date > '2026-10-12' AND o.entity_id LIKE 'USC%'
             AND o.entity_id IN (SELECT entity_id FROM V_NOAA_ENTITIES WHERE region = 'Colorado'))
)
SELECT entity_id, metric, obs_date,
  CASE
    WHEN entity_id = 'USC00051121' AND metric IN ('maximum_temperature','minimum_temperature') AND obs_date BETWEEN '2026-10-05' AND '2026-10-10' THEN ROUND(value * 9/5 + 32, 1)
    WHEN entity_id = 'USC00052281' AND metric = 'snow_depth' AND obs_date BETWEEN '2026-10-01' AND '2026-10-07' THEN NULL
    WHEN entity_id = 'USC00051959' AND metric = 'maximum_temperature' AND obs_date BETWEEN '2026-10-02' AND '2026-10-11' THEN 21.1
    ELSE value END AS value,
  unit
FROM base
UNION ALL
SELECT entity_id, metric, obs_date, value + 2.5, unit FROM V_NOAA_OBS
WHERE entity_id = 'USC00051294' AND metric = 'precipitation' AND obs_date BETWEEN '2026-10-01' AND '2026-10-03';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.BUILD_BASELINES("DATASET_ID" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
def run(session, dataset_id):
    reg = session.sql("SELECT obs_view FROM DATA_DETECTIVE.CORE.DATASET_REGISTRY WHERE dataset_id = ?", [dataset_id]).collect()
    if not reg:
        return f"Unknown dataset {dataset_id}"
    obs = reg[0]["OBS_VIEW"]
    session.sql("DELETE FROM DATA_DETECTIVE.CORE.BASELINES WHERE dataset_id = ?", [dataset_id]).collect()
    session.sql(f"""
        INSERT INTO DATA_DETECTIVE.CORE.BASELINES
        WITH mx AS (SELECT MAX(obs_date) d FROM {obs})
        SELECT ?, entity_id, metric, MONTH(obs_date), COUNT(*),
               MEDIAN(value),
               PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY value),
               PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY value),
               PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY value),
               PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY value),
               CURRENT_TIMESTAMP()
        FROM {obs}, mx
        WHERE obs_date BETWEEN DATEADD(day, -410, mx.d) AND DATEADD(day, -45, mx.d)
          AND value IS NOT NULL
        GROUP BY entity_id, metric, MONTH(obs_date)
    """, [dataset_id]).collect()
    n = session.sql("SELECT COUNT(*) c FROM DATA_DETECTIVE.CORE.BASELINES WHERE dataset_id = ?", [dataset_id]).collect()[0]["C"]
    return f"Built {n} baseline rows for {dataset_id}"
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.INVESTIGATE("RESULT_ID" VARCHAR, "MODEL" VARCHAR DEFAULT 'claude-sonnet-4-5', "MAX_STEPS" NUMBER(38,0) DEFAULT 6)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
import json, re, uuid, datetime, decimal

ROW_LIMIT = 200       # rows fetched per analysis
PROMPT_ROWS = 40      # rows shown to Claude per step
ID_RE = re.compile(r"^[A-Za-z0-9_\\-]{1,32}$")
DATE_RE = re.compile(r"^\\d{4}-\\d{2}-\\d{2}$")
MODEL_RE = re.compile(r"^[a-z0-9.\\-]{2,40}$")
FORBIDDEN = re.compile(r"\\b(INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|CALL|EXECUTE|COPY|PUT|GET|USE|SET|UNSET|BEGIN|COMMIT|ROLLBACK|REMOVE|LIST|SHOW|DESCRIBE|DESC|UNDROP|SYSTEM\\$\\w*)\\b", re.I)

def _json_default(o):
    if isinstance(o, (datetime.date, datetime.datetime)):
        return o.isoformat()
    if isinstance(o, decimal.Decimal):
        return float(o)
    return str(o)

def _rows(rows):
    out = []
    for r in rows:
        d = r.as_dict()
        out.append({k.lower(): (json.loads(v) if isinstance(v, str) and v[:1] in "[{" else v) for k, v in d.items()})
    return out

class Tools:
    """Read-only analysis catalog. All user/LLM-supplied values are validated and passed as binds."""
    def __init__(self, session, reg, metrics):
        self.s, self.obs, self.ent, self.base_ds = session, reg["OBS_VIEW"], reg["ENTITY_VIEW"], reg["BASELINE_DATASET"]
        self.metrics = metrics
        self.allowed_objects = {self.obs.upper(), self.ent.upper(), "DATA_DETECTIVE.CORE.BASELINES",
                                "DATA_DETECTIVE.CORE.METRIC_BOUNDS"}

    # --- validators ---
    def _id(self, v, name):
        v = str(v or "")
        if not ID_RE.match(v): raise ValueError(f"invalid {name}: {v!r}")
        return v
    def _date(self, v, name):
        v = str(v or "")
        if not DATE_RE.match(v): raise ValueError(f"invalid {name} (YYYY-MM-DD): {v!r}")
        return v
    def _metric(self, v):
        if v not in self.metrics: raise ValueError(f"invalid metric {v!r}; allowed: {sorted(self.metrics)}")
        return v
    def _text(self, v, name):
        v = str(v or "")
        if not v or len(v) > 120: raise ValueError(f"invalid {name}")
        return v

    def catalog(self):
        return {
          "entity_profile": {"args": {"entity_id": "str"}, "desc": "Station metadata (name, region, network, lat/lon, elevation) and per-metric first/last observation dates and row counts in the last 90 days."},
          "entity_timeseries": {"args": {"entity_id": "str", "metric": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "Daily values for one entity/metric with baseline median/p01/p99 for that month and row count per day (detects duplicates)."},
          "cross_metric": {"args": {"entity_id": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "All metrics for one entity per day, to check whether an issue affects one metric or the whole station."},
          "compare_neighbors": {"args": {"entity_id": "str", "metric": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD", "radius_km": "number (default 75)"}, "desc": "Per day: target value vs median/min/max of nearby stations'' values for the same metric. Distinguishes real weather from sensor/load errors."},
          "segment_reporting": {"args": {"region": "str (state or country)", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "Per day and network within a region: number of distinct reporting stations and rows. Reveals outages and which networks are affected."},
          "network_reporting_nationwide": {"args": {"network": "str (e.g. COOP, CoCoRaHS, SNOTEL)", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "Per day and top regions for one network: reporting station counts. Tells whether an outage is regional or network-wide."},
          "metric_day_profile": {"args": {"metric": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "Dataset-wide per-day stats for a metric: rows, entities, nulls, duplicate keys, p01/p50/p99."},
          "run_sql": {"args": {"sql": "a single read-only SELECT/WITH query"}, "desc": f"Free-form read-only SQL. Only these objects may be referenced: {sorted(self.allowed_objects)}. Columns of obs view: entity_id, metric, obs_date, value, unit. Entity view: entity_id, entity_name, region, country_name, latitude, longitude, elevation, network, segment. Results capped at {ROW_LIMIT} rows."},
        }

    def call(self, tool, a):
        a = a or {}
        if tool == "entity_profile":
            e = self._id(a.get("entity_id"), "entity_id")
            sql = f"""SELECT e.entity_id, e.entity_name, e.region, e.network, e.latitude, e.longitude, e.elevation,
                        o.metric, MIN(o.obs_date) first_date_90d, MAX(o.obs_date) last_date, COUNT(*) rows_90d
                      FROM {self.ent} e LEFT JOIN {self.obs} o ON o.entity_id = e.entity_id
                        AND o.obs_date >= DATEADD(day, -90, (SELECT MAX(obs_date) FROM {self.obs}))
                      WHERE e.entity_id = ? GROUP BY ALL ORDER BY o.metric"""
            return sql, [e]
        if tool == "entity_timeseries":
            e, m = self._id(a.get("entity_id"), "entity_id"), self._metric(a.get("metric"))
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = f"""SELECT o.obs_date, COUNT(*) n_rows, ARRAY_AGG(o.value) vals, ANY_VALUE(o.unit) unit,
                        ANY_VALUE(b.median_value) baseline_median, ANY_VALUE(b.p01) baseline_p01, ANY_VALUE(b.p99) baseline_p99
                      FROM {self.obs} o LEFT JOIN DATA_DETECTIVE.CORE.BASELINES b ON b.dataset_id = ? AND b.entity_id = o.entity_id
                        AND b.metric = o.metric AND b.month_of_year = MONTH(o.obs_date)
                      WHERE o.entity_id = ? AND o.metric = ? AND o.obs_date BETWEEN ? AND ?
                      GROUP BY o.obs_date ORDER BY o.obs_date"""
            return sql, [self.base_ds, e, m, d0, d1]
        if tool == "cross_metric":
            e = self._id(a.get("entity_id"), "entity_id")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = f"""SELECT obs_date, OBJECT_AGG(metric, value::VARIANT) metrics, COUNT(*) n_rows
                      FROM (SELECT obs_date, metric, ANY_VALUE(value) value FROM {self.obs}
                            WHERE entity_id = ? AND obs_date BETWEEN ? AND ? GROUP BY 1,2)
                      GROUP BY obs_date ORDER BY obs_date"""
            return sql, [e, d0, d1]
        if tool == "compare_neighbors":
            e, m = self._id(a.get("entity_id"), "entity_id"), self._metric(a.get("metric"))
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            radius = max(5.0, min(float(a.get("radius_km") or 75), 300.0))
            sql = f"""WITH t AS (SELECT latitude, longitude FROM {self.ent} WHERE entity_id = ?),
                      nb AS (SELECT e.entity_id FROM {self.ent} e, t WHERE e.entity_id <> ?
                             AND HAVERSINE(t.latitude, t.longitude, e.latitude, e.longitude) <= ?),
                      v AS (SELECT obs_date, entity_id, AVG(value) value FROM {self.obs}
                            WHERE metric = ? AND obs_date BETWEEN ? AND ? AND (entity_id = ? OR entity_id IN (SELECT entity_id FROM nb))
                            GROUP BY 1,2)
                      SELECT obs_date, MAX(IFF(entity_id = ?, value, NULL)) target_value,
                             MEDIAN(IFF(entity_id <> ?, value, NULL)) neighbor_median,
                             MIN(IFF(entity_id <> ?, value, NULL)) neighbor_min, MAX(IFF(entity_id <> ?, value, NULL)) neighbor_max,
                             COUNT(DISTINCT IFF(entity_id <> ?, entity_id, NULL)) n_neighbors
                      FROM v GROUP BY obs_date ORDER BY obs_date"""
            return sql, [e, e, radius, m, d0, d1, e, e, e, e, e, e]
        if tool == "segment_reporting":
            r = self._text(a.get("region"), "region")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = f"""SELECT o.obs_date, e.network, COUNT(DISTINCT o.entity_id) reporting_entities, COUNT(*) n_rows
                      FROM {self.obs} o JOIN {self.ent} e ON e.entity_id = o.entity_id
                      WHERE e.region = ? AND o.obs_date BETWEEN ? AND ?
                      GROUP BY 1,2 ORDER BY 1,2"""
            return sql, [r, d0, d1]
        if tool == "network_reporting_nationwide":
            n = self._text(a.get("network"), "network")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = f"""WITH d AS (SELECT o.obs_date, e.region, COUNT(DISTINCT o.entity_id) k
                                 FROM {self.obs} o JOIN {self.ent} e ON e.entity_id = o.entity_id
                                 WHERE e.network = ? AND o.obs_date BETWEEN ? AND ? GROUP BY 1,2),
                      top AS (SELECT region FROM d GROUP BY 1 ORDER BY SUM(k) DESC LIMIT 12)
                      SELECT obs_date, SUM(k) total_reporting, OBJECT_AGG(IFF(region IN (SELECT region FROM top), region, NULL), k::VARIANT) by_top_region
                      FROM d GROUP BY 1 ORDER BY 1"""
            return sql, [n, d0, d1]
        if tool == "metric_day_profile":
            m = self._metric(a.get("metric"))
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = f"""SELECT obs_date, COUNT(*) n_rows, COUNT(DISTINCT entity_id) n_entities, COUNT_IF(value IS NULL) n_nulls,
                        COUNT(*) - COUNT(DISTINCT entity_id) duplicate_keys,
                        APPROX_PERCENTILE(value, 0.01) p01, MEDIAN(value) p50, APPROX_PERCENTILE(value, 0.99) p99
                      FROM {self.obs} WHERE metric = ? AND obs_date BETWEEN ? AND ? GROUP BY 1 ORDER BY 1"""
            return sql, [m, d0, d1]
        if tool == "run_sql":
            return self.validate_sql(a.get("sql")), []
        raise ValueError(f"unknown tool {tool!r}")

    def validate_sql(self, sql):
        sql = (sql or "").strip()
        sql = re.sub(r"--[^\\n]*", " ", sql)
        sql = re.sub(r"/\\*.*?\\*/", " ", sql, flags=re.S).strip().rstrip(";").strip()
        if ";" in sql: raise ValueError("only a single statement is allowed")
        if not re.match(r"^(SELECT|WITH)\\b", sql, re.I): raise ValueError("query must start with SELECT or WITH")
        if FORBIDDEN.search(sql): raise ValueError(f"forbidden keyword: {FORBIDDEN.search(sql).group(0)}")
        if re.search(r"\\b(TABLE|IDENTIFIER|RESULT_SCAN|GENERATOR)\\s*\\(", sql, re.I): raise ValueError("table functions are not allowed")
        if re.search(r"[@$]", sql): raise ValueError("stages and variables are not allowed")
        bare = re.sub(r"''(?:[^'']|'''')*''", "''''", sql)
        if re.search(r"\\bFROM\\s+[A-Za-z0-9_.\\"]+(?:\\s+(?:AS\\s+)?(?!JOIN|WHERE|GROUP|ORDER|LIMIT|QUALIFY|HAVING|UNION|ON|INNER|LEFT|RIGHT|FULL|CROSS|NATURAL)[A-Za-z_]\\w*)?\\s*,", bare, re.I):
            raise ValueError("comma joins are not allowed; use explicit JOIN")
        for fq in re.findall(r"\\b[A-Za-z_][\\w$]*\\s*\\.\\s*[A-Za-z_][\\w$]*\\s*\\.\\s*[A-Za-z_][\\w$]*\\b", bare):
            if re.sub(r"\\s", "", fq).upper() not in self.allowed_objects:
                raise ValueError(f"object {fq} is not in the allowlist {sorted(self.allowed_objects)}")
        ctes = {m.upper() for m in re.findall(r"(?:WITH|,)\\s*([A-Za-z_][A-Za-z0-9_]*)\\s+AS\\s*\\(", sql, re.I)}
        for ref in re.findall(r"\\b(?:FROM|JOIN)\\s+([A-Za-z0-9_.\\"]+)", sql, re.I):
            r = ref.replace(''"'', "").upper()
            if r not in self.allowed_objects and r not in ctes:
                raise ValueError(f"object {ref} is not in the allowlist {sorted(self.allowed_objects)}")
        return f"SELECT * FROM ({sql}) LIMIT {ROW_LIMIT}"

SYSTEM = """You are Data Detective, a meticulous data-quality investigator working inside Snowflake.
You are given one anomaly flagged by automated profiling checks. Find its root cause using ONLY evidence from
the read-only analyses available to you. Think like a scientist: state a hypothesis, choose the single analysis that
best tests it, then update your beliefs.

Key distinctions to test:
- Real-world event (weather) vs data error: neighbors and related metrics corroborate real events.
- Scope: one entity vs a network vs a region vs the whole dataset; one metric vs all metrics.
- Error type: missing/late feed, duplicate load, unit/scale error, stuck sensor, null load, true extreme.

Rules:
- Respond with ONE JSON object and nothing else.
- To run an analysis: {"hypothesis": "...", "reasoning": "...", "action": "tool", "tool": "<name>", "args": {...}}
- To finish: {"action": "final", "report": {...}} with the report schema below.
- A "confirmed_finding" MUST cite evidence_steps (step numbers whose results directly show it). Anything inferred
  but not directly shown (e.g. *why* an upstream feed failed) is a "likely_cause" with a confidence level.
- Never invent numbers; quote values seen in results.
- Prefer the catalog tools; use run_sql only when no catalog tool fits.

Report schema:
{"title": str, "severity": "HIGH|MEDIUM|LOW", "verdict": "DATA_ERROR|REAL_EVENT|INCONCLUSIVE",
 "summary": str (2-4 sentences),
 "affected": {"entities": [str], "regions": [str], "networks": [str], "metrics": [str], "date_from": str, "date_to": str, "estimated_rows": int|null},
 "confirmed_findings": [{"finding": str, "evidence_steps": [int]}],
 "likely_causes": [{"cause": str, "confidence": "high|medium|low", "supporting_steps": [int], "how_to_confirm": str}],
 "ruled_out": [{"hypothesis": str, "evidence_steps": [int]}],
 "recommended_actions": [{"action": str, "priority": "P1|P2|P3", "type": "fix|quarantine|monitor|escalate"}],
 "suggested_check_sql": str (a read-only SELECT that would detect recurrence, or "")}"""

def _parse_json(text):
    text = (text or "").strip()
    if text.startswith(''"''):
        text = json.loads(text)
    text = re.sub(r"^```(?:json)?|```$", "", text.strip()).strip()
    m = re.search(r"\\{.*\\}", text, re.S)
    if not m: raise ValueError("no JSON object in model output")
    return json.loads(m.group(0))

def _llm(session, model, prompt):
    out = session.sql(f"SELECT AI_COMPLETE(''{model}'', ?, {{''temperature'': 0, ''max_tokens'': 4000}}) r", [prompt]).collect()[0]["R"]
    return out

def _enforce_evidence(report, ok_steps):
    """Demote ''confirmed'' findings that do not cite at least one successful step."""
    confirmed, demoted = [], []
    for f in report.get("confirmed_findings", []) or []:
        steps = [s for s in (f.get("evidence_steps") or []) if isinstance(s, int) and s in ok_steps]
        if steps:
            f["evidence_steps"] = steps
            confirmed.append(f)
        else:
            demoted.append({"cause": f.get("finding", ""), "confidence": "low", "supporting_steps": [],
                            "how_to_confirm": "Demoted by Data Detective: no successful analysis step was cited as evidence."})
    report["confirmed_findings"] = confirmed
    report["likely_causes"] = (report.get("likely_causes") or []) + demoted
    for c in report["likely_causes"]:
        c["supporting_steps"] = [s for s in (c.get("supporting_steps") or []) if isinstance(s, int) and s in ok_steps]
    return report

def run(session, result_id, model, max_steps):
    model = model or "claude-sonnet-4-5"
    if not MODEL_RE.match(model): return "invalid model name"
    max_steps = max(1, min(int(max_steps or 6), 10))
    try:
        # Not permitted when invoked from an owner''s-rights context (e.g. Streamlit); best effort only
        session.sql("ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 120").collect()
    except Exception:
        pass

    f = session.sql("SELECT * FROM DATA_DETECTIVE.CORE.CHECK_RESULTS WHERE result_id = ?", [result_id]).collect()
    if not f: return f"unknown result_id {result_id}"
    finding = _rows(f)[0]
    reg = session.sql("SELECT * FROM DATA_DETECTIVE.CORE.DATASET_REGISTRY WHERE dataset_id = ?", [finding["dataset_id"]]).collect()[0]
    run_info = _rows(session.sql("SELECT as_of_date, window_start FROM DATA_DETECTIVE.CORE.CHECK_RUNS WHERE run_id = ?", [finding["run_id"]]).collect())[0]
    metrics = {r["METRIC"] for r in session.sql("SELECT metric FROM DATA_DETECTIVE.CORE.METRIC_BOUNDS").collect()}
    tools = Tools(session, reg, metrics)

    inv_id = str(uuid.uuid4())
    session.sql("""INSERT INTO DATA_DETECTIVE.CORE.INVESTIGATIONS (investigation_id, result_id, dataset_id, model, status, started_at)
                   VALUES (?, ?, ?, ?, ''RUNNING'', CURRENT_TIMESTAMP())""", [inv_id, result_id, finding["dataset_id"], model]).collect()

    context = {
        "dataset": {"id": reg["DATASET_ID"], "description": reg["DESCRIPTION"], "metrics": sorted(metrics),
                    "check_window": run_info},
        "anomaly": {k: finding[k] for k in ("check_type", "metric", "obs_date", "severity", "affected_count", "observed", "expected", "summary", "details")},
        "tools": tools.catalog(),
    }
    history, ok_steps, report = [], set(), None
    for step in range(1, max_steps + 2):
        final_turn = step > max_steps
        prompt = SYSTEM + "\\n\\nCONTEXT:\\n" + json.dumps(context, default=_json_default) + "\\n\\nSTEPS SO FAR:\\n" + \\
                 (json.dumps(history, default=_json_default) if history else "[] (none yet)") + \\
                 ("\\n\\nYou have used all analysis steps. Respond now with action=final." if final_turn else
                  f"\\n\\nYou have {max_steps - step + 1} analysis step(s) left. Respond with your next JSON action.")
        raw = None
        try:
            raw = _llm(session, model, prompt)
            msg = _parse_json(raw)
        except Exception as e:
            err = f"model call/parse failed: {str(e)[:300]}"
            history.append({"step": step, "error": err})
            session.sql("""INSERT INTO DATA_DETECTIVE.CORE.INVESTIGATION_STEPS (investigation_id, step_no, reasoning, error, created_at)
                           VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP())""", [inv_id, step, (raw or "")[:2000], err]).collect()
            continue
        if msg.get("action") == "final" or final_turn:
            report = msg.get("report") or {}
            break
        tool, args = msg.get("tool"), msg.get("args") or {}
        sql_text, rows, err = None, [], None
        try:
            sql_text, binds = tools.call(tool, args)
            rows = _rows(session.sql(sql_text, binds).collect())
            ok_steps.add(step)
        except Exception as e:
            err = str(e)[:500]
        sample = rows[:PROMPT_ROWS]
        history.append({"step": step, "hypothesis": msg.get("hypothesis"), "tool": tool, "args": args,
                        "row_count": len(rows), "rows": sample, "truncated": len(rows) > PROMPT_ROWS, "error": err})
        session.sql("""INSERT INTO DATA_DETECTIVE.CORE.INVESTIGATION_STEPS
                       SELECT ?, ?, ?, ?, ?, PARSE_JSON(?), ?, ?, PARSE_JSON(?), ?, CURRENT_TIMESTAMP()""",
                    [inv_id, step, msg.get("hypothesis"), msg.get("reasoning"), tool, json.dumps(args, default=_json_default),
                     sql_text, len(rows), json.dumps(rows[:ROW_LIMIT], default=_json_default), err]).collect()

    status = "COMPLETED"
    if report is None:
        status, report = "FAILED", {"title": "Investigation did not complete", "verdict": "INCONCLUSIVE", "summary": "The model did not return a final report."}
    report = _enforce_evidence(report, ok_steps)
    session.sql("""UPDATE DATA_DETECTIVE.CORE.INVESTIGATIONS SET status = ?, finished_at = CURRENT_TIMESTAMP(),
                   n_steps = ?, report = PARSE_JSON(?) WHERE investigation_id = ?""",
                [status, len(ok_steps), json.dumps(report, default=_json_default), inv_id]).collect()
    return inv_id
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.RUN_CHECKS("DATASET_ID" VARCHAR, "AS_OF" DATE DEFAULT null, "LOOKBACK_DAYS" NUMBER(38,0) DEFAULT 21)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
import uuid

CHECKS = {}

CHECKS["NULL_VALUES"] = """
SELECT ''NULL_VALUES'' check_type, metric, MIN(obs_date) obs_date,
       IFF(COUNT(*) >= 5, ''HIGH'', ''MEDIUM'') severity, COUNT(DISTINCT entity_id) affected_count,
       COUNT(*) observed, 0 expected,
       ''Entity '' || entity_id || '' has '' || COUNT(*) || '' NULL '' || metric || '' values between '' || MIN(obs_date) || '' and '' || MAX(obs_date) summary,
       OBJECT_CONSTRUCT(''entity_id'', entity_id, ''date_from'', MIN(obs_date), ''date_to'', MAX(obs_date)) details
FROM obs WHERE value IS NULL
GROUP BY metric, entity_id
"""

CHECKS["DUPLICATE"] = """
SELECT ''DUPLICATE'', metric, MIN(obs_date),
       IFF(SUM(IFF(n_distinct_values > 1, 1, 0)) > 0, ''HIGH'', ''MEDIUM''), 1,
       SUM(n - 1), 0,
       ''Entity '' || entity_id || '' has '' || COUNT(*) || '' duplicated '' || metric || '' keys ('' ||
         SUM(IFF(n_distinct_values > 1, 1, 0)) || '' with conflicting values) between '' || MIN(obs_date) || '' and '' || MAX(obs_date),
       OBJECT_CONSTRUCT(''entity_id'', entity_id, ''date_from'', MIN(obs_date), ''date_to'', MAX(obs_date),
                        ''conflicting_keys'', SUM(IFF(n_distinct_values > 1, 1, 0)))
FROM (SELECT entity_id, metric, obs_date, COUNT(*) n, COUNT(DISTINCT value) n_distinct_values
      FROM obs GROUP BY 1,2,3 HAVING COUNT(*) > 1)
GROUP BY metric, entity_id
"""

# Active = reported on >= 50% of days in the first 14 days of the window; stale = last report older than stale_days.
# Flags regions whose stale rate is materially above the overall rate.
CHECKS["STALE"] = """
WITH act AS (
  SELECT entity_id, COUNT(DISTINCT obs_date) d14 FROM obs
  WHERE obs_date < DATEADD(day, 14, ''{ws}''::DATE) GROUP BY 1 HAVING d14 >= 7),
last AS (SELECT o.entity_id, MAX(o.obs_date) last_date FROM obs o JOIN act USING (entity_id) GROUP BY 1),
lab AS (SELECT l.*, COALESCE(e.segment, ''UNKNOWN'') region, (last_date < DATEADD(day, -{stale_days}, ''{asof}''::DATE)) is_stale
        FROM last l LEFT JOIN {ent} e USING (entity_id)),
overall AS (SELECT AVG(IFF(is_stale,1,0)) overall_rate FROM lab),
reg AS (
  SELECT region, COUNT(*) n_active, COUNT_IF(is_stale) n_stale, n_stale / n_active rate,
         MODE(IFF(is_stale, last_date, NULL)) modal_last_date,
         ARRAY_SLICE(ARRAY_AGG(IFF(is_stale, entity_id, NULL)) WITHIN GROUP (ORDER BY entity_id), 0, 40) stale_entities
  FROM lab GROUP BY region)
SELECT ''STALE'', ''ALL'', modal_last_date,
       IFF(rate >= 0.5, ''HIGH'', ''MEDIUM''), n_stale, ROUND(rate, 3), ROUND(overall_rate, 3),
       region || '': '' || n_stale || '' of '' || n_active || '' active entities ('' || ROUND(rate*100) || ''%) have not reported since ~'' ||
         modal_last_date || '' (overall stale rate '' || ROUND(overall_rate*100, 1) || ''%)'',
       OBJECT_CONSTRUCT(''segment'', region, ''n_active'', n_active, ''n_stale'', n_stale, ''modal_last_date'', modal_last_date,
                        ''overall_rate'', overall_rate, ''stale_entities_sample'', stale_entities)
FROM reg, overall
WHERE n_stale >= 3 AND rate >= GREATEST(0.5, 2 * overall_rate)
"""

# Daily row volume per metric vs median of the 28 days before the window (excludes the last 3 days for reporting latency)
CHECKS["VOLUME_DROP"] = """
WITH d AS (
  SELECT metric, obs_date, COUNT(*) n FROM {obs}
  WHERE obs_date BETWEEN DATEADD(day, -28, ''{ws}''::DATE) AND DATEADD(day, -3, ''{asof}''::DATE) GROUP BY 1,2),
exp AS (SELECT metric, MEDIAN(n) e FROM d WHERE obs_date < ''{ws}'' GROUP BY 1),
low AS (SELECT d.*, exp.e FROM d JOIN exp USING (metric) WHERE obs_date >= ''{ws}'' AND n < exp.e * (1 - {drop_pct}))
SELECT ''VOLUME_DROP'', metric, MIN(obs_date), IFF(MIN(n / e) < 0.5, ''HIGH'', ''MEDIUM''), COUNT(*),
       MIN(n), ANY_VALUE(e),
       metric || '': '' || COUNT(*) || '' day(s) with row volume below '' || ROUND((1-{drop_pct})*100) || ''% of baseline (min '' || MIN(n) || '' vs expected ~'' || ANY_VALUE(e) || '')'',
       OBJECT_CONSTRUCT(''days'', ARRAY_AGG(OBJECT_CONSTRUCT(''date'', obs_date, ''rows'', n)) WITHIN GROUP (ORDER BY obs_date))
FROM low GROUP BY metric
"""

# Out-of-bounds values for all metrics; robust z vs monthly baseline for non-zero-inflated metrics
CHECKS["OUTLIER"] = """
WITH s AS (
  SELECT o.entity_id, o.metric, o.obs_date, o.value, b.median_value, b.p01, b.p99,
         GREATEST((b.p75 - b.p25) / 1.349, (b.p99 - b.p01) / 8, 0.5) scale,
         (o.value - b.median_value) / scale z,
         (o.value < mb.min_value OR o.value > mb.max_value) oob
  FROM obs o
  LEFT JOIN DATA_DETECTIVE.CORE.BASELINES b
    ON b.dataset_id = ''{base_ds}'' AND b.entity_id = o.entity_id AND b.metric = o.metric AND b.month_of_year = MONTH(o.obs_date)
  LEFT JOIN DATA_DETECTIVE.CORE.METRIC_BOUNDS mb ON mb.metric = o.metric
  WHERE o.value IS NOT NULL),
f AS (
  SELECT * FROM s
  WHERE COALESCE(oob, FALSE)
     OR (metric IN (''minimum_temperature'',''maximum_temperature'',''average_daily_wind_speed'') AND ABS(z) > {z} AND (value > p99 OR value < p01))),
g AS (
  SELECT metric, entity_id, COUNT(*) n, MIN(obs_date) d0, MAX(obs_date) d1, MAX(ABS(z)) max_z, COUNT_IF(oob) n_oob,
         ANY_VALUE(median_value) med,
         ARRAY_AGG(OBJECT_CONSTRUCT(''date'', obs_date, ''value'', value, ''z'', ROUND(z,1))) WITHIN GROUP (ORDER BY obs_date) pts
  FROM f GROUP BY 1,2)
SELECT ''OUTLIER'', metric, d0, IFF(n >= 3 OR n_oob > 0, ''HIGH'', ''MEDIUM''), 1, ROUND(max_z, 1), med,
       ''Entity '' || entity_id || '': '' || n || '' unusual '' || metric || '' value(s) '' || d0 || ''..'' || d1 ||
         '' (max |z| '' || ROUND(max_z,1) || '', baseline median '' || ROUND(med,1) || '')'',
       OBJECT_CONSTRUCT(''entity_id'', entity_id, ''date_from'', d0, ''date_to'', d1, ''n_points'', n, ''n_out_of_bounds'', n_oob,
                        ''points'', ARRAY_SLICE(pts, 0, 15))
FROM g
QUALIFY ROW_NUMBER() OVER (ORDER BY n_oob DESC, max_z * LEAST(n, 5) DESC) <= 25
"""

# Runs of >= 6 identical consecutive non-zero readings on continuous metrics (stuck sensor)
CHECKS["FLATLINE"] = """
WITH r AS (
  SELECT entity_id, metric, obs_date, value,
         ROW_NUMBER() OVER (PARTITION BY entity_id, metric ORDER BY obs_date)
       - ROW_NUMBER() OVER (PARTITION BY entity_id, metric, value ORDER BY obs_date) grp
  FROM obs
  WHERE metric IN (''minimum_temperature'',''maximum_temperature'',''average_daily_wind_speed'')
    AND value IS NOT NULL AND value <> 0),
runs AS (SELECT entity_id, metric, value, MIN(obs_date) d0, MAX(obs_date) d1, COUNT(*) n
         FROM r GROUP BY entity_id, metric, value, grp HAVING COUNT(*) >= 6)
SELECT ''FLATLINE'', metric, d0, IFF(n >= 8, ''HIGH'', ''MEDIUM''), 1, n, 1,
       ''Entity '' || entity_id || '' reported constant '' || metric || '' = '' || value || '' for '' || n || '' consecutive readings '' || d0 || ''..'' || d1,
       OBJECT_CONSTRUCT(''entity_id'', entity_id, ''date_from'', d0, ''date_to'', d1, ''value'', value, ''run_length'', n)
FROM runs
QUALIFY ROW_NUMBER() OVER (ORDER BY n DESC) <= 25
"""

def run(session, dataset_id, as_of, lookback_days):
    reg = session.sql("SELECT * FROM DATA_DETECTIVE.CORE.DATASET_REGISTRY WHERE dataset_id = ?", [dataset_id]).collect()
    if not reg:
        return f"Unknown dataset {dataset_id}"
    r = reg[0]
    obs_view, ent_view = r["OBS_VIEW"], r["ENTITY_VIEW"]
    if as_of is None:
        as_of = session.sql(f"SELECT MAX(obs_date) d FROM {obs_view}").collect()[0]["D"]
    lookback = int(lookback_days or 21)
    ws = session.sql(f"SELECT DATEADD(day, -{lookback}, ''{as_of}''::DATE) d").collect()[0]["D"]
    run_id = str(uuid.uuid4())
    session.sql("INSERT INTO DATA_DETECTIVE.CORE.CHECK_RUNS (run_id, dataset_id, as_of_date, window_start, started_at) "
                "VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP())", [run_id, dataset_id, as_of, ws]).collect()
    fmt = dict(obs=obs_view, ent=ent_view, ws=ws, asof=as_of, stale_days=int(r["STALE_DAYS"]),
               drop_pct=float(r["MISSING_DROP_PCT"]), z=float(r["OUTLIER_Z"]), base_ds=r["BASELINE_DATASET"])
    prefix = f"WITH obs AS (SELECT * FROM {obs_view} WHERE obs_date BETWEEN ''{ws}'' AND ''{as_of}'') "
    for name, sql in CHECKS.items():
        body = sql.format(**fmt).strip()
        # Checks that start with their own CTE get the obs CTE merged in
        q = prefix + ", " + body[len("WITH "):] if body.startswith("WITH ") else prefix + body
        if name == "VOLUME_DROP":
            q = body
        session.sql(f"""
            INSERT INTO DATA_DETECTIVE.CORE.CHECK_RESULTS
            SELECT UUID_STRING(), ''{run_id}'', ''{dataset_id}'', c.*, CURRENT_TIMESTAMP() FROM ({q}) c
        """).collect()
    n = session.sql("SELECT COUNT(*) c FROM DATA_DETECTIVE.CORE.CHECK_RESULTS WHERE run_id = ?", [run_id]).collect()[0]["C"]
    session.sql("UPDATE DATA_DETECTIVE.CORE.CHECK_RUNS SET finished_at = CURRENT_TIMESTAMP(), n_findings = ? WHERE run_id = ?",
                [n, run_id]).collect()
    return run_id
';
create or replace task DATA_DETECTIVE.CORE.DAILY_CHECKS
	warehouse=DEFAULT_WH
	schedule='USING CRON 0 7 * * * America/Los_Angeles'
	as EXECUTE IMMEDIATE $$
BEGIN
  IF (DAYOFWEEK(CURRENT_DATE()) = 1) THEN
    CALL DATA_DETECTIVE.CORE.BUILD_BASELINES('NOAA_DAILY');
  END IF;
  CALL DATA_DETECTIVE.CORE.RUN_CHECKS('NOAA_DAILY', NULL, 21);
END;
$$;
create or replace streamlit DATA_DETECTIVE.CORE.DATA_DETECTIVE_APP
	from '@DATA_DETECTIVE.CORE.APP_STAGE/app'
	main_file='streamlit_app.py'
	query_warehouse='DEFAULT_WH'
	title='Data Detective';
create or replace schema DATA_DETECTIVE.PUBLIC;
