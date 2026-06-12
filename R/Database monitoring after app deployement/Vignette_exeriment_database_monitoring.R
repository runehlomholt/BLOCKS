# ============================================================
# Experiment Monitoring Script – Railway PostgreSQL
# ============================================================
# Purpose
# -------
# This script provides a compact, human-readable monitoring overview of an
# online factorial-survey / vignette experiment stored in a PostgreSQL database
# (deployed on Railway).
#
# It is intended for *diagnostic and monitoring* use during data collection,
# not for final analysis.
#
#
# Core Concepts (Operational Definitions)
# ---------------------------------------
# Respondent
#   A unique row in the `respondents` table.
#
# Participant lifecycle
#   The `respondents.status` field records allocated, started, completed, or
#   abandoned. Abandoned allocations remain available as recruitment paradata
#   but are ignored by future quota allocation.
#
# Completed experiment
#   A respondent who evaluated exactly the number of vignettes specified by
#   the experimental design (`vignettes_per_set`), operationalised as:
#     COUNT(DISTINCT vignette_order) == vignettes_per_set
#
# Dropped out of experiment
#   A respondent who started the experiment but evaluated fewer vignettes than
#   specified by the design:
#     1 ≤ COUNT(DISTINCT vignette_order) < vignettes_per_set
#
# Judgements recorded
#   The total number of evaluative data points, defined as distinct combinations of:
#     respondent × vignette exposure (vignette_order) × question
#
#
# Attention Check
# ---------------
# A respondent is counted as having FAILED the attention check if:
#   attention_completed == TRUE
#   AND attention_correct == FALSE
#
#
# Output
# ------
# The script prints:
#   1) A compact tibble with intuitive, interpretive metrics
#   2) A breakdown of respondents by experimental condition set
#
#
# Configuration
# -------------
# - Set `vignettes_per_set` to match the experimental design.
# - Requires DATABASE_URL to be set as an environment variable.
#
#
# Notes
# -----
# - The script assumes item-level storage in `vignette_responses`
#   (one row per respondent × vignette × question).
# - Vignette exposure is tracked via `vignette_order`, not `vignette_id`.
# - The script deliberately avoids episode-level inflation from restarts or
#   duplicated vignette IDs.
#
# ============================================================


if (!requireNamespace("pacman", quietly = TRUE)) {
  install.packages("pacman")
}

pacman::p_load(
  DBI,
  RPostgres,
  dplyr,
  glue,
  tibble
)

# Always print full tibbles (all rows + all columns) in this script/session
options(
  tibble.print_max = Inf,
  tibble.print_min = Inf,
  dplyr.print_max  = Inf
)

parse_db_url <- function(url) {
  stopifnot(nzchar(url))
  
  # Normalise URL scheme (Railway may use postgresql://)
  url <- sub("^postgresql://", "postgres://", url)
  
  m <- regexec("^postgres://([^:]+):([^@]+)@([^:/]+):(\\d+)/(.*)$", url)
  parts <- regmatches(url, m)[[1]]
  if (length(parts) < 6) {
    stop("DATABASE_URL did not match expected format.")
  }
  
  # Strip query string from database name (e.g. ?sslmode=require)
  dbname <- sub("\\?.*$", "", parts[6])
  
  list(
    user     = parts[2],
    password = parts[3],
    host     = parts[4],
    port     = as.integer(parts[5]),
    dbname   = dbname
  )
}

# Read DATABASE_URL from environment
DATABASE_URL <- Sys.getenv("DATABASE_URL")

if (!nzchar(DATABASE_URL)) {
  stop(
    "DATABASE_URL is empty.\n",
    "Set it using Sys.setenv(DATABASE_URL = 'postgresql://USER:PASSWORD@HOST:PORT/DBNAME?sslmode=require')\n",
    "or add it to your .Renviron file."
  )
}

db_cfg <- parse_db_url(DATABASE_URL)

# -------------------------------
# Connect
# -------------------------------
con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = db_cfg$dbname,
  host     = db_cfg$host,
  port     = db_cfg$port,
  user     = db_cfg$user,
  password = db_cfg$password,
  sslmode  = "require"
)
message("✔ Connected to PostgreSQL")

