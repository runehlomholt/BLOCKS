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
# Started experiment
#   A respondent who appears at least once in `vignette_responses`
#   (i.e., evaluated at least one vignette).
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

# -------------------------------
# Database connection (via DATABASE_URL)
# -------------------------------
# This script expects the database connection details to be provided
# via an environment variable called DATABASE_URL.
#
# Format (PostgreSQL):
#   postgresql://USER:PASSWORD@HOST:PORT/DBNAME?sslmode=require
#
# Example:
#   postgresql://myuser:mypassword@containers-us-west-42.railway.app:6543/railway
#
# How to set this:
#
# 1) Temporarily (recommended for interactive use in R / RStudio):
#    Sys.setenv(
#      DATABASE_URL = "postgresql://USER:PASSWORD@HOST:PORT/DBNAME?sslmode=require"
#    )
#
# 2) Permanently (recommended for repeated use):
#    - Add it to your .Renviron file, e.g.:
#        DATABASE_URL=postgresql://USER:PASSWORD@HOST:PORT/DBNAME?sslmode=require
#
# 3) On Railway:
#    - This variable is already provided automatically.
#
# NOTE:
# - Do NOT hard-code credentials directly into the script.
# - Restart R after changing .Renviron for changes to take effect.
#
# -------------------------------

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
# REMEMBER TO SET THE NUMBER OF VIGNETTES PER SET HERE ACCORDING TO YOU DESIGN ##
monitor_db <- function(con, vignettes_per_set = 4) {
  stopifnot(is.numeric(vignettes_per_set), vignettes_per_set > 0)
  
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
  
  # 3) Started: appear in vignette_responses at least once
  n_started <- dbGetQuery(con, "
    SELECT COUNT(DISTINCT respondent_id)::int AS n
    FROM vignette_responses
  ")$n[[1]]
  
  # 4) Completed experiment: exactly vignettes_per_set distinct vignette_order
  n_completed_experiment <- dbGetQuery(con, glue("
    SELECT COUNT(*)::int AS n
    FROM (
      SELECT respondent_id
      FROM vignette_responses
      GROUP BY respondent_id
      HAVING COUNT(DISTINCT vignette_order) = {vignettes_per_set}
    ) t
  "))$n[[1]]
  
  # 5) Dropped out: started, but fewer than vignettes_per_set distinct vignette_order
  n_dropped_out <- dbGetQuery(con, glue("
    SELECT COUNT(*)::int AS n
    FROM (
      SELECT respondent_id
      FROM vignette_responses
      GROUP BY respondent_id
      HAVING COUNT(DISTINCT vignette_order) BETWEEN 1 AND {vignettes_per_set - 1}
    ) t
  "))$n[[1]]
  
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
  
  # 7) Attention check stats + fail percent among reached
  att_counts <- dbGetQuery(con, "
    SELECT
      SUM(CASE WHEN attention_completed = TRUE THEN 1 ELSE 0 END)::int AS n_reached,
      SUM(CASE WHEN attention_completed = TRUE AND COALESCE(attention_correct, FALSE) = TRUE THEN 1 ELSE 0 END)::int AS n_passed,
      SUM(CASE WHEN attention_completed = TRUE AND COALESCE(attention_correct, FALSE) = FALSE THEN 1 ELSE 0 END)::int AS n_failed
    FROM respondents
  ") %>% as_tibble()
  
  att_reached <- att_counts$n_reached[[1]]
  att_passed  <- att_counts$n_passed[[1]]
  att_failed  <- att_counts$n_failed[[1]]
  
  att_pass_rate <- if (!is.na(att_reached) && att_reached > 0) round(100 * att_passed / att_reached, 1) else NA_real_
  att_fail_rate <- if (!is.na(att_reached) && att_reached > 0) round(100 * att_failed / att_reached, 1) else NA_real_
  
  # 8) Diagnostic: unique respondents per condition set
  respondents_by_set <- dbGetQuery(con, "
    SELECT condition_set,
           COUNT(DISTINCT id)::int AS n_unique_respondents
    FROM respondents
    GROUP BY condition_set
    ORDER BY condition_set
  ") %>%
    as_tibble() %>%
    rename(
      `Vignette set` = condition_set,
      `Unique respondents (N)` = n_unique_respondents
    )
  
  # Summary tibble (compact + interpretive)
  summary_tbl <- tibble(
    `Metric` = c(
      "N unique respondents (respondents.id)",
      "Duplicate respondent entries (same external_id; should be 0)",
      "Respondents who started (have any vignette response)",
      "Completed experiment (evaluated all designed vignettes)",
      "Dropped out (started but evaluated fewer than designed vignettes)",
      "Judgements recorded (respondent × vignette (order) × question)",
      "Average judgements per vignette evaluated",
      "Attention check reached",
      "Attention check passed",
      "Attention check failed",
      "Attention check fail rate (%) among reached"
    ),
    `Value` = c(
      n_unique_respondents,
      n_duplicates,
      n_started,
      n_completed_experiment,
      n_dropped_out,
      n_judgements,
      avg_judgements_per_vignette,
      att_reached,
      att_passed,
      att_failed,
      att_fail_rate
    )
  )
  
  list(summary = summary_tbl, respondents_by_set = respondents_by_set)
}


# -------------------------------
# Run + print
# -------------------------------
vignettes_per_set <- 4
res <- monitor_db(con, vignettes_per_set)

print(res$summary)
print(res$respondents_by_set)

dbDisconnect(con)  # optional
