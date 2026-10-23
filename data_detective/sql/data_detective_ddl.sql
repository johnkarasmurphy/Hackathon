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
	UNIT VARCHAR(16777216),
	CONTINUOUS BOOLEAN
);
create or replace TABLE DATA_DETECTIVE.CORE.WFR_CONFIG (
	CONFIG_ID VARCHAR(16777216) NOT NULL,
	STATUS VARCHAR(16777216),
	PARAMS VARIANT,
	CREATED_AT TIMESTAMP_LTZ(9),
	primary key (CONFIG_ID)
);
create or replace TABLE DATA_DETECTIVE.CORE.WFR_SCORES (
	CONFIG_ID VARCHAR(16777216),
	ZONE_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	DRYNESS_RH FLOAT,
	WIND_MPH FLOAT,
	HEAT_F FLOAT,
	ALERT_VALUE FLOAT,
	N_FIRES_ALL NUMBER(38,0),
	N_FIRES_SEASON NUMBER(38,0),
	P_DRYNESS FLOAT,
	P_WIND FLOAT,
	P_HEAT FLOAT,
	P_ALERT FLOAT,
	P_HIST_ALL FLOAT,
	P_HIST_SEASON FLOAT,
	N_REF_DAYS NUMBER(38,0),
	N_STATIONS NUMBER(38,0),
	MISSING_INPUTS ARRAY,
	ALERT_TYPES ARRAY,
	SCORE FLOAT,
	BAND VARCHAR(16777216),
	SCORED_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.CORE.WFR_STATION_DAY cluster by (local_day)(
	STATION_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	MIN_RH FLOAT,
	MAX_WIND_MPH FLOAT,
	MAX_TEMP_F FLOAT,
	N_HOURS NUMBER(38,0),
	N_RH NUMBER(38,0),
	N_WIND NUMBER(38,0),
	N_TEMP NUMBER(38,0),
	BUILT_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY (
	ZONE_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	ALERT_VALUE FLOAT,
	ALERT_TYPES ARRAY
);
create or replace TABLE DATA_DETECTIVE.CORE.WFR_ZONE_DAY (
	ZONE_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	DRYNESS_RH FLOAT,
	WIND_MPH FLOAT,
	HEAT_F FLOAT,
	N_STATIONS NUMBER(38,0),
	N_RH NUMBER(38,0),
	N_WIND NUMBER(38,0),
	N_TEMP NUMBER(38,0)
);
create or replace TABLE DATA_DETECTIVE.CORE.WFR_ZONE_HISTORY (
	ZONE_ID VARCHAR(16777216),
	MONTH_OF_YEAR NUMBER(38,0),
	N_FIRES_ALL NUMBER(38,0),
	N_FIRES_SEASON NUMBER(38,0),
	HIST_ALL FLOAT,
	HIST_SEASON FLOAT
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
create or replace view DATA_DETECTIVE.CORE.V_NWS_CA_ENTITIES(
	ENTITY_ID,
	ENTITY_NAME,
	REGION,
	COUNTRY_NAME,
	LATITUDE,
	LONGITUDE,
	ELEVATION,
	NETWORK,
	SEGMENT,
	COUNTY_GEO_ID
) as
SELECT station_id AS entity_id, station_name AS entity_name, zone_id AS region, 'United States' AS country_name,
       latitude, longitude, elevation, 'NWS' AS network, zone_id AS segment, county_geo_id
FROM V_WFR_STATIONS;
create or replace view DATA_DETECTIVE.CORE.V_NWS_CA_OBS(
	ENTITY_ID,
	METRIC,
	OBS_DATE,
	VALUE,
	UNIT
) as
WITH u AS (
  SELECT station_id AS entity_id, LOWER(metric) AS metric, local_day AS obs_date, value
  FROM WFR_STATION_DAY
  UNPIVOT INCLUDE NULLS (value FOR metric IN (min_rh, max_wind_mph, max_temp_f))),

reports AS (SELECT DISTINCT entity_id, metric FROM BASELINES WHERE dataset_id = 'NWS_CA_DAILY' AND n_obs >= 20)
SELECT u.entity_id, u.metric, u.obs_date, u.value,
       DECODE(u.metric, 'min_rh', 'Percent', 'max_wind_mph', 'Miles per hour', 'Degrees Fahrenheit') AS unit
FROM u
WHERE u.value IS NOT NULL
   OR EXISTS (SELECT 1 FROM reports r WHERE r.entity_id = u.entity_id AND r.metric = u.metric);
create or replace view DATA_DETECTIVE.CORE.V_WFR_COUNTY(
	CONFIG_ID,
	COUNTY_GEO_ID,
	LOCAL_DAY,
	SCORE,
	BAND,
	DRIVING_ZONE,
	N_ZONES
) as
SELECT s.config_id, zc.county_geo_id, s.local_day, MAX(s.score) score,
       MAX_BY(s.band, s.score) band, MAX_BY(s.zone_id, s.score) driving_zone, COUNT(*) n_zones
FROM WFR_SCORES s JOIN V_WFR_ZONE_COUNTY zc ON zc.zone_id = s.zone_id
GROUP BY 1, 2, 3;
create or replace view DATA_DETECTIVE.CORE.V_WFR_SCORES_TRUST(
	CONFIG_ID,
	ZONE_ID,
	LOCAL_DAY,
	DRYNESS_RH,
	WIND_MPH,
	HEAT_F,
	ALERT_VALUE,
	N_FIRES_ALL,
	N_FIRES_SEASON,
	P_DRYNESS,
	P_WIND,
	P_HEAT,
	P_ALERT,
	P_HIST_ALL,
	P_HIST_SEASON,
	N_REF_DAYS,
	N_STATIONS,
	MISSING_INPUTS,
	ALERT_TYPES,
	SCORE,
	BAND,
	SCORED_AT,
	N_DQ_FINDINGS,
	FINDING_IDS,
	TRUST_REASONS,
	SHARE_BAD_STATIONS,
	N_BAD_STATIONS,
	INPUT_TRUST
) as
WITH last_run AS (
  SELECT run_id FROM CHECK_RUNS WHERE dataset_id = 'NWS_CA_DAILY' AND finished_at IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (ORDER BY started_at DESC) = 1),
f AS (
  SELECT r.result_id, r.check_type, r.severity, r.metric, r.summary, st.station_id,
         COALESCE(st.zone_id, r.details:segment::STRING) zone_id,
         COALESCE(r.details:date_from::DATE, DATEADD(day, 1, r.details:modal_last_date::DATE)) d0,
         COALESCE(r.details:date_to::DATE, cr.as_of_date) d1
  FROM CHECK_RESULTS r JOIN last_run lr ON lr.run_id = r.run_id
  JOIN CHECK_RUNS cr ON cr.run_id = r.run_id
  LEFT JOIN V_WFR_STATIONS st ON st.station_id = r.details:entity_id::STRING
  WHERE r.check_type IN ('NULL_VALUES', 'DUPLICATE', 'OUTLIER', 'FLATLINE', 'STALE')),
zf AS (
  SELECT s.zone_id, s.local_day, COUNT(f.result_id) n_findings, COUNT(DISTINCT f.station_id) n_bad_stations,
         MAX(IFF(f.check_type = 'STALE', 1, 0)) zone_stale,
         ARRAY_AGG(DISTINCT f.check_type || ' ' || f.metric) WITHIN GROUP (ORDER BY f.check_type || ' ' || f.metric) finding_types,
         ARRAY_AGG(f.result_id) finding_ids
  FROM WFR_SCORES s JOIN f ON f.zone_id = s.zone_id AND s.local_day BETWEEN f.d0 AND f.d1
  WHERE s.config_id = 'wfr-v4a'
  GROUP BY 1, 2)
SELECT s.*, COALESCE(zf.n_findings, 0) n_dq_findings, zf.finding_ids,
       ARRAY_CAT(
         ARRAY_CONSTRUCT_COMPACT(
           IFF(s.n_stations = 0, 'no reporting stations (weather factors defaulted to 0.5)', NULL),
           IFF(ARRAY_SIZE(s.missing_inputs) > 0 AND s.n_stations > 0, 'missing inputs: ' || ARRAY_TO_STRING(s.missing_inputs, ', '), NULL),
           IFF(s.n_stations BETWEEN 1 AND 2, 'only ' || s.n_stations || ' reporting station(s)', NULL)),
         COALESCE(TRANSFORM(zf.finding_types, x -> 'data-quality finding: ' || x::STRING), [])) trust_reasons,
       ROUND(COALESCE(zf.n_bad_stations, 0) / NULLIF(s.n_stations, 0), 2) share_bad_stations,
       COALESCE(zf.n_bad_stations, 0) n_bad_stations,

       CASE WHEN s.n_stations = 0 OR ARRAY_SIZE(s.missing_inputs) >= 2 OR COALESCE(zf.zone_stale, 0) = 1
                 OR COALESCE(zf.n_bad_stations, 0) >= GREATEST(1, 0.5 * s.n_stations) THEN 'UNRELIABLE'
            WHEN ARRAY_SIZE(s.missing_inputs) > 0 OR s.n_stations <= 2
                 OR COALESCE(zf.n_bad_stations, 0) >= GREATEST(1, 0.2 * s.n_stations) THEN 'DEGRADED'
            ELSE 'OK' END input_trust
FROM WFR_SCORES s LEFT JOIN zf ON zf.zone_id = s.zone_id AND zf.local_day = s.local_day
WHERE s.config_id = 'wfr-v4a';
create or replace view DATA_DETECTIVE.CORE.V_WFR_SCORE_OBS(
	ENTITY_ID,
	METRIC,
	OBS_DATE,
	VALUE,
	UNIT
) as
SELECT zone_id AS entity_id, 'wfr_score' AS metric, local_day AS obs_date, score AS value, 'Score 0-100' AS unit
FROM WFR_SCORES WHERE config_id = 'wfr-v4a';
create or replace view DATA_DETECTIVE.CORE.V_WFR_STATIONS(
	STATION_ID,
	STATION_NAME,
	ZONE_ID,
	COUNTY_GEO_ID,
	LATITUDE,
	LONGITUDE,
	ELEVATION
) as
SELECT nws_weather_station_id AS station_id, nws_weather_station_name AS station_name,
       fire_weather_zone_id AS zone_id, county_geo_id, latitude, longitude, elevation
FROM SNOWFLAKE_CURATED_DATA_CORE_WEATHER_DATA.PUBLIC_DATA.NWS_WEATHER_STATION_INDEX
WHERE state_geo_id = 'geoId/06' AND fire_weather_zone_id IS NOT NULL;
create or replace view DATA_DETECTIVE.CORE.V_WFR_ZONES(
	ZONE_ID,
	LATITUDE,
	LONGITUDE,
	N_STATIONS_INDEXED,
	COUNTIES,
	ZONE_NAME
) as
SELECT s.zone_id, AVG(s.latitude) latitude, AVG(s.longitude) longitude, COUNT(*) n_stations_indexed,
       ARRAY_AGG(DISTINCT s.county_geo_id) counties,
       ANY_VALUE(z.nws_weather_zone_name) zone_name
FROM V_WFR_STATIONS s
LEFT JOIN SNOWFLAKE_CURATED_DATA_CORE_WEATHER_DATA.PUBLIC_DATA.NWS_WEATHER_ZONE_INDEX z
  ON z.nws_weather_zone_id = s.zone_id
GROUP BY s.zone_id;
create or replace view DATA_DETECTIVE.CORE.V_WFR_ZONE_COUNTY(
	ZONE_ID,
	COUNTY_GEO_ID
) as
SELECT DISTINCT zone_id, county_geo_id FROM V_WFR_STATIONS WHERE county_geo_id IS NOT NULL;
create or replace view DATA_DETECTIVE.CORE.V_WFR_ZONE_ENTITIES(
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
SELECT zone_id AS entity_id, COALESCE(zone_name, zone_id) AS entity_name, zone_id AS region, 'United States' AS country_name,
       latitude, longitude, NULL::FLOAT AS elevation, 'NWS fire weather zone' AS network, zone_id AS segment
FROM V_WFR_ZONES;
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
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.CREATE_WFR_REVIEW("ZONE_ID" VARCHAR, "LOCAL_DAY" DATE)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  rid STRING DEFAULT UUID_STRING();
  fid STRING DEFAULT UUID_STRING();
BEGIN
  INSERT INTO DATA_DETECTIVE.CORE.CHECK_RUNS (run_id, dataset_id, as_of_date, window_start, started_at, finished_at, n_findings)
    VALUES (:rid, ''WFR_V4A'', :LOCAL_DAY, DATEADD(day, -14, :LOCAL_DAY), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 1);
  INSERT INTO DATA_DETECTIVE.CORE.CHECK_RESULTS
  SELECT :fid, :rid, ''WFR_V4A'', ''SCORE_REVIEW'', ''wfr_score'', t.local_day, ''MEDIUM'', 1, t.score, NULL,
         ''User review of zone '' || t.zone_id || '' wildfire score '' || ROUND(t.score, 1) || '' ('' || t.band || '') on '' || t.local_day ||
           ''. Explain what drives this score, whether it is trustworthy (input trust: '' || t.input_trust || ''), and how it changed over the prior 14 days.'',
         OBJECT_CONSTRUCT(''entity_id'', t.zone_id, ''date_from'', DATEADD(day, -14, t.local_day), ''date_to'', t.local_day,
                          ''input_trust'', t.input_trust, ''trust_reasons'', t.trust_reasons),
         CURRENT_TIMESTAMP()
  FROM DATA_DETECTIVE.CORE.V_WFR_SCORES_TRUST t WHERE t.zone_id = :ZONE_ID AND t.local_day = :LOCAL_DAY;
  RETURN fid;
END;
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
                                "DATA_DETECTIVE.CORE.METRIC_BOUNDS", "DATA_DETECTIVE.CORE.WFR_SCORES",
                                "DATA_DETECTIVE.CORE.WFR_STATION_DAY", "DATA_DETECTIVE.CORE.V_WFR_STATIONS",
                                "DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY"}

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
          "zone_score_breakdown": {"args": {"zone_id": "str (e.g. CAZ264)", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "wfr-v4a wildfire score per day for a fire weather zone: raw inputs (zone median min RH %, wind mph, max temp F, alert), factor percentiles, weighted contribution of each factor in score points, band, n reporting stations, missing inputs, active alerts. Use to explain score jumps."},
          "zone_station_inputs": {"args": {"zone_id": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "Per station and day in a fire weather zone: min RH, max wind mph, max temp F, hours reported. Reveals whether a zone median was driven by one bad/stuck/missing station versus a zone-wide weather change."},
          "nearby_zone_scores": {"args": {"zone_id": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD", "radius_km": "number (default 100)"}, "desc": "Per day: the target zone''s wildfire score and alert vs the median score and the number of nearby fire weather zones (centroid distance) under Red Flag Warning/Fire Weather Watch. Distinguishes a regional fire-weather event from a zone-specific artifact."},
          "run_sql": {"args": {"sql": "a single read-only SELECT/WITH query"}, "desc": f"Free-form read-only SQL. Only these objects may be referenced: {sorted(self.allowed_objects)}. Columns of obs view: entity_id, metric, obs_date, value, unit. Entity view: entity_id, entity_name, region, country_name, latitude, longitude, elevation, network, segment. WFR_SCORES: config_id, zone_id, local_day, dryness_rh, wind_mph, heat_f, alert_value, n_fires_all, n_fires_season, p_dryness, p_wind, p_heat, p_alert, p_hist_all, p_hist_season, n_ref_days, n_stations, missing_inputs, alert_types, score, band. WFR_STATION_DAY: station_id, local_day, min_rh, max_wind_mph, max_temp_f, n_hours, n_rh, n_wind, n_temp. V_WFR_STATIONS: station_id, station_name, zone_id, county_geo_id, latitude, longitude, elevation. WFR_ZONE_ALERT_DAY: zone_id, local_day, alert_value, alert_types. Results capped at {ROW_LIMIT} rows."},
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
        if tool == "zone_score_breakdown":
            z = self._id(a.get("zone_id"), "zone_id")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = """SELECT local_day, score, band, n_stations, missing_inputs, alert_types,
                        ROUND(dryness_rh, 1) min_rh_pct, ROUND(wind_mph, 1) wind_mph, ROUND(heat_f, 1) max_temp_f,
                        ROUND(p_dryness, 2) p_dry, ROUND(p_wind, 2) p_wind, ROUND(p_heat, 2) p_heat, p_alert,
                        ROUND(p_hist_all, 2) p_hist_all, ROUND(p_hist_season, 2) p_hist_season,
                        ROUND(100 * p_dryness / 8, 1) pts_dry, ROUND(100 * p_wind / 8, 1) pts_wind, ROUND(100 * p_heat / 8, 1) pts_heat,
                        ROUND(100 * p_alert / 8, 1) pts_alert, ROUND(100 * p_hist_all / 8, 1) pts_hist_all,
                        ROUND(300 * p_hist_season / 8, 1) pts_hist_season
                      FROM DATA_DETECTIVE.CORE.WFR_SCORES
                      WHERE config_id = ''wfr-v4a'' AND zone_id = ? AND local_day BETWEEN ? AND ? ORDER BY local_day"""
            return sql, [z, d0, d1]
        if tool == "zone_station_inputs":
            z = self._id(a.get("zone_id"), "zone_id")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = """SELECT d.local_day, d.station_id, s.station_name, ROUND(d.min_rh, 1) min_rh, ROUND(d.max_wind_mph, 1) max_wind_mph,
                        ROUND(d.max_temp_f, 1) max_temp_f, d.n_hours
                      FROM DATA_DETECTIVE.CORE.WFR_STATION_DAY d JOIN DATA_DETECTIVE.CORE.V_WFR_STATIONS s ON s.station_id = d.station_id
                      WHERE s.zone_id = ? AND d.local_day BETWEEN ? AND ? ORDER BY d.local_day, d.station_id LIMIT 200"""
            return sql, [z, d0, d1]
        if tool == "nearby_zone_scores":
            z = self._id(a.get("zone_id"), "zone_id")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            radius = max(10.0, min(float(a.get("radius_km") or 100), 400.0))
            sql = """WITH c AS (SELECT zone_id, AVG(latitude) lat, AVG(longitude) lon FROM DATA_DETECTIVE.CORE.V_WFR_STATIONS GROUP BY 1),
                      nb AS (SELECT o.zone_id FROM c t JOIN c o ON o.zone_id <> t.zone_id
                             WHERE t.zone_id = ? AND HAVERSINE(t.lat, t.lon, o.lat, o.lon) <= ?)
                      SELECT s.local_day,
                             MAX(IFF(s.zone_id = ?, s.score, NULL)) target_score, MAX(IFF(s.zone_id = ?, s.band, NULL)) target_band,
                             MAX(IFF(s.zone_id = ?, s.alert_value, NULL)) target_alert,
                             MEDIAN(IFF(s.zone_id <> ?, s.score, NULL)) neighbor_median_score,
                             COUNT_IF(s.zone_id <> ? AND s.alert_value >= 1) neighbors_rfw, COUNT_IF(s.zone_id <> ? AND s.alert_value = 0.5) neighbors_fww,
                             COUNT_IF(s.zone_id <> ?) n_neighbors
                      FROM DATA_DETECTIVE.CORE.WFR_SCORES s
                      WHERE s.config_id = ''wfr-v4a'' AND s.local_day BETWEEN ? AND ?
                        AND (s.zone_id = ? OR s.zone_id IN (SELECT zone_id FROM nb))
                      GROUP BY 1 ORDER BY 1"""
            return sql, [z, radius, z, z, z, z, z, z, z, d0, d1, z]
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
- For implausible magnitudes, explicitly test unit/scale hypotheses before concluding "sensor malfunction":
  check whether a simple transform (F->C via (v-32)*5/9, C->F, x10 / /10, km/h<->mph x1.609, mm<->in x25.4)
  maps the anomalous values onto the baseline or neighbor values. If it does, the finding is a unit/scale error.

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
     OR (metric IN (SELECT metric FROM DATA_DETECTIVE.CORE.METRIC_BOUNDS WHERE continuous) AND ABS(z) > {z} AND (value > p99 OR value < p01))),
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
  WHERE metric IN (SELECT metric FROM DATA_DETECTIVE.CORE.METRIC_BOUNDS WHERE continuous)
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
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.RUN_WFR_SCORE_CHECKS("AS_OF" DATE DEFAULT null, "LOOKBACK_DAYS" NUMBER(38,0) DEFAULT 14, "JUMP_POINTS" FLOAT DEFAULT 20)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  rid STRING DEFAULT UUID_STRING();
  asof DATE; ws DATE;
BEGIN
  asof := COALESCE(:AS_OF, (SELECT MAX(local_day) FROM DATA_DETECTIVE.CORE.WFR_SCORES WHERE config_id = ''wfr-v4a''));
  ws := DATEADD(day, -:LOOKBACK_DAYS, :asof);
  INSERT INTO DATA_DETECTIVE.CORE.CHECK_RUNS (run_id, dataset_id, as_of_date, window_start, started_at)
    VALUES (:rid, ''WFR_V4A'', :asof, :ws, CURRENT_TIMESTAMP());

  INSERT INTO DATA_DETECTIVE.CORE.CHECK_RESULTS
  WITH s AS (
    SELECT zone_id, local_day, score, band, p_dryness, p_wind, p_heat, p_alert,
           LAG(score) OVER (PARTITION BY zone_id ORDER BY local_day) prev_score,
           LAG(band) OVER (PARTITION BY zone_id ORDER BY local_day) prev_band,
           LAG(p_dryness) OVER (PARTITION BY zone_id ORDER BY local_day) prev_dry,
           LAG(p_wind) OVER (PARTITION BY zone_id ORDER BY local_day) prev_wind,
           LAG(p_heat) OVER (PARTITION BY zone_id ORDER BY local_day) prev_heat,
           LAG(p_alert) OVER (PARTITION BY zone_id ORDER BY local_day) prev_alert
    FROM DATA_DETECTIVE.CORE.WFR_SCORES
    WHERE config_id = ''wfr-v4a'' AND local_day BETWEEN DATEADD(day, -1, :ws) AND :asof)
  SELECT UUID_STRING(), :rid, ''WFR_V4A'', ''SCORE_JUMP'', ''wfr_score'', local_day,
         IFF(ABS(score - prev_score) >= 1.5 * :JUMP_POINTS, ''HIGH'', ''MEDIUM''), 1, score, prev_score,
         ''Zone '' || zone_id || '' wildfire score '' || IFF(score > prev_score, ''jumped'', ''dropped'') || '' '' ||
           ROUND(prev_score, 1) || '' -> '' || ROUND(score, 1) || '' ('' || prev_band || '' -> '' || band || '') on '' || local_day,
         OBJECT_CONSTRUCT(''entity_id'', zone_id, ''date_from'', DATEADD(day, -1, local_day), ''date_to'', local_day,
           ''factor_deltas'', OBJECT_CONSTRUCT(''dryness'', ROUND(p_dryness - prev_dry, 2), ''wind'', ROUND(p_wind - prev_wind, 2),
                                             ''heat'', ROUND(p_heat - prev_heat, 2), ''alert'', ROUND(p_alert - prev_alert, 2))),
         CURRENT_TIMESTAMP()
  FROM s
  WHERE local_day >= :ws AND prev_score IS NOT NULL AND ABS(score - prev_score) >= :JUMP_POINTS
  UNION ALL
  SELECT UUID_STRING(), :rid, ''WFR_V4A'', ''DEGRADED_HIGH_SCORE'', ''wfr_score'', t.local_day, ''HIGH'', 1, t.score, NULL,
         ''Zone '' || t.zone_id || '' scored '' || t.band || '' ('' || ROUND(t.score, 1) || '') on '' || t.local_day ||
           '' but input trust is '' || t.input_trust || '': '' || ARRAY_TO_STRING(t.trust_reasons, ''; ''),
         OBJECT_CONSTRUCT(''entity_id'', t.zone_id, ''date_from'', t.local_day, ''date_to'', t.local_day,
                          ''trust_reasons'', t.trust_reasons, ''missing_inputs'', t.missing_inputs),
         CURRENT_TIMESTAMP()
  FROM DATA_DETECTIVE.CORE.V_WFR_SCORES_TRUST t
  WHERE t.local_day BETWEEN :ws AND :asof AND t.band IN (''High'', ''Very High'', ''Extreme'') AND t.input_trust <> ''OK''
  UNION ALL
  -- Red Flag Warning / Fire Weather Watch in a zone while no zone within 100 km has any alert that day
  SELECT UUID_STRING(), :rid, ''WFR_V4A'', ''ISOLATED_ALERT'', ''alert'', a.local_day, ''HIGH'', 1, a.alert_value, 0,
         ''Zone '' || a.zone_id || '' has '' || ARRAY_TO_STRING(a.alert_types, '', '') || '' on '' || a.local_day ||
           '' but none of '' || COUNT(nb.zone_id) || '' zones within 100 km has a fire-weather alert'',
         OBJECT_CONSTRUCT(''entity_id'', a.zone_id, ''date_from'', a.local_day, ''date_to'', a.local_day,
                          ''alert_types'', a.alert_types, ''n_neighbor_zones'', COUNT(nb.zone_id)),
         CURRENT_TIMESTAMP()
  FROM DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY a
  JOIN DATA_DETECTIVE.CORE.V_WFR_ZONES t ON t.zone_id = a.zone_id
  JOIN DATA_DETECTIVE.CORE.V_WFR_ZONES nb ON nb.zone_id <> a.zone_id
   AND HAVERSINE(t.latitude, t.longitude, nb.latitude, nb.longitude) <= 100
  LEFT JOIN DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY na ON na.zone_id = nb.zone_id AND na.local_day = a.local_day
  WHERE a.local_day BETWEEN :ws AND :asof
  GROUP BY a.zone_id, a.local_day, a.alert_value, a.alert_types
  HAVING COUNT(nb.zone_id) >= 2 AND COUNT(na.zone_id) = 0;

  UPDATE DATA_DETECTIVE.CORE.CHECK_RUNS SET finished_at = CURRENT_TIMESTAMP(),
    n_findings = (SELECT COUNT(*) FROM DATA_DETECTIVE.CORE.CHECK_RESULTS WHERE run_id = :rid) WHERE run_id = :rid;
  RETURN rid;
END;
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.SCORE_WILDFIRE_RISK("D_FROM" DATE, "D_TO" DATE, "CONFIG_ID" VARCHAR DEFAULT 'wfr-v4a')
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  ref_from DATE; ref_to DATE; wt FLOAT; miss FLOAT;
  w_dry FLOAT; w_wind FLOAT; w_heat FLOAT; w_alert FLOAT; w_ha FLOAT; w_hs FLOAT;
  b_mod FLOAT; b_high FLOAT; b_vh FLOAT; b_ext FLOAT;
BEGIN
  SELECT params:reference_period[0]::DATE, params:reference_period[1]::DATE, params:weight_total::FLOAT, params:missing_factor::FLOAT,
         params:weights:dryness::FLOAT, params:weights:wind::FLOAT, params:weights:heat::FLOAT, params:weights:alert::FLOAT,
         params:weights:hist_all::FLOAT, params:weights:hist_season::FLOAT,
         params:bands[1]:min::FLOAT, params:bands[2]:min::FLOAT, params:bands[3]:min::FLOAT, params:bands[4]:min::FLOAT
    INTO :ref_from, :ref_to, :wt, :miss, :w_dry, :w_wind, :w_heat, :w_alert, :w_ha, :w_hs, :b_mod, :b_high, :b_vh, :b_ext
    FROM DATA_DETECTIVE.CORE.WFR_CONFIG WHERE config_id = :CONFIG_ID;

  -- Zone-day = median across stations
  DELETE FROM DATA_DETECTIVE.CORE.WFR_ZONE_DAY
   WHERE local_day BETWEEN :ref_from AND :ref_to OR local_day BETWEEN :D_FROM AND :D_TO;
  INSERT INTO DATA_DETECTIVE.CORE.WFR_ZONE_DAY
  SELECT s.zone_id, d.local_day, MEDIAN(d.min_rh), MEDIAN(d.max_wind_mph), MEDIAN(d.max_temp_f),
         COUNT(DISTINCT d.station_id), COUNT(d.min_rh), COUNT(d.max_wind_mph), COUNT(d.max_temp_f)
  FROM DATA_DETECTIVE.CORE.WFR_STATION_DAY d JOIN DATA_DETECTIVE.CORE.V_WFR_STATIONS s ON s.station_id = d.station_id
  WHERE d.local_day BETWEEN :ref_from AND :ref_to OR d.local_day BETWEEN :D_FROM AND :D_TO
  GROUP BY 1, 2;

  DELETE FROM DATA_DETECTIVE.CORE.WFR_SCORES WHERE config_id = :CONFIG_ID AND local_day BETWEEN :D_FROM AND :D_TO;
  INSERT INTO DATA_DETECTIVE.CORE.WFR_SCORES
  WITH grid AS (
    SELECT z.zone_id, DATEADD(day, g.n, :D_FROM) local_day
    FROM (SELECT DISTINCT zone_id FROM DATA_DETECTIVE.CORE.V_WFR_STATIONS) z
    CROSS JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 n FROM TABLE(GENERATOR(ROWCOUNT => 1000))) g
    WHERE DATEADD(day, g.n, :D_FROM) <= :D_TO),
  cur AS (
    SELECT g.zone_id, g.local_day, zd.dryness_rh, zd.wind_mph, zd.heat_f, COALESCE(zd.n_stations, 0) n_stations
    FROM grid g LEFT JOIN DATA_DETECTIVE.CORE.WFR_ZONE_DAY zd ON zd.zone_id = g.zone_id AND zd.local_day = g.local_day),
  -- share of same-zone, same-month reference days less risky than the scored day (ties = 0.5)
  pct AS (
    SELECT c.zone_id, c.local_day,
           COUNT(r.local_day) n_ref,
           (COUNT_IF(r.dryness_rh > c.dryness_rh) + 0.5 * COUNT_IF(r.dryness_rh = c.dryness_rh)) / NULLIF(COUNT(r.dryness_rh), 0) p_dry,
           (COUNT_IF(r.wind_mph < c.wind_mph) + 0.5 * COUNT_IF(r.wind_mph = c.wind_mph)) / NULLIF(COUNT(r.wind_mph), 0) p_wind,
           (COUNT_IF(r.heat_f < c.heat_f) + 0.5 * COUNT_IF(r.heat_f = c.heat_f)) / NULLIF(COUNT(r.heat_f), 0) p_heat
    FROM cur c LEFT JOIN DATA_DETECTIVE.CORE.WFR_ZONE_DAY r
      ON r.zone_id = c.zone_id AND MONTH(r.local_day) = MONTH(c.local_day) AND r.local_day BETWEEN :ref_from AND :ref_to
    GROUP BY 1, 2),
  f AS (
    SELECT c.*, a.alert_value, a.alert_types, h.n_fires_all, h.n_fires_season, p.n_ref,
           IFF(c.dryness_rh IS NULL, :miss, COALESCE(p.p_dry, :miss)) p_dryness,
           IFF(c.wind_mph IS NULL, :miss, COALESCE(p.p_wind, :miss)) p_wind,
           IFF(c.heat_f IS NULL, :miss, COALESCE(p.p_heat, :miss)) p_heat,
           COALESCE(a.alert_value, 0) p_alert,
           COALESCE(h.hist_all, :miss) p_hist_all, COALESCE(h.hist_season, :miss) p_hist_season
    FROM cur c
    JOIN pct p ON p.zone_id = c.zone_id AND p.local_day = c.local_day
    LEFT JOIN DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY a ON a.zone_id = c.zone_id AND a.local_day = c.local_day
    LEFT JOIN DATA_DETECTIVE.CORE.WFR_ZONE_HISTORY h ON h.zone_id = c.zone_id AND h.month_of_year = MONTH(c.local_day)),
  s AS (
    SELECT f.*, ROUND(100 * (:w_dry * p_dryness + :w_wind * p_wind + :w_heat * p_heat
                 + :w_alert * p_alert + :w_ha * p_hist_all + :w_hs * p_hist_season) / :wt, 1) score
    FROM f)
  SELECT :CONFIG_ID, zone_id, local_day, dryness_rh, wind_mph, heat_f, COALESCE(alert_value, 0), n_fires_all, n_fires_season,
         p_dryness, p_wind, p_heat, p_alert, p_hist_all, p_hist_season, n_ref, n_stations,
         ARRAY_CONSTRUCT_COMPACT(IFF(dryness_rh IS NULL, ''dryness'', NULL), IFF(wind_mph IS NULL, ''wind'', NULL),
                                 IFF(heat_f IS NULL, ''heat'', NULL), IFF(n_ref = 0, ''reference_days'', NULL)),
         alert_types, score,
         CASE WHEN score >= :b_ext THEN ''Extreme'' WHEN score >= :b_vh THEN ''Very High'' WHEN score >= :b_high THEN ''High''
              WHEN score >= :b_mod THEN ''Moderate'' ELSE ''Low'' END,
         CURRENT_TIMESTAMP()
  FROM s;

  RETURN ''scored '' || (SELECT COUNT(*) FROM DATA_DETECTIVE.CORE.WFR_SCORES
                        WHERE config_id = :CONFIG_ID AND local_day BETWEEN :D_FROM AND :D_TO) || '' zone-days'';
END;
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.WFR_BUILD_STATIC("CONFIG_ID" VARCHAR DEFAULT 'wfr-v4a')
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  hist_from DATE; hist_to DATE; min_ac FLOAT; max_deg FLOAT;
BEGIN
  SELECT params:history_window[0]::DATE, params:history_window[1]::DATE, params:history_min_acres::FLOAT, params:fire_to_zone_max_deg::FLOAT
    INTO :hist_from, :hist_to, :min_ac, :max_deg
    FROM DATA_DETECTIVE.CORE.WFR_CONFIG WHERE config_id = :CONFIG_ID;

  -- RFW = 1.0, FWW = 0.5. Active from onset to end, truncated by a later Cancel for the same county + event type.
  TRUNCATE TABLE DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY;
  INSERT INTO DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY
  WITH a AS (
    SELECT county_geo_id, event_type, onset_timestamp start_ts, end_timestamp end_ts, alert_type, sent_timestamp
    FROM SNOWFLAKE_CURATED_DATA_CORE_WEATHER_DATA.PUBLIC_DATA.NWS_WEATHER_ALERT_EVENTS
    WHERE county_geo_id LIKE ''geoId/06%'' AND alert_status = ''Actual''
      AND event_type IN (''Red Flag Warning'', ''Fire Weather Watch'')),
  active AS (
    SELECT a.county_geo_id, a.event_type, a.start_ts,
           LEAST(a.end_ts, COALESCE(MIN(c.sent_timestamp), a.end_ts)) end_ts
    FROM a LEFT JOIN a c ON c.alert_type = ''Cancel'' AND c.county_geo_id = a.county_geo_id AND c.event_type = a.event_type
                        AND c.sent_timestamp > a.start_ts AND c.sent_timestamp < a.end_ts
    WHERE a.alert_type <> ''Cancel''
    GROUP BY 1, 2, 3, a.end_ts),
  days AS (
    SELECT act.county_geo_id, act.event_type,
           DATEADD(day, g.n, DATEADD(hour, -7, act.start_ts)::DATE) local_day
    FROM active act
    JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 n FROM TABLE(GENERATOR(ROWCOUNT => 15))) g
      ON DATEADD(day, g.n, DATEADD(hour, -7, act.start_ts)::DATE) <= DATEADD(hour, -7, act.end_ts)::DATE
    WHERE act.end_ts > act.start_ts)
  SELECT zc.zone_id, d.local_day,
         MAX(IFF(d.event_type = ''Red Flag Warning'', 1.0, 0.5)),
         ARRAY_AGG(DISTINCT d.event_type)
  FROM days d JOIN DATA_DETECTIVE.CORE.V_WFR_ZONE_COUNTY zc ON zc.county_geo_id = d.county_geo_id
  GROUP BY 1, 2;

  -- History fires (CA, WF, not deleted, dedupe IRWINID, >= 10 ac, discovered in history window) -> nearest CA station zone
  TRUNCATE TABLE DATA_DETECTIVE.CORE.WFR_ZONE_HISTORY;
  INSERT INTO DATA_DETECTIVE.CORE.WFR_ZONE_HISTORY
  WITH f AS (
    SELECT attr_irwinid,
           MAX(COALESCE(attr_finalacres, attr_incidentsize, TRY_TO_DOUBLE(poly_gisacres))) acres,
           MIN(DATEADD(hour, -7, TRY_TO_TIMESTAMP(attr_firediscoverydatetime, ''MM/DD/YYYY HH12:MI:SS AM'')))::DATE disc_day,
           ANY_VALUE(attr_initiallatitude) lat, ANY_VALUE(attr_initiallongitude) lon
    FROM DEFAULT_DATABASE.DEFAULT_SCHEMA.WFIGS_INTERAGENCY_PERIMETERS
    WHERE attr_poostate = ''US-CA'' AND attr_incidenttypecategory = ''WF'' AND NOT COALESCE(poly_deletethis, FALSE)
      AND attr_irwinid IS NOT NULL
    GROUP BY attr_irwinid),
  hist AS (
    SELECT * FROM f
    WHERE acres >= :min_ac AND disc_day BETWEEN :hist_from AND :hist_to AND lat IS NOT NULL AND lon IS NOT NULL),
  nearest AS (
    SELECT h.attr_irwinid, h.disc_day, s.zone_id
    FROM hist h JOIN DATA_DETECTIVE.CORE.V_WFR_STATIONS s
      ON s.latitude BETWEEN h.lat - :max_deg AND h.lat + :max_deg
     AND SQRT(POWER(s.latitude - h.lat, 2) + POWER((s.longitude - h.lon) * COS(RADIANS(h.lat)), 2)) <= :max_deg
    QUALIFY ROW_NUMBER() OVER (PARTITION BY h.attr_irwinid
              ORDER BY POWER(s.latitude - h.lat, 2) + POWER((s.longitude - h.lon) * COS(RADIANS(h.lat)), 2)) = 1),
  zones AS (SELECT DISTINCT zone_id FROM DATA_DETECTIVE.CORE.V_WFR_STATIONS),
  months AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) m FROM TABLE(GENERATOR(ROWCOUNT => 12))),
  cnt AS (
    SELECT z.zone_id, mo.m,
           COUNT(n.attr_irwinid) n_all,
           COUNT_IF(MOD(MONTH(n.disc_day) - mo.m + 12, 12) IN (0, 1, 11)) n_season
    FROM zones z CROSS JOIN months mo LEFT JOIN nearest n ON n.zone_id = z.zone_id
    GROUP BY z.zone_id, mo.m)
  -- percentile rank across zones, ties averaged: (n_less + (n_equal - 1) / 2) / (N - 1)
  SELECT zone_id, m, n_all, n_season,
         (RANK() OVER (PARTITION BY m ORDER BY n_all) - 1
           + (COUNT(*) OVER (PARTITION BY m, n_all) - 1) / 2) / NULLIF(COUNT(*) OVER (PARTITION BY m) - 1, 0),
         (RANK() OVER (PARTITION BY m ORDER BY n_season) - 1
           + (COUNT(*) OVER (PARTITION BY m, n_season) - 1) / 2) / NULLIF(COUNT(*) OVER (PARTITION BY m) - 1, 0)
  FROM cnt;

  RETURN ''alert zone-days: '' || (SELECT COUNT(*) FROM DATA_DETECTIVE.CORE.WFR_ZONE_ALERT_DAY) ||
         '', zones with history fires: '' || (SELECT COUNT(DISTINCT zone_id) FROM DATA_DETECTIVE.CORE.WFR_ZONE_HISTORY WHERE n_fires_all > 0) ||
         '', history fires: '' || (SELECT SUM(n_fires_all) FROM DATA_DETECTIVE.CORE.WFR_ZONE_HISTORY WHERE month_of_year = 1);
END;
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.CORE.WFR_BUILD_STATION_DAY("D_FROM" DATE, "D_TO" DATE)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
import datetime

def _month_chunks(d0, d1):
    cur = d0
    while cur <= d1:
        nxt = (cur.replace(day=1) + datetime.timedelta(days=32)).replace(day=1)
        yield cur, min(nxt - datetime.timedelta(days=1), d1)
        cur = nxt

def run(session, d_from, d_to):
    done = []
    for a, b in _month_chunks(d_from, d_to):
        session.sql("DELETE FROM DATA_DETECTIVE.CORE.WFR_STATION_DAY WHERE local_day BETWEEN ? AND ?", [a, b]).collect()
        session.sql("""
            INSERT INTO DATA_DETECTIVE.CORE.WFR_STATION_DAY
            WITH h AS (
              SELECT t.nws_weather_station_id station_id, DATEADD(hour, -7, t.timestamp) local_ts,
                     MAX(IFF(t.variable = ''relative_humidity'', t.value, NULL)) rh,
                     MAX(IFF(t.variable = ''wind_speed'', t.value, NULL)) ws_kmh,
                     MAX(IFF(t.variable = ''wind_gust'', t.value, NULL)) wg_kmh,
                     MAX(IFF(t.variable = ''temperature'', t.value, NULL)) temp_c
              FROM SNOWFLAKE_CURATED_DATA_CORE_WEATHER_DATA.PUBLIC_DATA.NWS_WEATHER_TIMESERIES t
              JOIN DATA_DETECTIVE.CORE.V_WFR_STATIONS s ON s.station_id = t.nws_weather_station_id
              WHERE t.variable IN (''relative_humidity'', ''wind_speed'', ''wind_gust'', ''temperature'')
                AND t.timestamp >= DATEADD(hour, 7, ?::TIMESTAMP_NTZ)
                AND t.timestamp <  DATEADD(hour, 7, DATEADD(day, 1, ?::DATE)::TIMESTAMP_NTZ)
              GROUP BY 1, 2)
            SELECT station_id, local_ts::DATE,
                   MIN(rh),
                   MAX(IFF(ws_kmh IS NULL AND wg_kmh IS NULL, NULL,
                           GREATEST(COALESCE(ws_kmh, 0), COALESCE(0.6 * wg_kmh, 0)))) * 0.621371,
                   MAX(temp_c) * 9 / 5 + 32,
                   COUNT(*), COUNT(rh), COUNT(COALESCE(ws_kmh, wg_kmh)), COUNT(temp_c), CURRENT_TIMESTAMP()
            FROM h GROUP BY 1, 2
        """, [a, b]).collect()
        done.append(str(a)[:7])
    return "built " + ", ".join(done)
';
create or replace task DATA_DETECTIVE.CORE.DAILY_CHECKS
	warehouse=DEFAULT_WH
	schedule='USING CRON 0 7 * * * America/Los_Angeles'
	as EXECUTE IMMEDIATE $$
BEGIN
  IF (DAYOFWEEK(CURRENT_DATE()) = 1) THEN
    CALL DATA_DETECTIVE.CORE.BUILD_BASELINES('NOAA_DAILY');
    CALL DATA_DETECTIVE.CORE.BUILD_BASELINES('NWS_CA_DAILY');
  END IF;
  CALL DATA_DETECTIVE.CORE.RUN_CHECKS('NOAA_DAILY', NULL, 21);
  -- Wildfire risk (wfr-v4a): refresh recent inputs (late-arriving obs), rescore, then check inputs and scores
  CALL DATA_DETECTIVE.CORE.WFR_BUILD_STATION_DAY(DATEADD(day, -3, CURRENT_DATE()), CURRENT_DATE());
  CALL DATA_DETECTIVE.CORE.WFR_BUILD_STATIC('wfr-v4a');
  CALL DATA_DETECTIVE.CORE.SCORE_WILDFIRE_RISK(DATEADD(day, -3, CURRENT_DATE()), CURRENT_DATE(), 'wfr-v4a');
  CALL DATA_DETECTIVE.CORE.RUN_CHECKS('NWS_CA_DAILY', NULL, 21);
  CALL DATA_DETECTIVE.CORE.RUN_WFR_SCORE_CHECKS(NULL, 14, 20);
END;
$$;
create or replace streamlit DATA_DETECTIVE.CORE.DATA_DETECTIVE_APP
	from '@DATA_DETECTIVE.CORE.APP_STAGE/app'
	main_file='streamlit_app.py'
	query_warehouse='DEFAULT_WH'
	title='Data Detective';
create or replace schema DATA_DETECTIVE.DEMO COMMENT='Data Detective demo: CA-only, 2024+, snapshot with labeled MOCK anomalies';

create or replace TABLE DATA_DETECTIVE.DEMO.BASELINES (
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
create or replace TABLE DATA_DETECTIVE.DEMO.CHECK_RESULTS (
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
create or replace TABLE DATA_DETECTIVE.DEMO.CHECK_RUNS (
	RUN_ID VARCHAR(16777216),
	DATASET_ID VARCHAR(16777216),
	AS_OF_DATE DATE,
	WINDOW_START DATE,
	STARTED_AT TIMESTAMP_LTZ(9),
	FINISHED_AT TIMESTAMP_LTZ(9),
	N_FINDINGS NUMBER(38,0)
);
create or replace TABLE DATA_DETECTIVE.DEMO.DATASET_REGISTRY (
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
create or replace TABLE DATA_DETECTIVE.DEMO.INVESTIGATIONS (
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
create or replace TABLE DATA_DETECTIVE.DEMO.INVESTIGATION_STEPS (
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
create or replace TABLE DATA_DETECTIVE.DEMO.METRIC_BOUNDS (
	METRIC VARCHAR(16777216),
	MIN_VALUE FLOAT,
	MAX_VALUE FLOAT,
	UNIT VARCHAR(16777216),
	CONTINUOUS BOOLEAN
);
create or replace TABLE DATA_DETECTIVE.DEMO.MOCK_GROUND_TRUTH (
	MOCK_ID NUMBER(38,0),
	DATASET_ID VARCHAR(16777216),
	EXPECTED_CHECKS ARRAY,
	ENTITY_SCOPE VARCHAR(16777216),
	MATCH_KEY VARCHAR(16777216),
	METRIC VARCHAR(16777216),
	DATE_FROM DATE,
	DATE_TO DATE,
	TRUE_ROOT_CAUSE VARCHAR(16777216),
	EXPECTED_VERDICT VARCHAR(16777216),
	LABEL VARCHAR(16777216) DEFAULT 'MOCK'
);
create or replace TABLE DATA_DETECTIVE.DEMO.MOCK_REMOVED_ROWS (
	MOCK_ID NUMBER(38,0),
	SOURCE_TABLE VARCHAR(16777216),
	ROW_DATA VARIANT,
	REMOVED_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.DEMO.NOAA_ENTITIES (
	ENTITY_ID VARCHAR(16777216),
	ENTITY_NAME VARCHAR(16777216),
	REGION VARCHAR(16777216),
	COUNTRY_NAME VARCHAR(16777216),
	LATITUDE FLOAT,
	LONGITUDE FLOAT,
	ELEVATION FLOAT,
	NETWORK VARCHAR(16777216),
	SEGMENT VARCHAR(16777216)
);
create or replace TABLE DATA_DETECTIVE.DEMO.NOAA_OBS (
	ENTITY_ID VARCHAR(16777216),
	METRIC VARCHAR(16777216),
	OBS_DATE DATE,
	VALUE NUMBER(38,6),
	UNIT VARCHAR(16777216),
	DATA_SOURCE VARCHAR(16777216)
);
create or replace TABLE DATA_DETECTIVE.DEMO.NWS_STATIONS (
	STATION_ID VARCHAR(16777216),
	STATION_NAME VARCHAR(16777216),
	ZONE_ID VARCHAR(16777216),
	COUNTY_GEO_ID VARCHAR(16777216),
	LATITUDE FLOAT,
	LONGITUDE FLOAT,
	ELEVATION FLOAT,
	ZONE_NAME VARCHAR(16777216)
);
create or replace TABLE DATA_DETECTIVE.DEMO.WFIGS_PERIMETERS_CA (
	OBJECTID NUMBER(38,0),
	POLY_SOURCEOID NUMBER(38,0),
	POLY_INCIDENTNAME VARCHAR(16777216),
	POLY_FEATURECATEGORY VARCHAR(16777216),
	POLY_MAPMETHOD VARCHAR(16777216),
	POLY_GISACRES VARCHAR(16777216),
	POLY_DELETETHIS BOOLEAN,
	POLY_FEATUREACCESS VARCHAR(16777216),
	POLY_FEATURESTATUS VARCHAR(16777216),
	POLY_ISVISIBLE BOOLEAN,
	POLY_CREATEDATE VARCHAR(16777216),
	POLY_DATECURRENT VARCHAR(16777216),
	POLY_POLYGONDATETIME VARCHAR(16777216),
	POLY_IRWINID VARCHAR(16777216),
	POLY_FORID VARCHAR(16777216),
	POLY_ACRES_AUTOCALC VARCHAR(16777216),
	POLY_SOURCEGLOBALID VARCHAR(16777216),
	POLY_SOURCE VARCHAR(16777216),
	ATTR_SOURCEOID NUMBER(38,0),
	ATTR_ABCDMISC VARCHAR(16777216),
	ATTR_ADSPERMISSIONSTATE VARCHAR(16777216),
	ATTR_CALCULATEDACRES NUMBER(38,4),
	ATTR_CONTAINMENTDATETIME VARCHAR(16777216),
	ATTR_CONTROLDATETIME VARCHAR(16777216),
	ATTR_CREATEDBYSYSTEM VARCHAR(16777216),
	ATTR_INCIDENTSIZE NUMBER(38,3),
	ATTR_DISCOVERYACRES NUMBER(38,2),
	ATTR_DISPATCHCENTERID VARCHAR(16777216),
	ATTR_ESTIMATEDCOSTTODATE NUMBER(38,2),
	ATTR_FINALACRES NUMBER(38,2),
	ATTR_FFREPORTAPPROVEDBYTITLE VARCHAR(16777216),
	ATTR_FFREPORTAPPROVEDBYUNIT VARCHAR(16777216),
	ATTR_FFREPORTAPPROVEDDATE VARCHAR(16777216),
	ATTR_FIREBEHAVIORGENERAL VARCHAR(16777216),
	ATTR_FIREBEHAVIORGENERAL1 VARCHAR(16777216),
	ATTR_FIREBEHAVIORGENERAL2 VARCHAR(16777216),
	ATTR_FIREBEHAVIORGENERAL3 VARCHAR(16777216),
	ATTR_FIRECAUSE VARCHAR(16777216),
	ATTR_FIRECAUSEGENERAL VARCHAR(16777216),
	ATTR_FIRECAUSESPECIFIC VARCHAR(16777216),
	ATTR_FIRECODE VARCHAR(16777216),
	ATTR_FIREDEPARTMENTID VARCHAR(16777216),
	ATTR_FIREDISCOVERYDATETIME VARCHAR(16777216),
	ATTR_FIREMGMTCOMPLEXITY VARCHAR(16777216),
	ATTR_FIREOUTDATETIME VARCHAR(16777216),
	ATTR_FIRESTRATEGYCONFINEPERCENT NUMBER(38,0),
	ATTR_FIRESTRATEGYFULLSUPPPRCNT NUMBER(38,0),
	ATTR_FIRESTRATEGYMONITORPERCENT NUMBER(38,0),
	ATTR_FIRESTRATEGYPOINTZONEPRCNT NUMBER(38,0),
	ATTR_FSJOBCODE VARCHAR(16777216),
	ATTR_FSOVERRIDECODE VARCHAR(16777216),
	ATTR_GACC VARCHAR(16777216),
	ATTR_ICS209REPORTDATETIME VARCHAR(16777216),
	ATTR_ICS209RPTFORTIMEPERIODFROM VARCHAR(16777216),
	ATTR_ICS209RPTFORTIMEPERIODTO VARCHAR(16777216),
	ATTR_ICS209REPORTSTATUS VARCHAR(16777216),
	ATTR_INCIDENTMANAGEMENTORG VARCHAR(16777216),
	ATTR_INCIDENTNAME VARCHAR(16777216),
	ATTR_INCIDENTSHORTDESCRIPTION VARCHAR(16777216),
	ATTR_INCIDENTTYPECATEGORY VARCHAR(16777216),
	ATTR_INCIDENTTYPEKIND VARCHAR(16777216),
	ATTR_INITIALLATITUDE NUMBER(38,8),
	ATTR_INITIALLONGITUDE NUMBER(38,8),
	ATTR_INITIALRESPONSEACRES NUMBER(38,3),
	ATTR_INITIALRESPONSEDATETIME VARCHAR(16777216),
	ATTR_IRWINID VARCHAR(16777216),
	ATTR_ISFIRECAUSEINVESTIGATED NUMBER(38,0),
	ATTR_ISFIRECODEREQUESTED NUMBER(38,0),
	ATTR_ISFSASSISTED NUMBER(38,0),
	ATTR_ISMULTIJURISDICTIONAL NUMBER(38,0),
	ATTR_ISQUARANTINED NUMBER(38,0),
	ATTR_ISREIMBURSABLE NUMBER(38,0),
	ATTR_ISTRESPASS NUMBER(38,0),
	ATTR_ISUNIFIEDCOMMAND NUMBER(38,0),
	ATTR_ISVALID NUMBER(38,0),
	ATTR_LOCALINCIDENTIDENTIFIER VARCHAR(16777216),
	ATTR_MODIFIEDBYSYSTEM VARCHAR(16777216),
	ATTR_PERCENTCONTAINED NUMBER(38,0),
	ATTR_PERCENTPERIMTOBECONTAINED NUMBER(38,0),
	ATTR_POOCITY VARCHAR(16777216),
	ATTR_POOCOUNTY VARCHAR(16777216),
	ATTR_POODISPATCHCENTERID VARCHAR(16777216),
	ATTR_POOFIPS NUMBER(38,0),
	ATTR_POOJURISDICTIONALAGENCY VARCHAR(16777216),
	ATTR_POOJURISDICTIONALUNIT VARCHAR(16777216),
	ATTR_POOJURISDICTUNITPARENTUNIT VARCHAR(16777216),
	ATTR_POOLANDOWNERCATEGORY VARCHAR(16777216),
	ATTR_POOLANDOWNERKIND VARCHAR(16777216),
	ATTR_POOLEGALDESCPRINCIPALMERID VARCHAR(16777216),
	ATTR_POOLEGALDESCQTR VARCHAR(16777216),
	ATTR_POOLEGALDESCQTRQTR VARCHAR(16777216),
	ATTR_POOLEGALDESCRANGE VARCHAR(16777216),
	ATTR_POOLEGALDESCSECTION NUMBER(38,0),
	ATTR_POOLEGALDESCTOWNSHIP VARCHAR(16777216),
	ATTR_POOPREDICTIVESERVICEAREAID VARCHAR(16777216),
	ATTR_POOPROTECTINGAGENCY VARCHAR(16777216),
	ATTR_POOPROTECTINGUNIT VARCHAR(16777216),
	ATTR_POOSTATE VARCHAR(16777216),
	ATTR_PREDOMINANTFUELGROUP VARCHAR(16777216),
	ATTR_PREDOMINANTFUELMODEL VARCHAR(16777216),
	ATTR_PRIMARYFUELMODEL VARCHAR(16777216),
	ATTR_SECONDARYFUELMODEL VARCHAR(16777216),
	ATTR_TOTALINCIDENTPERSONNEL NUMBER(38,0),
	ATTR_UNIQUEFIREIDENTIFIER VARCHAR(16777216),
	ATTR_FORID VARCHAR(16777216),
	ATTR_WFDSSDECISIONSTATUS VARCHAR(16777216),
	ATTR_ESTIMATEDFINALCOST NUMBER(38,0),
	ATTR_ORGANIZATIONALASSESSMENT VARCHAR(16777216),
	ATTR_STRATDECISIONPUBLISHDATE VARCHAR(16777216),
	ATTR_CREATEDONDATETIME_DT VARCHAR(16777216),
	ATTR_MODIFIEDONDATETIME_DT VARCHAR(16777216),
	ATTR_SOURCE VARCHAR(16777216),
	ATTR_ISCPXCHILD NUMBER(38,0),
	ATTR_CPXNAME VARCHAR(16777216),
	ATTR_CPXID VARCHAR(16777216),
	ATTR_SOURCEGLOBALID VARCHAR(16777216),
	GLOBALID VARCHAR(16777216),
	SHAPE__AREA FLOAT,
	SHAPE__LENGTH VARCHAR(16777216),
	ATTR_INCIDENTCOMPLEXITYLEVEL VARCHAR(16777216)
);
create or replace TABLE DATA_DETECTIVE.DEMO.WFR_CONFIG (
	CONFIG_ID VARCHAR(16777216),
	STATUS VARCHAR(16777216),
	PARAMS VARIANT,
	CREATED_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.DEMO.WFR_SCORES (
	CONFIG_ID VARCHAR(16777216),
	ZONE_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	DRYNESS_RH FLOAT,
	WIND_MPH FLOAT,
	HEAT_F FLOAT,
	ALERT_VALUE FLOAT,
	N_FIRES_ALL NUMBER(38,0),
	N_FIRES_SEASON NUMBER(38,0),
	P_DRYNESS FLOAT,
	P_WIND FLOAT,
	P_HEAT FLOAT,
	P_ALERT FLOAT,
	P_HIST_ALL FLOAT,
	P_HIST_SEASON FLOAT,
	N_REF_DAYS NUMBER(38,0),
	N_STATIONS NUMBER(38,0),
	MISSING_INPUTS ARRAY,
	ALERT_TYPES ARRAY,
	SCORE FLOAT,
	BAND VARCHAR(16777216),
	SCORED_AT TIMESTAMP_LTZ(9)
);
create or replace TABLE DATA_DETECTIVE.DEMO.WFR_STATION_DAY (
	STATION_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	MIN_RH FLOAT,
	MAX_WIND_MPH FLOAT,
	MAX_TEMP_F FLOAT,
	N_HOURS NUMBER(38,0),
	N_RH NUMBER(38,0),
	N_WIND NUMBER(38,0),
	N_TEMP NUMBER(38,0),
	BUILT_AT TIMESTAMP_LTZ(9),
	DATA_SOURCE VARCHAR(16777216)
);
create or replace TABLE DATA_DETECTIVE.DEMO.WFR_ZONE_ALERT_DAY (
	ZONE_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	ALERT_VALUE FLOAT,
	ALERT_TYPES ARRAY,
	DATA_SOURCE VARCHAR(16777216)
);
create or replace TABLE DATA_DETECTIVE.DEMO.WFR_ZONE_DAY (
	ZONE_ID VARCHAR(16777216),
	LOCAL_DAY DATE,
	DRYNESS_RH FLOAT,
	WIND_MPH FLOAT,
	HEAT_F FLOAT,
	N_STATIONS NUMBER(38,0),
	N_RH NUMBER(38,0),
	N_WIND NUMBER(38,0),
	N_TEMP NUMBER(38,0)
);
create or replace TABLE DATA_DETECTIVE.DEMO.WFR_ZONE_HISTORY (
	ZONE_ID VARCHAR(16777216),
	MONTH_OF_YEAR NUMBER(38,0),
	N_FIRES_ALL NUMBER(38,0),
	N_FIRES_SEASON NUMBER(38,0),
	HIST_ALL FLOAT,
	HIST_SEASON FLOAT
);
create or replace view DATA_DETECTIVE.DEMO.V_MOCK_EVAL(
	MOCK_ID,
	LABEL,
	DATASET_ID,
	ENTITY_SCOPE,
	EXPECTED_CHECKS,
	CHECKS_FIRED,
	DETECTED,
	EXAMPLE_SUMMARY,
	INVESTIGATOR_VERDICT,
	VERDICT_CORRECT,
	INVESTIGATOR_TITLE,
	TRUE_ROOT_CAUSE
) as
WITH last_run AS (
  SELECT dataset_id, run_id FROM CHECK_RUNS WHERE finished_at IS NOT NULL
    AND run_id NOT IN (SELECT run_id FROM CHECK_RESULTS WHERE check_type = 'SCORE_REVIEW')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY dataset_id ORDER BY started_at DESC) = 1),
hits AS (
  SELECT g.mock_id, r.result_id, r.check_type, r.summary
  FROM MOCK_GROUND_TRUTH g

  JOIN last_run lr ON lr.dataset_id = g.dataset_id
     OR (ARRAY_CONTAINS('DEGRADED_HIGH_SCORE'::VARIANT, g.expected_checks) AND lr.dataset_id = 'WFR_V4A')
  JOIN CHECK_RESULTS r ON r.run_id = lr.run_id AND ARRAY_CONTAINS(r.check_type::VARIANT, g.expected_checks)
   AND (r.details:entity_id::STRING = g.match_key OR r.details:segment::STRING = g.match_key
        OR r.details:entity_id::STRING IN (SELECT station_id FROM NWS_STATIONS WHERE zone_id = g.match_key))

   AND COALESCE(r.details:date_to::DATE, IFF(r.check_type = 'STALE', g.date_to, r.obs_date)) >= g.date_from),
inv AS (
  SELECT result_id, report FROM INVESTIGATIONS WHERE status = 'COMPLETED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY result_id ORDER BY started_at DESC) = 1),
best AS (
  SELECT h.mock_id, COUNT(*) n_findings, ARRAY_AGG(DISTINCT h.check_type) checks_fired,
         MAX_BY(inv.report, inv.report IS NOT NULL) report, ANY_VALUE(h.summary) example_summary
  FROM hits h LEFT JOIN inv ON inv.result_id = h.result_id GROUP BY 1)
SELECT g.mock_id, g.label, g.dataset_id, g.entity_scope, g.expected_checks, b.checks_fired,
       COALESCE(b.n_findings, 0) > 0 AS detected, b.example_summary,
       b.report:verdict::STRING AS investigator_verdict,
       b.report:verdict::STRING = g.expected_verdict AS verdict_correct,
       b.report:title::STRING AS investigator_title, g.true_root_cause
FROM MOCK_GROUND_TRUTH g LEFT JOIN best b ON b.mock_id = g.mock_id
ORDER BY g.mock_id;
create or replace view DATA_DETECTIVE.DEMO.V_NOAA_ENTITIES(
	ENTITY_ID,
	ENTITY_NAME,
	REGION,
	COUNTRY_NAME,
	LATITUDE,
	LONGITUDE,
	ELEVATION,
	NETWORK,
	SEGMENT
) as SELECT * FROM NOAA_ENTITIES;
create or replace view DATA_DETECTIVE.DEMO.V_NOAA_OBS(
	ENTITY_ID,
	METRIC,
	OBS_DATE,
	VALUE,
	UNIT
) as SELECT entity_id, metric, obs_date, value, unit FROM NOAA_OBS;
create or replace view DATA_DETECTIVE.DEMO.V_NWS_CA_ENTITIES(
	ENTITY_ID,
	ENTITY_NAME,
	REGION,
	COUNTRY_NAME,
	LATITUDE,
	LONGITUDE,
	ELEVATION,
	NETWORK,
	SEGMENT,
	COUNTY_GEO_ID
) as
SELECT station_id AS entity_id, station_name AS entity_name, zone_id AS region, 'United States' AS country_name,
       latitude, longitude, elevation, 'NWS' AS network, zone_id AS segment, county_geo_id
FROM V_WFR_STATIONS;
create or replace view DATA_DETECTIVE.DEMO.V_NWS_CA_OBS(
	ENTITY_ID,
	METRIC,
	OBS_DATE,
	VALUE,
	UNIT
) as
WITH u AS (
  SELECT station_id AS entity_id, LOWER(metric) AS metric, local_day AS obs_date, value
  FROM WFR_STATION_DAY
  UNPIVOT INCLUDE NULLS (value FOR metric IN (min_rh, max_wind_mph, max_temp_f))),

reports AS (SELECT DISTINCT entity_id, metric FROM BASELINES WHERE dataset_id = 'NWS_CA_DAILY' AND n_obs >= 20)
SELECT u.entity_id, u.metric, u.obs_date, u.value,
       DECODE(u.metric, 'min_rh', 'Percent', 'max_wind_mph', 'Miles per hour', 'Degrees Fahrenheit') AS unit
FROM u
WHERE u.value IS NOT NULL
   OR EXISTS (SELECT 1 FROM reports r WHERE r.entity_id = u.entity_id AND r.metric = u.metric);
create or replace view DATA_DETECTIVE.DEMO.V_WFR_COUNTY(
	CONFIG_ID,
	COUNTY_GEO_ID,
	LOCAL_DAY,
	SCORE,
	BAND,
	DRIVING_ZONE,
	N_ZONES
) as
SELECT s.config_id, zc.county_geo_id, s.local_day, MAX(s.score) score,
       MAX_BY(s.band, s.score) band, MAX_BY(s.zone_id, s.score) driving_zone, COUNT(*) n_zones
FROM WFR_SCORES s JOIN V_WFR_ZONE_COUNTY zc ON zc.zone_id = s.zone_id
GROUP BY 1, 2, 3;
create or replace view DATA_DETECTIVE.DEMO.V_WFR_SCORES_TRUST(
	CONFIG_ID,
	ZONE_ID,
	LOCAL_DAY,
	DRYNESS_RH,
	WIND_MPH,
	HEAT_F,
	ALERT_VALUE,
	N_FIRES_ALL,
	N_FIRES_SEASON,
	P_DRYNESS,
	P_WIND,
	P_HEAT,
	P_ALERT,
	P_HIST_ALL,
	P_HIST_SEASON,
	N_REF_DAYS,
	N_STATIONS,
	MISSING_INPUTS,
	ALERT_TYPES,
	SCORE,
	BAND,
	SCORED_AT,
	N_DQ_FINDINGS,
	FINDING_IDS,
	TRUST_REASONS,
	SHARE_BAD_STATIONS,
	N_BAD_STATIONS,
	INPUT_TRUST
) as
WITH last_run AS (
  SELECT run_id FROM CHECK_RUNS WHERE dataset_id = 'NWS_CA_DAILY' AND finished_at IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (ORDER BY started_at DESC) = 1),
f AS (
  SELECT r.result_id, r.check_type, r.severity, r.metric, r.summary, st.station_id,
         COALESCE(st.zone_id, r.details:segment::STRING) zone_id,
         COALESCE(r.details:date_from::DATE, DATEADD(day, 1, r.details:modal_last_date::DATE)) d0,
         COALESCE(r.details:date_to::DATE, cr.as_of_date) d1
  FROM CHECK_RESULTS r JOIN last_run lr ON lr.run_id = r.run_id
  JOIN CHECK_RUNS cr ON cr.run_id = r.run_id
  LEFT JOIN V_WFR_STATIONS st ON st.station_id = r.details:entity_id::STRING
  WHERE r.check_type IN ('NULL_VALUES', 'DUPLICATE', 'OUTLIER', 'FLATLINE', 'STALE')),
zf AS (
  SELECT s.zone_id, s.local_day, COUNT(f.result_id) n_findings, COUNT(DISTINCT f.station_id) n_bad_stations,
         MAX(IFF(f.check_type = 'STALE', 1, 0)) zone_stale,
         ARRAY_AGG(DISTINCT f.check_type || ' ' || f.metric) WITHIN GROUP (ORDER BY f.check_type || ' ' || f.metric) finding_types,
         ARRAY_AGG(f.result_id) finding_ids
  FROM WFR_SCORES s JOIN f ON f.zone_id = s.zone_id AND s.local_day BETWEEN f.d0 AND f.d1
  WHERE s.config_id = 'wfr-v4a'
  GROUP BY 1, 2)
SELECT s.*, COALESCE(zf.n_findings, 0) n_dq_findings, zf.finding_ids,
       ARRAY_CAT(
         ARRAY_CONSTRUCT_COMPACT(
           IFF(s.n_stations = 0, 'no reporting stations (weather factors defaulted to 0.5)', NULL),
           IFF(ARRAY_SIZE(s.missing_inputs) > 0 AND s.n_stations > 0, 'missing inputs: ' || ARRAY_TO_STRING(s.missing_inputs, ', '), NULL),
           IFF(s.n_stations BETWEEN 1 AND 2, 'only ' || s.n_stations || ' reporting station(s)', NULL)),
         COALESCE(TRANSFORM(zf.finding_types, x -> 'data-quality finding: ' || x::STRING), [])) trust_reasons,
       ROUND(COALESCE(zf.n_bad_stations, 0) / NULLIF(s.n_stations, 0), 2) share_bad_stations,
       COALESCE(zf.n_bad_stations, 0) n_bad_stations,

       CASE WHEN s.n_stations = 0 OR ARRAY_SIZE(s.missing_inputs) >= 2 OR COALESCE(zf.zone_stale, 0) = 1
                 OR COALESCE(zf.n_bad_stations, 0) >= GREATEST(1, 0.5 * s.n_stations) THEN 'UNRELIABLE'
            WHEN ARRAY_SIZE(s.missing_inputs) > 0 OR s.n_stations <= 2
                 OR COALESCE(zf.n_bad_stations, 0) >= GREATEST(1, 0.2 * s.n_stations) THEN 'DEGRADED'
            ELSE 'OK' END input_trust
FROM WFR_SCORES s LEFT JOIN zf ON zf.zone_id = s.zone_id AND zf.local_day = s.local_day
WHERE s.config_id = 'wfr-v4a';
create or replace view DATA_DETECTIVE.DEMO.V_WFR_SCORE_OBS(
	ENTITY_ID,
	METRIC,
	OBS_DATE,
	VALUE,
	UNIT
) as
SELECT zone_id AS entity_id, 'wfr_score' AS metric, local_day AS obs_date, score AS value, 'Score 0-100' AS unit
FROM WFR_SCORES WHERE config_id = 'wfr-v4a';
create or replace view DATA_DETECTIVE.DEMO.V_WFR_STATIONS(
	STATION_ID,
	STATION_NAME,
	ZONE_ID,
	COUNTY_GEO_ID,
	LATITUDE,
	LONGITUDE,
	ELEVATION
) as
SELECT station_id, station_name, zone_id, county_geo_id, latitude, longitude, elevation FROM NWS_STATIONS;
create or replace view DATA_DETECTIVE.DEMO.V_WFR_ZONES(
	ZONE_ID,
	LATITUDE,
	LONGITUDE,
	N_STATIONS_INDEXED,
	COUNTIES,
	ZONE_NAME
) as
SELECT zone_id, AVG(latitude) latitude, AVG(longitude) longitude, COUNT(*) n_stations_indexed,
       ARRAY_AGG(DISTINCT county_geo_id) counties, ANY_VALUE(zone_name) zone_name
FROM NWS_STATIONS GROUP BY zone_id;
create or replace view DATA_DETECTIVE.DEMO.V_WFR_ZONE_COUNTY(
	ZONE_ID,
	COUNTY_GEO_ID
) as
SELECT DISTINCT zone_id, county_geo_id FROM V_WFR_STATIONS WHERE county_geo_id IS NOT NULL;
create or replace view DATA_DETECTIVE.DEMO.V_WFR_ZONE_ENTITIES(
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
SELECT zone_id AS entity_id, COALESCE(zone_name, zone_id) AS entity_name, zone_id AS region, 'United States' AS country_name,
       latitude, longitude, NULL::FLOAT AS elevation, 'NWS fire weather zone' AS network, zone_id AS segment
FROM V_WFR_ZONES;
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.DEMO.BUILD_BASELINES("DATASET_ID" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
def run(session, dataset_id):
    reg = session.sql("SELECT obs_view FROM DATA_DETECTIVE.DEMO.DATASET_REGISTRY WHERE dataset_id = ?", [dataset_id]).collect()
    if not reg:
        return f"Unknown dataset {dataset_id}"
    obs = reg[0]["OBS_VIEW"]
    session.sql("DELETE FROM DATA_DETECTIVE.DEMO.BASELINES WHERE dataset_id = ?", [dataset_id]).collect()
    session.sql(f"""
        INSERT INTO DATA_DETECTIVE.DEMO.BASELINES
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
    n = session.sql("SELECT COUNT(*) c FROM DATA_DETECTIVE.DEMO.BASELINES WHERE dataset_id = ?", [dataset_id]).collect()[0]["C"]
    return f"Built {n} baseline rows for {dataset_id}"
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.DEMO.CREATE_WFR_REVIEW("ZONE_ID" VARCHAR, "LOCAL_DAY" DATE)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  rid STRING DEFAULT UUID_STRING();
  fid STRING DEFAULT UUID_STRING();
BEGIN
  INSERT INTO DATA_DETECTIVE.DEMO.CHECK_RUNS (run_id, dataset_id, as_of_date, window_start, started_at, finished_at, n_findings)
    VALUES (:rid, ''WFR_V4A'', :LOCAL_DAY, DATEADD(day, -14, :LOCAL_DAY), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 1);
  INSERT INTO DATA_DETECTIVE.DEMO.CHECK_RESULTS
  SELECT :fid, :rid, ''WFR_V4A'', ''SCORE_REVIEW'', ''wfr_score'', t.local_day, ''MEDIUM'', 1, t.score, NULL,
         ''User review of zone '' || t.zone_id || '' wildfire score '' || ROUND(t.score, 1) || '' ('' || t.band || '') on '' || t.local_day ||
           ''. Explain what drives this score, whether it is trustworthy (input trust: '' || t.input_trust || ''), and how it changed over the prior 14 days.'',
         OBJECT_CONSTRUCT(''entity_id'', t.zone_id, ''date_from'', DATEADD(day, -14, t.local_day), ''date_to'', t.local_day,
                          ''input_trust'', t.input_trust, ''trust_reasons'', t.trust_reasons),
         CURRENT_TIMESTAMP()
  FROM DATA_DETECTIVE.DEMO.V_WFR_SCORES_TRUST t WHERE t.zone_id = :ZONE_ID AND t.local_day = :LOCAL_DAY;
  RETURN fid;
END;
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.DEMO.INVESTIGATE("RESULT_ID" VARCHAR, "MODEL" VARCHAR DEFAULT 'claude-sonnet-4-5', "MAX_STEPS" NUMBER(38,0) DEFAULT 6)
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
        self.allowed_objects = {self.obs.upper(), self.ent.upper(), "DATA_DETECTIVE.DEMO.BASELINES",
                                "DATA_DETECTIVE.DEMO.METRIC_BOUNDS", "DATA_DETECTIVE.DEMO.WFR_SCORES",
                                "DATA_DETECTIVE.DEMO.WFR_STATION_DAY", "DATA_DETECTIVE.DEMO.V_WFR_STATIONS",
                                "DATA_DETECTIVE.DEMO.WFR_ZONE_ALERT_DAY"}

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
          "zone_score_breakdown": {"args": {"zone_id": "str (e.g. CAZ264)", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "wfr-v4a wildfire score per day for a fire weather zone: raw inputs (zone median min RH %, wind mph, max temp F, alert), factor percentiles, weighted contribution of each factor in score points, band, n reporting stations, missing inputs, active alerts. Use to explain score jumps."},
          "zone_station_inputs": {"args": {"zone_id": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD"}, "desc": "Per station and day in a fire weather zone: min RH, max wind mph, max temp F, hours reported. Reveals whether a zone median was driven by one bad/stuck/missing station versus a zone-wide weather change."},
          "nearby_zone_scores": {"args": {"zone_id": "str", "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD", "radius_km": "number (default 100)"}, "desc": "Per day: the target zone''s wildfire score and alert vs the median score and the number of nearby fire weather zones (centroid distance) under Red Flag Warning/Fire Weather Watch. Distinguishes a regional fire-weather event from a zone-specific artifact."},
          "run_sql": {"args": {"sql": "a single read-only SELECT/WITH query"}, "desc": f"Free-form read-only SQL. Only these objects may be referenced: {sorted(self.allowed_objects)}. Columns of obs view: entity_id, metric, obs_date, value, unit. Entity view: entity_id, entity_name, region, country_name, latitude, longitude, elevation, network, segment. WFR_SCORES: config_id, zone_id, local_day, dryness_rh, wind_mph, heat_f, alert_value, n_fires_all, n_fires_season, p_dryness, p_wind, p_heat, p_alert, p_hist_all, p_hist_season, n_ref_days, n_stations, missing_inputs, alert_types, score, band. WFR_STATION_DAY: station_id, local_day, min_rh, max_wind_mph, max_temp_f, n_hours, n_rh, n_wind, n_temp. V_WFR_STATIONS: station_id, station_name, zone_id, county_geo_id, latitude, longitude, elevation. WFR_ZONE_ALERT_DAY: zone_id, local_day, alert_value, alert_types. Results capped at {ROW_LIMIT} rows."},
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
                      FROM {self.obs} o LEFT JOIN DATA_DETECTIVE.DEMO.BASELINES b ON b.dataset_id = ? AND b.entity_id = o.entity_id
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
        if tool == "zone_score_breakdown":
            z = self._id(a.get("zone_id"), "zone_id")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = """SELECT local_day, score, band, n_stations, missing_inputs, alert_types,
                        ROUND(dryness_rh, 1) min_rh_pct, ROUND(wind_mph, 1) wind_mph, ROUND(heat_f, 1) max_temp_f,
                        ROUND(p_dryness, 2) p_dry, ROUND(p_wind, 2) p_wind, ROUND(p_heat, 2) p_heat, p_alert,
                        ROUND(p_hist_all, 2) p_hist_all, ROUND(p_hist_season, 2) p_hist_season,
                        ROUND(100 * p_dryness / 8, 1) pts_dry, ROUND(100 * p_wind / 8, 1) pts_wind, ROUND(100 * p_heat / 8, 1) pts_heat,
                        ROUND(100 * p_alert / 8, 1) pts_alert, ROUND(100 * p_hist_all / 8, 1) pts_hist_all,
                        ROUND(300 * p_hist_season / 8, 1) pts_hist_season
                      FROM DATA_DETECTIVE.DEMO.WFR_SCORES
                      WHERE config_id = ''wfr-v4a'' AND zone_id = ? AND local_day BETWEEN ? AND ? ORDER BY local_day"""
            return sql, [z, d0, d1]
        if tool == "zone_station_inputs":
            z = self._id(a.get("zone_id"), "zone_id")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            sql = """SELECT d.local_day, d.station_id, s.station_name, ROUND(d.min_rh, 1) min_rh, ROUND(d.max_wind_mph, 1) max_wind_mph,
                        ROUND(d.max_temp_f, 1) max_temp_f, d.n_hours
                      FROM DATA_DETECTIVE.DEMO.WFR_STATION_DAY d JOIN DATA_DETECTIVE.DEMO.V_WFR_STATIONS s ON s.station_id = d.station_id
                      WHERE s.zone_id = ? AND d.local_day BETWEEN ? AND ? ORDER BY d.local_day, d.station_id LIMIT 200"""
            return sql, [z, d0, d1]
        if tool == "nearby_zone_scores":
            z = self._id(a.get("zone_id"), "zone_id")
            d0, d1 = self._date(a.get("date_from"), "date_from"), self._date(a.get("date_to"), "date_to")
            radius = max(10.0, min(float(a.get("radius_km") or 100), 400.0))
            sql = """WITH c AS (SELECT zone_id, AVG(latitude) lat, AVG(longitude) lon FROM DATA_DETECTIVE.DEMO.V_WFR_STATIONS GROUP BY 1),
                      nb AS (SELECT o.zone_id FROM c t JOIN c o ON o.zone_id <> t.zone_id
                             WHERE t.zone_id = ? AND HAVERSINE(t.lat, t.lon, o.lat, o.lon) <= ?)
                      SELECT s.local_day,
                             MAX(IFF(s.zone_id = ?, s.score, NULL)) target_score, MAX(IFF(s.zone_id = ?, s.band, NULL)) target_band,
                             MAX(IFF(s.zone_id = ?, s.alert_value, NULL)) target_alert,
                             MEDIAN(IFF(s.zone_id <> ?, s.score, NULL)) neighbor_median_score,
                             COUNT_IF(s.zone_id <> ? AND s.alert_value >= 1) neighbors_rfw, COUNT_IF(s.zone_id <> ? AND s.alert_value = 0.5) neighbors_fww,
                             COUNT_IF(s.zone_id <> ?) n_neighbors
                      FROM DATA_DETECTIVE.DEMO.WFR_SCORES s
                      WHERE s.config_id = ''wfr-v4a'' AND s.local_day BETWEEN ? AND ?
                        AND (s.zone_id = ? OR s.zone_id IN (SELECT zone_id FROM nb))
                      GROUP BY 1 ORDER BY 1"""
            return sql, [z, radius, z, z, z, z, z, z, z, d0, d1, z]
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
- For implausible magnitudes, explicitly test unit/scale hypotheses before concluding "sensor malfunction":
  check whether a simple transform (F->C via (v-32)*5/9, C->F, x10 / /10, km/h<->mph x1.609, mm<->in x25.4)
  maps the anomalous values onto the baseline or neighbor values. If it does, the finding is a unit/scale error.

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

    f = session.sql("SELECT * FROM DATA_DETECTIVE.DEMO.CHECK_RESULTS WHERE result_id = ?", [result_id]).collect()
    if not f: return f"unknown result_id {result_id}"
    finding = _rows(f)[0]
    reg = session.sql("SELECT * FROM DATA_DETECTIVE.DEMO.DATASET_REGISTRY WHERE dataset_id = ?", [finding["dataset_id"]]).collect()[0]
    run_info = _rows(session.sql("SELECT as_of_date, window_start FROM DATA_DETECTIVE.DEMO.CHECK_RUNS WHERE run_id = ?", [finding["run_id"]]).collect())[0]
    metrics = {r["METRIC"] for r in session.sql("SELECT metric FROM DATA_DETECTIVE.DEMO.METRIC_BOUNDS").collect()}
    tools = Tools(session, reg, metrics)

    inv_id = str(uuid.uuid4())
    session.sql("""INSERT INTO DATA_DETECTIVE.DEMO.INVESTIGATIONS (investigation_id, result_id, dataset_id, model, status, started_at)
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
            session.sql("""INSERT INTO DATA_DETECTIVE.DEMO.INVESTIGATION_STEPS (investigation_id, step_no, reasoning, error, created_at)
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
        session.sql("""INSERT INTO DATA_DETECTIVE.DEMO.INVESTIGATION_STEPS
                       SELECT ?, ?, ?, ?, ?, PARSE_JSON(?), ?, ?, PARSE_JSON(?), ?, CURRENT_TIMESTAMP()""",
                    [inv_id, step, msg.get("hypothesis"), msg.get("reasoning"), tool, json.dumps(args, default=_json_default),
                     sql_text, len(rows), json.dumps(rows[:ROW_LIMIT], default=_json_default), err]).collect()

    status = "COMPLETED"
    if report is None:
        status, report = "FAILED", {"title": "Investigation did not complete", "verdict": "INCONCLUSIVE", "summary": "The model did not return a final report."}
    report = _enforce_evidence(report, ok_steps)
    session.sql("""UPDATE DATA_DETECTIVE.DEMO.INVESTIGATIONS SET status = ?, finished_at = CURRENT_TIMESTAMP(),
                   n_steps = ?, report = PARSE_JSON(?) WHERE investigation_id = ?""",
                [status, len(ok_steps), json.dumps(report, default=_json_default), inv_id]).collect()
    return inv_id
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.DEMO.RUN_CHECKS("DATASET_ID" VARCHAR, "AS_OF" DATE DEFAULT null, "LOOKBACK_DAYS" NUMBER(38,0) DEFAULT 21)
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
  LEFT JOIN DATA_DETECTIVE.DEMO.BASELINES b
    ON b.dataset_id = ''{base_ds}'' AND b.entity_id = o.entity_id AND b.metric = o.metric AND b.month_of_year = MONTH(o.obs_date)
  LEFT JOIN DATA_DETECTIVE.DEMO.METRIC_BOUNDS mb ON mb.metric = o.metric
  WHERE o.value IS NOT NULL),
f AS (
  SELECT * FROM s
  WHERE COALESCE(oob, FALSE)
     OR (metric IN (SELECT metric FROM DATA_DETECTIVE.DEMO.METRIC_BOUNDS WHERE continuous) AND ABS(z) > {z} AND (value > p99 OR value < p01))),
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
  WHERE metric IN (SELECT metric FROM DATA_DETECTIVE.DEMO.METRIC_BOUNDS WHERE continuous)
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
    reg = session.sql("SELECT * FROM DATA_DETECTIVE.DEMO.DATASET_REGISTRY WHERE dataset_id = ?", [dataset_id]).collect()
    if not reg:
        return f"Unknown dataset {dataset_id}"
    r = reg[0]
    obs_view, ent_view = r["OBS_VIEW"], r["ENTITY_VIEW"]
    if as_of is None:
        as_of = session.sql(f"SELECT MAX(obs_date) d FROM {obs_view}").collect()[0]["D"]
    lookback = int(lookback_days or 21)
    ws = session.sql(f"SELECT DATEADD(day, -{lookback}, ''{as_of}''::DATE) d").collect()[0]["D"]
    run_id = str(uuid.uuid4())
    session.sql("INSERT INTO DATA_DETECTIVE.DEMO.CHECK_RUNS (run_id, dataset_id, as_of_date, window_start, started_at) "
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
            INSERT INTO DATA_DETECTIVE.DEMO.CHECK_RESULTS
            SELECT UUID_STRING(), ''{run_id}'', ''{dataset_id}'', c.*, CURRENT_TIMESTAMP() FROM ({q}) c
        """).collect()
    n = session.sql("SELECT COUNT(*) c FROM DATA_DETECTIVE.DEMO.CHECK_RESULTS WHERE run_id = ?", [run_id]).collect()[0]["C"]
    session.sql("UPDATE DATA_DETECTIVE.DEMO.CHECK_RUNS SET finished_at = CURRENT_TIMESTAMP(), n_findings = ? WHERE run_id = ?",
                [n, run_id]).collect()
    return run_id
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.DEMO.RUN_WFR_SCORE_CHECKS("AS_OF" DATE DEFAULT null, "LOOKBACK_DAYS" NUMBER(38,0) DEFAULT 14, "JUMP_POINTS" FLOAT DEFAULT 20)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  rid STRING DEFAULT UUID_STRING();
  asof DATE; ws DATE;
BEGIN
  asof := COALESCE(:AS_OF, (SELECT MAX(local_day) FROM DATA_DETECTIVE.DEMO.WFR_SCORES WHERE config_id = ''wfr-v4a''));
  ws := DATEADD(day, -:LOOKBACK_DAYS, :asof);
  INSERT INTO DATA_DETECTIVE.DEMO.CHECK_RUNS (run_id, dataset_id, as_of_date, window_start, started_at)
    VALUES (:rid, ''WFR_V4A'', :asof, :ws, CURRENT_TIMESTAMP());

  INSERT INTO DATA_DETECTIVE.DEMO.CHECK_RESULTS
  WITH s AS (
    SELECT zone_id, local_day, score, band, p_dryness, p_wind, p_heat, p_alert,
           LAG(score) OVER (PARTITION BY zone_id ORDER BY local_day) prev_score,
           LAG(band) OVER (PARTITION BY zone_id ORDER BY local_day) prev_band,
           LAG(p_dryness) OVER (PARTITION BY zone_id ORDER BY local_day) prev_dry,
           LAG(p_wind) OVER (PARTITION BY zone_id ORDER BY local_day) prev_wind,
           LAG(p_heat) OVER (PARTITION BY zone_id ORDER BY local_day) prev_heat,
           LAG(p_alert) OVER (PARTITION BY zone_id ORDER BY local_day) prev_alert
    FROM DATA_DETECTIVE.DEMO.WFR_SCORES
    WHERE config_id = ''wfr-v4a'' AND local_day BETWEEN DATEADD(day, -1, :ws) AND :asof)
  SELECT UUID_STRING(), :rid, ''WFR_V4A'', ''SCORE_JUMP'', ''wfr_score'', local_day,
         IFF(ABS(score - prev_score) >= 1.5 * :JUMP_POINTS, ''HIGH'', ''MEDIUM''), 1, score, prev_score,
         ''Zone '' || zone_id || '' wildfire score '' || IFF(score > prev_score, ''jumped'', ''dropped'') || '' '' ||
           ROUND(prev_score, 1) || '' -> '' || ROUND(score, 1) || '' ('' || prev_band || '' -> '' || band || '') on '' || local_day,
         OBJECT_CONSTRUCT(''entity_id'', zone_id, ''date_from'', DATEADD(day, -1, local_day), ''date_to'', local_day,
           ''factor_deltas'', OBJECT_CONSTRUCT(''dryness'', ROUND(p_dryness - prev_dry, 2), ''wind'', ROUND(p_wind - prev_wind, 2),
                                             ''heat'', ROUND(p_heat - prev_heat, 2), ''alert'', ROUND(p_alert - prev_alert, 2))),
         CURRENT_TIMESTAMP()
  FROM s
  WHERE local_day >= :ws AND prev_score IS NOT NULL AND ABS(score - prev_score) >= :JUMP_POINTS
  UNION ALL
  SELECT UUID_STRING(), :rid, ''WFR_V4A'', ''DEGRADED_HIGH_SCORE'', ''wfr_score'', t.local_day, ''HIGH'', 1, t.score, NULL,
         ''Zone '' || t.zone_id || '' scored '' || t.band || '' ('' || ROUND(t.score, 1) || '') on '' || t.local_day ||
           '' but input trust is '' || t.input_trust || '': '' || ARRAY_TO_STRING(t.trust_reasons, ''; ''),
         OBJECT_CONSTRUCT(''entity_id'', t.zone_id, ''date_from'', t.local_day, ''date_to'', t.local_day,
                          ''trust_reasons'', t.trust_reasons, ''missing_inputs'', t.missing_inputs),
         CURRENT_TIMESTAMP()
  FROM DATA_DETECTIVE.DEMO.V_WFR_SCORES_TRUST t
  WHERE t.local_day BETWEEN :ws AND :asof AND t.band IN (''High'', ''Very High'', ''Extreme'') AND t.input_trust <> ''OK''
  UNION ALL
  -- Red Flag Warning / Fire Weather Watch in a zone while no zone within 100 km has any alert that day
  SELECT UUID_STRING(), :rid, ''WFR_V4A'', ''ISOLATED_ALERT'', ''alert'', a.local_day, ''HIGH'', 1, a.alert_value, 0,
         ''Zone '' || a.zone_id || '' has '' || ARRAY_TO_STRING(a.alert_types, '', '') || '' on '' || a.local_day ||
           '' but none of '' || COUNT(nb.zone_id) || '' zones within 100 km has a fire-weather alert'',
         OBJECT_CONSTRUCT(''entity_id'', a.zone_id, ''date_from'', a.local_day, ''date_to'', a.local_day,
                          ''alert_types'', a.alert_types, ''n_neighbor_zones'', COUNT(nb.zone_id)),
         CURRENT_TIMESTAMP()
  FROM DATA_DETECTIVE.DEMO.WFR_ZONE_ALERT_DAY a
  JOIN DATA_DETECTIVE.DEMO.V_WFR_ZONES t ON t.zone_id = a.zone_id
  JOIN DATA_DETECTIVE.DEMO.V_WFR_ZONES nb ON nb.zone_id <> a.zone_id
   AND HAVERSINE(t.latitude, t.longitude, nb.latitude, nb.longitude) <= 100
  LEFT JOIN DATA_DETECTIVE.DEMO.WFR_ZONE_ALERT_DAY na ON na.zone_id = nb.zone_id AND na.local_day = a.local_day
  WHERE a.local_day BETWEEN :ws AND :asof
  GROUP BY a.zone_id, a.local_day, a.alert_value, a.alert_types
  HAVING COUNT(nb.zone_id) >= 2 AND COUNT(na.zone_id) = 0;

  UPDATE DATA_DETECTIVE.DEMO.CHECK_RUNS SET finished_at = CURRENT_TIMESTAMP(),
    n_findings = (SELECT COUNT(*) FROM DATA_DETECTIVE.DEMO.CHECK_RESULTS WHERE run_id = :rid) WHERE run_id = :rid;
  RETURN rid;
END;
';
CREATE OR REPLACE PROCEDURE DATA_DETECTIVE.DEMO.SCORE_WILDFIRE_RISK("D_FROM" DATE, "D_TO" DATE, "CONFIG_ID" VARCHAR DEFAULT 'wfr-v4a')
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  ref_from DATE; ref_to DATE; wt FLOAT; miss FLOAT;
  w_dry FLOAT; w_wind FLOAT; w_heat FLOAT; w_alert FLOAT; w_ha FLOAT; w_hs FLOAT;
  b_mod FLOAT; b_high FLOAT; b_vh FLOAT; b_ext FLOAT;
BEGIN
  SELECT params:reference_period[0]::DATE, params:reference_period[1]::DATE, params:weight_total::FLOAT, params:missing_factor::FLOAT,
         params:weights:dryness::FLOAT, params:weights:wind::FLOAT, params:weights:heat::FLOAT, params:weights:alert::FLOAT,
         params:weights:hist_all::FLOAT, params:weights:hist_season::FLOAT,
         params:bands[1]:min::FLOAT, params:bands[2]:min::FLOAT, params:bands[3]:min::FLOAT, params:bands[4]:min::FLOAT
    INTO :ref_from, :ref_to, :wt, :miss, :w_dry, :w_wind, :w_heat, :w_alert, :w_ha, :w_hs, :b_mod, :b_high, :b_vh, :b_ext
    FROM DATA_DETECTIVE.DEMO.WFR_CONFIG WHERE config_id = :CONFIG_ID;

  -- Zone-day = median across stations
  DELETE FROM DATA_DETECTIVE.DEMO.WFR_ZONE_DAY
   WHERE local_day BETWEEN :ref_from AND :ref_to OR local_day BETWEEN :D_FROM AND :D_TO;
  INSERT INTO DATA_DETECTIVE.DEMO.WFR_ZONE_DAY
  SELECT s.zone_id, d.local_day, MEDIAN(d.min_rh), MEDIAN(d.max_wind_mph), MEDIAN(d.max_temp_f),
         COUNT(DISTINCT d.station_id), COUNT(d.min_rh), COUNT(d.max_wind_mph), COUNT(d.max_temp_f)
  FROM DATA_DETECTIVE.DEMO.WFR_STATION_DAY d JOIN DATA_DETECTIVE.DEMO.V_WFR_STATIONS s ON s.station_id = d.station_id
  WHERE d.local_day BETWEEN :ref_from AND :ref_to OR d.local_day BETWEEN :D_FROM AND :D_TO
  GROUP BY 1, 2;

  DELETE FROM DATA_DETECTIVE.DEMO.WFR_SCORES WHERE config_id = :CONFIG_ID AND local_day BETWEEN :D_FROM AND :D_TO;
  INSERT INTO DATA_DETECTIVE.DEMO.WFR_SCORES
  WITH grid AS (
    SELECT z.zone_id, DATEADD(day, g.n, :D_FROM) local_day
    FROM (SELECT DISTINCT zone_id FROM DATA_DETECTIVE.DEMO.V_WFR_STATIONS) z
    CROSS JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 n FROM TABLE(GENERATOR(ROWCOUNT => 1000))) g
    WHERE DATEADD(day, g.n, :D_FROM) <= :D_TO),
  cur AS (
    SELECT g.zone_id, g.local_day, zd.dryness_rh, zd.wind_mph, zd.heat_f, COALESCE(zd.n_stations, 0) n_stations
    FROM grid g LEFT JOIN DATA_DETECTIVE.DEMO.WFR_ZONE_DAY zd ON zd.zone_id = g.zone_id AND zd.local_day = g.local_day),
  -- share of same-zone, same-month reference days less risky than the scored day (ties = 0.5)
  pct AS (
    SELECT c.zone_id, c.local_day,
           COUNT(r.local_day) n_ref,
           (COUNT_IF(r.dryness_rh > c.dryness_rh) + 0.5 * COUNT_IF(r.dryness_rh = c.dryness_rh)) / NULLIF(COUNT(r.dryness_rh), 0) p_dry,
           (COUNT_IF(r.wind_mph < c.wind_mph) + 0.5 * COUNT_IF(r.wind_mph = c.wind_mph)) / NULLIF(COUNT(r.wind_mph), 0) p_wind,
           (COUNT_IF(r.heat_f < c.heat_f) + 0.5 * COUNT_IF(r.heat_f = c.heat_f)) / NULLIF(COUNT(r.heat_f), 0) p_heat
    FROM cur c LEFT JOIN DATA_DETECTIVE.DEMO.WFR_ZONE_DAY r
      ON r.zone_id = c.zone_id AND MONTH(r.local_day) = MONTH(c.local_day) AND r.local_day BETWEEN :ref_from AND :ref_to
    GROUP BY 1, 2),
  f AS (
    SELECT c.*, a.alert_value, a.alert_types, h.n_fires_all, h.n_fires_season, p.n_ref,
           IFF(c.dryness_rh IS NULL, :miss, COALESCE(p.p_dry, :miss)) p_dryness,
           IFF(c.wind_mph IS NULL, :miss, COALESCE(p.p_wind, :miss)) p_wind,
           IFF(c.heat_f IS NULL, :miss, COALESCE(p.p_heat, :miss)) p_heat,
           COALESCE(a.alert_value, 0) p_alert,
           COALESCE(h.hist_all, :miss) p_hist_all, COALESCE(h.hist_season, :miss) p_hist_season
    FROM cur c
    JOIN pct p ON p.zone_id = c.zone_id AND p.local_day = c.local_day
    LEFT JOIN DATA_DETECTIVE.DEMO.WFR_ZONE_ALERT_DAY a ON a.zone_id = c.zone_id AND a.local_day = c.local_day
    LEFT JOIN DATA_DETECTIVE.DEMO.WFR_ZONE_HISTORY h ON h.zone_id = c.zone_id AND h.month_of_year = MONTH(c.local_day)),
  s AS (
    SELECT f.*, ROUND(100 * (:w_dry * p_dryness + :w_wind * p_wind + :w_heat * p_heat
                 + :w_alert * p_alert + :w_ha * p_hist_all + :w_hs * p_hist_season) / :wt, 1) score
    FROM f)
  SELECT :CONFIG_ID, zone_id, local_day, dryness_rh, wind_mph, heat_f, COALESCE(alert_value, 0), n_fires_all, n_fires_season,
         p_dryness, p_wind, p_heat, p_alert, p_hist_all, p_hist_season, n_ref, n_stations,
         ARRAY_CONSTRUCT_COMPACT(IFF(dryness_rh IS NULL, ''dryness'', NULL), IFF(wind_mph IS NULL, ''wind'', NULL),
                                 IFF(heat_f IS NULL, ''heat'', NULL), IFF(n_ref = 0, ''reference_days'', NULL)),
         alert_types, score,
         CASE WHEN score >= :b_ext THEN ''Extreme'' WHEN score >= :b_vh THEN ''Very High'' WHEN score >= :b_high THEN ''High''
              WHEN score >= :b_mod THEN ''Moderate'' ELSE ''Low'' END,
         CURRENT_TIMESTAMP()
  FROM s;

  RETURN ''scored '' || (SELECT COUNT(*) FROM DATA_DETECTIVE.DEMO.WFR_SCORES
                        WHERE config_id = :CONFIG_ID AND local_day BETWEEN :D_FROM AND :D_TO) || '' zone-days'';
END;
';
create or replace schema DATA_DETECTIVE.PUBLIC;
