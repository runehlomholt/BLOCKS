# ==============================================================================
# Script: 03a_monitor_database.R
# Purpose: Read-only monitoring of a deployed BLOCKS PostgreSQL database.
# ==============================================================================

source(file.path("scripts", "00_setup.R"))
source(file.path(path_helpers, "database_helpers.R"))

run_database_monitor <- function() {
connection <- connect_blocks_database()
on.exit(DBI::dbDisconnect(connection), add = TRUE)
assert_blocks_schema(connection)

expiry_minutes <- as.integer(Sys.getenv("ALLOCATION_EXPIRY_MINUTES", "60"))
if (is.na(expiry_minutes) || expiry_minutes < 1) {
  stop("ALLOCATION_EXPIRY_MINUTES must be a positive integer.")
}

status_counts <- DBI::dbGetQuery(connection, "
  SELECT status, COUNT(*)::int AS n
  FROM respondents
  GROUP BY status
  ORDER BY status
")
status_n <- function(name) {
  value <- status_counts$n[status_counts$status == name]
  if (length(value) == 0) 0L else value[[1]]
}

response_metrics <- DBI::dbGetQuery(connection, "
  WITH episodes AS (
    SELECT
      respondent_id,
      vignette_order,
      MAX(answer_change_count)::int AS answer_changes
    FROM vignette_responses
    GROUP BY respondent_id, vignette_order
  )
  SELECT
    COUNT(DISTINCT respondent_id)::int AS respondents_with_responses,
    COUNT(*)::int AS vignette_episodes,
    COUNT(*) FILTER (WHERE answer_changes > 0)::int AS revised_episodes,
    ROUND(AVG(answer_changes), 2) AS average_answer_changes
  FROM episodes
")

judgement_metrics <- DBI::dbGetQuery(connection, "
  SELECT
    COUNT(*)::int AS stored_rows,
    COUNT(DISTINCT (respondent_id, vignette_order, question_id))::int
      AS unique_judgements
  FROM vignette_responses
")

attention_metrics <- DBI::dbGetQuery(connection, "
  SELECT
    COUNT(*) FILTER (WHERE attention_completed = TRUE)::int AS reached,
    COUNT(*) FILTER (
      WHERE attention_completed = TRUE AND attention_correct = TRUE
    )::int AS passed,
    COUNT(*) FILTER (
      WHERE attention_completed = TRUE AND attention_correct = FALSE
    )::int AS failed,
    ROUND(AVG(attention_latency_ms) FILTER (
      WHERE attention_latency_ms IS NOT NULL
    ))::int AS average_latency_ms
  FROM respondents
")

stale_allocations <- DBI::dbGetQuery(connection, paste0("
  SELECT COUNT(*)::int AS n
  FROM respondents
  WHERE status = 'allocated'
    AND last_activity_at < CURRENT_TIMESTAMP - INTERVAL '",
  expiry_minutes,
  " minutes'
"))$n[[1]]

summary_table <- tibble::tibble(
  metric = c(
    "All respondent records",
    "Currently allocated",
    "Currently started",
    "Completed",
    "Abandoned before first response",
    paste0("Allocated but inactive > ", expiry_minutes, " minutes"),
    "Respondents with responses",
    "Vignette episodes",
    "Stored item-response rows",
    "Unique judgements",
    "Episodes with answer revisions",
    "Average answer changes per episode",
    "Attention check reached",
    "Attention check passed",
    "Attention check failed",
    "Average attention latency (ms)"
  ),
  value = c(
    sum(status_counts$n),
    status_n("allocated"),
    status_n("started"),
    status_n("completed"),
    status_n("abandoned"),
    stale_allocations,
    response_metrics$respondents_with_responses,
    response_metrics$vignette_episodes,
    judgement_metrics$stored_rows,
    judgement_metrics$unique_judgements,
    response_metrics$revised_episodes,
    response_metrics$average_answer_changes,
    attention_metrics$reached,
    attention_metrics$passed,
    attention_metrics$failed,
    attention_metrics$average_latency_ms
  )
)

respondents_by_set <- DBI::dbGetQuery(connection, "
  SELECT
    condition_set,
    COUNT(*)::int AS total,
    COUNT(*) FILTER (WHERE status = 'allocated')::int AS allocated,
    COUNT(*) FILTER (WHERE status = 'started')::int AS started,
    COUNT(*) FILTER (WHERE status = 'completed')::int AS completed,
    COUNT(*) FILTER (WHERE status = 'abandoned')::int AS abandoned
  FROM respondents
  GROUP BY condition_set
  ORDER BY CAST(REPLACE(condition_set, 'Set_', '') AS INTEGER)
")

attention_gate_diagnostic <- DBI::dbGetQuery(connection, "
  WITH progress AS (
    SELECT
      r.id,
      r.status,
      r.attention_order,
      r.attention_completed,
      COUNT(DISTINCT vr.vignette_order)::int AS completed_vignettes
    FROM respondents r
    LEFT JOIN vignette_responses vr ON vr.respondent_id = r.id
    GROUP BY r.id, r.status, r.attention_order, r.attention_completed
  )
  SELECT
    CASE
      WHEN status = 'abandoned' THEN 'abandoned before first response'
      WHEN attention_order IS NULL THEN 'no attention check planned'
      WHEN attention_completed = TRUE THEN 'attention submitted'
      WHEN completed_vignettes < attention_order THEN 'attention not yet due'
      WHEN completed_vignettes = attention_order THEN 'stopped at attention gate'
      ELSE 'inconsistent attention progression'
    END AS attention_status,
    COUNT(*)::int AS n
  FROM progress
  GROUP BY attention_status
  ORDER BY attention_status
")

cat("\n============================================================\n")
cat("BLOCKS DATABASE MONITOR\n")
cat("============================================================\n")
print(summary_table, n = Inf)
cat("\nRESPONDENTS BY VIGNETTE SET\n")
print(tibble::as_tibble(respondents_by_set), n = Inf)
cat("\nATTENTION-GATE DIAGNOSTIC\n")
print(tibble::as_tibble(attention_gate_diagnostic), n = Inf)
}

run_database_monitor()