# -------------------------------
# Monitoring function
# -------------------------------
monitor_db <- function(con) {
  
  # 1) N unique respondents (Respondent.id is unique per row)
  n_unique_respondents <- dbGetQuery(con, "
    SELECT COUNT(DISTINCT id)::int AS n
    FROM respondents
  ")$n[[1]]
  
  # 2) Duplicate external_id count (diagnostic: should be 0)
  # Counts how many *extra* rows exist beyond the first for each duplicated external_id.
  n_duplicates <- dbGetQuery(con, "
    SELECT COALESCE(SUM(dup_count - 1), 0)::int AS n
    FROM (
      SELECT external_id, COUNT(*) AS dup_count
      FROM respondents
      GROUP BY external_id
      HAVING COUNT(*) > 1
    ) d
  ")$n[[1]]
  
  # 3) Lifecycle status counts
  status_counts <- dbGetQuery(con, "
    SELECT status, COUNT(*)::int AS n
    FROM respondents
    GROUP BY status
    ORDER BY status
  ") %>% as_tibble()

  status_n <- function(name) {
    value <- status_counts$n[status_counts$status == name]
    if (length(value) == 0) 0L else value[[1]]
  }

  n_allocated <- status_n("allocated")
  n_abandoned <- status_n("abandoned")

  # Started includes both active starters and completed participants.
  n_started <- dbGetQuery(con, "
    SELECT COUNT(DISTINCT respondent_id)::int AS n
    FROM vignette_responses
  ")$n[[1]]
  
  # 4) Completion is recorded by the application after the final assignment.
  n_completed_experiment <- status_n("completed")
  
  # 5) Current partial starters. These may still resume later.
  n_partial <- status_n("started")
  
  # 6) Judgements recorded (respondent × vignette_order × question_id)
  n_judgements <- dbGetQuery(con, "
    SELECT COUNT(*)::int AS n
    FROM (
      SELECT DISTINCT respondent_id, vignette_order, question_id
      FROM vignette_responses
    ) t
  ")$n[[1]]
  
  # Average judgements per vignette exposure
  avg_judgements_per_vignette <- dbGetQuery(con, "
    SELECT
      CASE
        WHEN COUNT(DISTINCT (respondent_id, vignette_order)) = 0 THEN NULL
        ELSE ROUND(
          COUNT(DISTINCT (respondent_id, vignette_order, question_id))::numeric
          / COUNT(DISTINCT (respondent_id, vignette_order))::numeric
        , 2)
      END AS avg
    FROM vignette_responses
  ")$avg[[1]]

  answer_change_stats <- dbGetQuery(con, "
    WITH episodes AS (
      SELECT respondent_id, vignette_order, MAX(answer_change_count)::int AS changes
      FROM vignette_responses
      GROUP BY respondent_id, vignette_order
    )
    SELECT
      COUNT(*) FILTER (WHERE changes > 0)::int AS n_revised,
      ROUND(AVG(changes), 2) AS avg_changes
    FROM episodes
  ") %>% as_tibble()

  n_revised <- answer_change_stats$n_revised[[1]]
  avg_answer_changes <- answer_change_stats$avg_changes[[1]]
  
  # 7) Attention check stats + fail percent among reached
  att_counts <- dbGetQuery(con, "
    SELECT
      SUM(CASE WHEN attention_completed = TRUE THEN 1 ELSE 0 END)::int AS n_reached,
      SUM(CASE WHEN attention_completed = TRUE AND COALESCE(attention_correct, FALSE) = TRUE THEN 1 ELSE 0 END)::int AS n_passed,
      SUM(CASE WHEN attention_completed = TRUE AND COALESCE(attention_correct, FALSE) = FALSE THEN 1 ELSE 0 END)::int AS n_failed,
      ROUND(AVG(attention_latency_ms) FILTER (WHERE attention_latency_ms IS NOT NULL))::int AS avg_latency_ms
    FROM respondents
  ") %>% as_tibble()
  
  att_reached <- att_counts$n_reached[[1]]
  att_passed  <- att_counts$n_passed[[1]]
  att_failed  <- att_counts$n_failed[[1]]
  att_avg_latency <- att_counts$avg_latency_ms[[1]]
  
  att_pass_rate <- if (!is.na(att_reached) && att_reached > 0) round(100 * att_passed / att_reached, 1) else NA_real_
  att_fail_rate <- if (!is.na(att_reached) && att_reached > 0) round(100 * att_failed / att_reached, 1) else NA_real_
  
  # 8) Diagnostic: unique respondents per condition set
  respondents_by_set <- dbGetQuery(con, "
    SELECT condition_set,
           COUNT(DISTINCT id)::int AS n_unique_respondents,
           COUNT(*) FILTER (WHERE status = 'allocated')::int AS n_allocated,
           COUNT(*) FILTER (WHERE status = 'started')::int AS n_started,
           COUNT(*) FILTER (WHERE status = 'completed')::int AS n_completed,
           COUNT(*) FILTER (WHERE status = 'abandoned')::int AS n_abandoned
    FROM respondents
    GROUP BY condition_set
    ORDER BY condition_set
  ") %>%
    as_tibble() %>%
    rename(
      `Vignette set` = condition_set,
      `Unique respondents (N)` = n_unique_respondents,
      `Allocated` = n_allocated,
      `Started` = n_started,
      `Completed` = n_completed,
      `Abandoned` = n_abandoned
    )
  
  # Summary tibble (compact + interpretive)
  summary_tbl <- tibble(
    `Metric` = c(
      "N unique respondents (respondents.id)",
      "Duplicate respondent entries (same external_id; should be 0)",
      "Currently allocated (not yet started)",
      "Abandoned before first response",
      "Respondents who started (have any vignette response)",
      "Currently partial (started but not completed)",
      "Completed experiment",
      "Judgements recorded (respondent × vignette (order) × question)",
      "Average judgements per vignette evaluated",
      "Vignette responses revised at least once",
      "Average answer changes per vignette response",
      "Attention check reached",
      "Attention check passed",
      "Attention check failed",
      "Attention check fail rate (%) among reached",
      "Average attention-check latency (ms)"
    ),
    `Value` = c(
      n_unique_respondents,
      n_duplicates,
      n_allocated,
      n_abandoned,
      n_started,
      n_partial,
      n_completed_experiment,
      n_judgements,
      avg_judgements_per_vignette,
      n_revised,
      avg_answer_changes,
      att_reached,
      att_passed,
      att_failed,
      att_fail_rate,
      att_avg_latency
    )
  )
  
  list(summary = summary_tbl, respondents_by_set = respondents_by_set)
}


# -------------------------------
# Run + print
# -------------------------------
res <- monitor_db(con)

print(res$summary)
print(res$respondents_by_set)

# Non-starters are retained as allocated or abandoned lifecycle records.
# Do not delete them during data collection; their counts are reported above.



## attention diagnostics ##
attention_gate_diagnostic <- dbGetQuery(con, "
WITH progress AS (
  SELECT
    r.id AS respondent_id,
    r.external_id,
    r.condition_set,
    r.attention_order,
    r.attention_completed,
    r.attention_correct,
    COUNT(DISTINCT vr.vignette_order)::int AS n_vignettes_completed,
    MAX(vr.vignette_order)::int AS max_vignette_order
  FROM respondents r
  LEFT JOIN vignette_responses vr
    ON vr.respondent_id = r.id
  GROUP BY
    r.id,
    r.external_id,
    r.condition_set,
    r.attention_order,
    r.attention_completed,
    r.attention_correct
)
SELECT
  CASE
    WHEN n_vignettes_completed = 0 THEN
      '00 no vignette submitted'

    WHEN attention_order IS NULL THEN
      '01 no attention plan'

    WHEN attention_completed = TRUE THEN
      '04 attention submitted'

    WHEN n_vignettes_completed < attention_order THEN
      '02 dropped before attention was due'

    WHEN n_vignettes_completed = attention_order THEN
      '03 stopped at scheduled attention gate'

    WHEN n_vignettes_completed > attention_order
         AND COALESCE(attention_completed, FALSE) = FALSE THEN
      '99 inconsistent: passed gate without attention_completed'

    ELSE
      '98 other'
  END AS attention_status,
  COUNT(*)::int AS n
FROM progress
GROUP BY attention_status
ORDER BY attention_status
") %>% as_tibble()

print(attention_gate_diagnostic)

# # 6) Optional: rerun monitoring after cleanup
res <- monitor_db(con)

print(res$summary)
print(res$respondents_by_set)

#######
dbDisconnect(con)  # optional
