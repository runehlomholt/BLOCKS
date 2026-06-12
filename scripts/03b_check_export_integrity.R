# ==============================================================================
# Script: 03b_check_export_integrity.R
# Purpose: Validate a CSV downloaded from the protected /export endpoint.
# Usage: Rscript scripts/03b_check_export_integrity.R [path/to/export.csv]
# ==============================================================================

source(file.path("scripts", "00_setup.R"))
require_workflow_packages(c("readr", "dplyr", "tibble", "tidyr"))

arguments <- commandArgs(trailingOnly = TRUE)
input_file <- if (length(arguments) > 0) arguments[[1]] else "vignette_data.csv"
if (!file.exists(input_file)) stop("Export file not found: ", input_file)
data <- readr::read_csv(input_file, show_col_types = FALSE)

required_columns <- c(
  "internal_id", "respondent_id", "block", "status", "vignette",
  "vignette_order", "latency_ms", "click_count", "answer_change_count",
  "attention_order", "attention_completed", "attention_correct",
  "attention_presented_at", "attention_submitted_at", "attention_latency_ms"
)
missing_columns <- setdiff(required_columns, names(data))
if (length(missing_columns) > 0) {
  stop("Missing required export columns: ", paste(missing_columns, collapse = ", "))
}

metadata_columns <- c(
  required_columns,
  "allocated_at", "participant_started_at", "participant_completed_at",
  "participant_abandoned_at", "design_version", "app_version",
  "client_started_at", "client_ended_at", "server_received_at"
)
item_columns <- setdiff(names(data), metadata_columns)
if (length(item_columns) == 0) stop("No question-response columns were detected.")

duplicate_episodes <- data |>
  dplyr::count(internal_id, vignette_order) |>
  dplyr::filter(n > 1)
invalid_status <- data |>
  dplyr::filter(!status %in% c("allocated", "started", "completed", "abandoned"))
invalid_latency <- data |>
  dplyr::filter(is.na(latency_ms) | latency_ms < 0)
invalid_changes <- data |>
  dplyr::filter(is.na(answer_change_count) | answer_change_count < 0)
missing_items <- data |>
  dplyr::summarise(dplyr::across(dplyr::all_of(item_columns), ~ sum(is.na(.x)))) |>
  tidyr::pivot_longer(dplyr::everything(), names_to = "item", values_to = "missing") |>
  dplyr::filter(missing > 0)

checks <- tibble::tibble(
  check = c(
    "Unique respondent x vignette-order rows",
    "Valid lifecycle statuses",
    "Non-negative response latency",
    "Non-negative answer-change count",
    "Complete question responses"
  ),
  passed = c(
    nrow(duplicate_episodes) == 0,
    nrow(invalid_status) == 0,
    nrow(invalid_latency) == 0,
    nrow(invalid_changes) == 0,
    nrow(missing_items) == 0
  ),
  issues = c(
    nrow(duplicate_episodes),
    nrow(invalid_status),
    nrow(invalid_latency),
    nrow(invalid_changes),
    nrow(missing_items)
  )
)

print(checks, n = Inf)
if (!all(checks$passed)) stop("One or more export-integrity checks failed.")

output_file <- file.path(
  dirname(input_file),
  paste0(tools::file_path_sans_ext(basename(input_file)), "_checked.csv")
)
readr::write_csv(data, output_file)
message("Export integrity checks passed. Checked file: ", output_file)
