########################################################
# Vignette experiment – data integrity checks
########################################################

# 1. Packages -------------------------------------------------------------

if (!requireNamespace("pacman", quietly = TRUE)) {
  install.packages("pacman")
}

pacman::p_load(
  tidyverse,
  janitor
)

# 2. Load data ------------------------------------------------------------

data_raw <- read_csv(
  "vignette_data.csv",
  col_types = cols()
) %>%
  clean_names()

message("✔ Data loaded")
glimpse(data_raw)

# Registry for check results
check_results <- list()

register_check <- function(name, passed, note = NULL) {
  check_results[[name]] <<- list(
    passed = passed,
    note = note
  )
}

# 3. Required variables ---------------------------------------------------

required_vars <- c(
  "internal_id",
  "respondent_id",
  "block",
  "vignette",
  "vignette_order",
  "latency_ms",
  "answer_change_count",
  "attention_order",
  "attention_completed",
  "attention_correct"
)

missing_vars <- setdiff(required_vars, names(data_raw))

if (length(missing_vars) > 0) {
  register_check(
    "Required variables present",
    FALSE,
    paste("Missing:", paste(missing_vars, collapse = ", "))
  )
  stop("❌ Required variables missing: ", paste(missing_vars, collapse = ", "))
} else {
  register_check(
    "Required variables present",
    TRUE
  )
}

# 4. Identify item columns ------------------------------------------------

meta_vars <- c(
  "internal_id",
  "respondent_id",
  "block",
  "vignette",
  "vignette_order",
  "latency_ms",
  "click_count",
  "answer_change_count",
  "status",
  "allocated_at",
  "participant_started_at",
  "participant_completed_at",
  "participant_abandoned_at",
  "attention_presented_at",
  "attention_submitted_at",
  "attention_latency_ms",
  "client_started_at",
  "client_ended_at",
  "server_received_at",
  "design_version",
  "app_version",
  "attention_order",
  "attention_completed",
  "attention_correct"
)

item_vars <- setdiff(names(data_raw), meta_vars)

if (length(item_vars) == 0) {
  register_check(
    "Item columns detected",
    FALSE,
    "No item columns found"
  )
  stop("❌ No item columns detected")
} else {
  register_check(
    "Item columns detected",
    TRUE,
    paste(length(item_vars), "items")
  )
}

# 5. One row per respondent × vignette -----------------------------------

dup_rows <- data_raw %>%
  count(internal_id, vignette, vignette_order) %>%
  filter(n > 1)

register_check(
  "Unique respondent × vignette rows",
  nrow(dup_rows) == 0,
  ifelse(nrow(dup_rows) == 0,
         "No duplicates detected",
         paste(nrow(dup_rows), "duplicate rows"))
)

# 6. Rows per respondent consistency -------------------------------------

rows_per_respondent <- data_raw %>%
  count(internal_id)

n_unique <- n_distinct(rows_per_respondent$n)

register_check(
  "Equal number of vignettes per respondent",
  n_unique == 1,
  ifelse(
    n_unique == 1,
    paste("All respondents have", unique(rows_per_respondent$n), "rows"),
    "Unequal number of vignette rows across respondents"
  )
)

# 7. Vignette order integrity --------------------------------------------

order_check <- data_raw %>%
  group_by(internal_id) %>%
  summarise(
    min_order = min(vignette_order, na.rm = TRUE),
    max_order = max(vignette_order, na.rm = TRUE),
    n_rows = n(),
    .groups = "drop"
  )

order_violations <- order_check %>%
  filter(min_order != 1 | max_order != n_rows)

register_check(
  "Vignette order continuity",
  nrow(order_violations) == 0,
  ifelse(
    nrow(order_violations) == 0,
    "Orders start at 1 and are continuous",
    paste(nrow(order_violations), "respondents with order problems")
  )
)

# 8. Item response completeness ------------------------------------------

missing_items <- data_raw %>%
  select(all_of(item_vars)) %>%
  summarise(across(everything(), ~ sum(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "item", values_to = "n_missing") %>%
  filter(n_missing > 0)

register_check(
  "No missing item responses",
  nrow(missing_items) == 0,
  ifelse(
    nrow(missing_items) == 0,
    "All item responses present",
    paste(nrow(missing_items), "items with missing values")
  )
)

# 9. Response-time plausibility ------------------------------------------

fast_responses <- data_raw %>%
  filter(latency_ms < 300)

register_check(
  "Response time plausibility",
  nrow(fast_responses) == 0,
  paste(nrow(fast_responses), "vignettes < 300 ms")
)

# 10. Click count sanity --------------------------------------------------

if ("click_count" %in% names(data_raw)) {
  
  zero_clicks <- data_raw %>%
    filter(click_count < 1)
  
  register_check(
    "Click count recorded",
    TRUE,
    paste(nrow(zero_clicks), "rows with <1 click")
  )
  
} else {
  register_check(
    "Click count recorded",
    FALSE,
    "click_count variable missing"
  )
}

# 11. Attention check consistency ----------------------------------------

attention_summary <- data_raw %>%
  distinct(internal_id, attention_order, attention_completed, attention_correct,
           attention_presented_at, attention_submitted_at, attention_latency_ms)

register_check(
  "Attention check info present",
  nrow(attention_summary) == n_distinct(data_raw$internal_id),
  "One attention record per respondent"
)

failed_attention <- attention_summary %>%
  filter(attention_completed & !attention_correct)

register_check(
  "Attention check pass rate",
  nrow(failed_attention) == 0,
  paste(nrow(failed_attention), "respondents failed attention check")
)

# 12. Block randomisation sanity -----------------------------------------

negative_answer_changes <- data_raw %>%
  filter(answer_change_count < 0)

register_check(
  "Answer-change count valid",
  nrow(negative_answer_changes) == 0,
  paste(nrow(negative_answer_changes), "rows with negative counts")
)

block_counts <- data_raw %>%
  distinct(internal_id, block) %>%
  count(block)

register_check(
  "Multiple blocks present",
  nrow(block_counts) > 1,
  paste("Blocks:", paste(block_counts$block, collapse = ", "))
)

# 13. FINAL SUMMARY -------------------------------------------------------

message("\n================ DATA INTEGRITY SUMMARY ================\n")

for (name in names(check_results)) {
  res <- check_results[[name]]
  status <- if (res$passed) "✔ PASSES" else "✖ DID NOT PASS"
  message(sprintf("%-40s %s", name, status))
  if (!is.null(res$note)) {
    message("   ↳ ", res$note)
  }
}

message("\n========================================================\n")

# 14. Analysis-ready dataset ---------------------------------------------

analysis_data <- data_raw %>%
  select(
    internal_id,
    respondent_id,
    block,
    any_of(c(
      "status", "allocated_at", "participant_started_at",
      "participant_completed_at", "participant_abandoned_at",
      "design_version", "app_version"
    )),
    vignette,
    vignette_order,
    all_of(item_vars),
    any_of(c("client_started_at", "client_ended_at", "server_received_at")),
    latency_ms,
    any_of("click_count"),
    answer_change_count,
    attention_order,
    attention_completed,
    attention_correct,
    any_of(c(
      "attention_presented_at", "attention_submitted_at",
      "attention_latency_ms"
    ))
  )

write_csv(analysis_data, "vignette_data_clean.csv")

message("✔ Clean analysis dataset written to vignette_data_clean.csv")
