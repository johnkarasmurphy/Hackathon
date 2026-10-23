# Snowflake hackathon

## Data Detective

Data Detective is an AI-powered data quality investigator built entirely inside Snowflake, with Claude as the investigator. It profiles weather observations from the Snowflake Marketplace dataset `SNOWFLAKE_CURATED_CORE_WEATHER_DATA`, flags anomalies, and explains why they happened. It also checks the data behind a wildfire risk score (`wfr-v4a`) to show whether a score can be trusted.

### What it does

1. **Profile and check.** Daily checks compare recent observations against historical baselines (per entity, metric and month) and flag null values, duplicates, stale records, volume drops, outliers and flatlined sensors. Wildfire score checks catch score jumps, high scores built on degraded inputs, and isolated alerts.
2. **Investigate.** For each finding, Claude runs a hypothesis-driven loop. It states a hypothesis, picks one read-only analysis to test it, reads the result, and updates its beliefs. The analyses cover entity profiles, time series, cross-metric comparisons, neighbor comparisons, network-level reporting and score breakdowns. It will also explicitly test unit and scale errors (such as F to C or mph to km/h) before it blames a sensor.
3. **Report.** Each investigation produces a structured, evidence-backed report: verdict (`DATA_ERROR`, `REAL_EVENT` or `INCONCLUSIVE`), severity, affected entities, dates and rows, what was ruled out, prioritized recommended actions, and a SQL check to detect recurrence.
4. **Review.** A Streamlit app lets users pick a dataset, run checks, read findings and investigations, browse history, and request a review of any wildfire score.

### Benefits from Snowflake

- **Data never leaves the platform.** The data, baselines, checks, investigation steps and reports all live in Snowflake. Claude is called from inside Snowflake, so there is no export, extra pipeline or external API key to manage.
- **Cortex AI access to Claude.** Stored procedures call Claude (Sonnet, Opus or Haiku) through Snowflake Cortex `AI_COMPLETE`. Users can pick the model per run to trade off cost, speed and depth.
- **Snowpark stored procedures.** The checks, baseline builds, wildfire scoring and the investigation loop run as Python and SQL procedures next to the data. They execute as the caller, so Snowflake roles and access controls still apply.
- **Marketplace data.** Weather observations come straight from the Snowflake Marketplace, with no ingestion work and no external data dependencies.
- **Scheduled monitoring.** A Snowflake Task (`DAILY_CHECKS`, 7am Los Angeles time) reruns the checks and the wildfire rescoring automatically.
- **Streamlit in Snowflake.** The UI is hosted and governed in the same account, and queries Snowflake directly through the active session.
- **Auditable by design.** Every check run, investigation and analysis step is stored in tables, so findings can be reviewed and reproduced later.

### Benefits from Anthropic (Claude)

- **Root-cause reasoning, not just alerts.** Claude plans a sequence of analyses, tests competing explanations, and tells real-world events apart from data errors by using neighbor and related-metric evidence.
- **Honest about uncertainty.** The prompt separates confirmed findings from likely causes with a confidence level. A finding can only be "confirmed" if it cites the investigation steps that show it. Code in the procedure demotes any confirmed finding that lacks successful supporting evidence to a likely cause.
- **Grounded in evidence.** Claude is told to quote only values seen in results and never invent numbers. It runs at temperature 0 for repeatable output.
- **Structured output.** Claude returns strict JSON for each step and for the final report. That makes reports easy to store, query and display.
- **Safe by construction.** Claude can only call a catalog of named, read-only tools. The `run_sql` fallback is validated, and statements that write, alter or call anything are rejected. Row counts are capped per step.
- **Model choice.** Sonnet, Opus and Haiku are selectable from the app's sidebar.

### Architecture

```
Marketplace weather data ─► checks + baselines (Snowpark procedures, daily Task)
                                    │ findings
                                    ▼
                  INVESTIGATE (Snowpark procedure)
        Claude via Cortex AI_COMPLETE ◄─► read-only analysis tools
                                    │ evidence-backed report
                                    ▼
                  Streamlit in Snowflake app
```

### Layout

- `data_detective/`: the project. See [`data_detective/README.md`](data_detective/README.md) for Snowflake objects and redeploy notes, and `data_detective/docs/mvp_summary.txt` for the MVP description.
  - `sql/data_detective_ddl.sql`: full DDL for the `DATA_DETECTIVE` database
  - `streamlit_app/`: Streamlit in Snowflake app source

