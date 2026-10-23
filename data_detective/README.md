# Data Detective

AI-powered data quality investigator built with Snowflake and Claude. It profiles weather observations from the Snowflake Marketplace dataset `SNOWFLAKE_CURATED_CORE_WEATHER_DATA`, flags anomalies, and uses read-only SQL to investigate root causes.

See `docs/mvp_summary.txt` for the MVP description.

## Layout

- `sql/data_detective_ddl.sql`: full DDL for the `DATA_DETECTIVE` database (schemas, tables, views, stored procedures, task and Streamlit app), exported with `GET_DDL('DATABASE','DATA_DETECTIVE',TRUE)`.
- `streamlit_app/`: Streamlit in Snowflake app source (`streamlit_app.py`, `environment.yml`), staged at `@DATA_DETECTIVE.CORE.APP_STAGE/app`.
- `docs/`: project notes.

## Snowflake objects

Everything lives in `DATA_DETECTIVE.CORE`.

- Tables: `BASELINES`, `CHECK_RESULTS`, `CHECK_RUNS`, `DATASET_REGISTRY`, `DEMO_GROUND_TRUTH`, `INVESTIGATIONS`, `INVESTIGATION_STEPS`, `METRIC_BOUNDS`
- Views: `V_DEMO_EVAL`, `V_NOAA_ENTITIES`, `V_NOAA_OBS`, `V_NOAA_OBS_DEMO`
- Procedures: `BUILD_BASELINES`, `RUN_CHECKS`, `INVESTIGATE`
- Task: `DAILY_CHECKS` (suspended; daily at 7am Los Angeles time)
- Streamlit app: `DATA_DETECTIVE_APP` on `DEFAULT_WH`

## Redeploying

The DDL uses `create or replace`, which drops existing objects and data. Run it only against an account where that is intended. The DDL contains no table data.
