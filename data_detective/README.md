# Data Detective

AI-powered data quality investigator built with Snowflake and Claude. It profiles weather observations from the Snowflake Marketplace dataset `SNOWFLAKE_CURATED_CORE_WEATHER_DATA`, flags anomalies, and uses read-only SQL to investigate root causes.

See `docs/mvp_summary.txt` for the MVP description.

## Layout

- `sql/data_detective_ddl.sql`: full DDL for the `DATA_DETECTIVE` database (schemas, tables, views, stored procedures, task and Streamlit app), exported with `GET_DDL('DATABASE','DATA_DETECTIVE',TRUE)`.
- `streamlit_app/`: Streamlit in Snowflake app source (`streamlit_app.py`, `environment.yml`), staged at `@DATA_DETECTIVE.CORE.APP_STAGE/app`.
- `docs/`: project notes.

## Snowflake objects

Two schemas: `DATA_DETECTIVE.CORE` (live data) and `DATA_DETECTIVE.DEMO` (California-only 2024+ snapshot with labeled MOCK anomalies; the app switches between them with the sidebar Environment toggle).

`CORE`:

- Tables: `BASELINES`, `CHECK_RESULTS`, `CHECK_RUNS`, `DATASET_REGISTRY`, `DEMO_GROUND_TRUTH`, `INVESTIGATIONS`, `INVESTIGATION_STEPS`, `METRIC_BOUNDS`
- Wildfire risk tables (wfr-v4a): `WFR_CONFIG`, `WFR_SCORES`, `WFR_STATION_DAY`, `WFR_ZONE_DAY`, `WFR_ZONE_ALERT_DAY`, `WFR_ZONE_HISTORY`
- Views: `V_DEMO_EVAL`, `V_NOAA_ENTITIES`, `V_NOAA_OBS`, `V_NOAA_OBS_DEMO`, `V_NWS_CA_ENTITIES`, `V_NWS_CA_OBS`, `V_WFR_COUNTY`, `V_WFR_SCORE_OBS`, `V_WFR_SCORES_TRUST`, `V_WFR_STATIONS`, `V_WFR_ZONE_COUNTY`, `V_WFR_ZONE_ENTITIES`, `V_WFR_ZONES`
- Procedures: `BUILD_BASELINES`, `RUN_CHECKS`, `INVESTIGATE`, `CREATE_WFR_REVIEW`, `RUN_WFR_SCORE_CHECKS`, `SCORE_WILDFIRE_RISK`, `WFR_BUILD_STATIC`, `WFR_BUILD_STATION_DAY`
- Task: `DAILY_CHECKS` (started; daily at 7am Los Angeles time; runs the data checks and the wfr-v4a rescoring)
- Streamlit app: `DATA_DETECTIVE_APP` on `DEFAULT_WH`

`DEMO` has copies of the tables, views and procedures above, plus `MOCK_GROUND_TRUTH`, `MOCK_REMOVED_ROWS`, `NOAA_ENTITIES`, `NOAA_OBS`, `NWS_STATIONS`, `WFIGS_PERIMETERS_CA` and the view `V_MOCK_EVAL`.

## Redeploying

The DDL uses `create or replace`, which drops existing objects and data. Run it only against an account where that is intended. The DDL contains no table data.
