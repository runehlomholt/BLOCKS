# ==============================================================================
# Script: 02a_generate_vignette_texts.R
# Purpose: Generate implementation-ready vignette text files.
# ==============================================================================

source(file.path("scripts", "00_setup.R"))
require_workflow_packages(c("dplyr", "purrr", "tibble", "readr"))
print_study_design_summary <- FALSE
source(file.path(path_scripts, "01a_define_study_design.R"))
source(file.path(path_helpers, "text_helpers.R"))

full_design_file <- file.path(path_outputs, "full_factorial_design.rds")
blocked_design_file <- file.path(path_outputs, "blocked_design.rds")
if (!file.exists(full_design_file) || !file.exists(blocked_design_file)) {
  stop("Run scripts/01b and scripts/01c before generating vignette text.")
}

full_design <- readRDS(full_design_file)
blocked_design <- readRDS(blocked_design_file)
vignette_sets <- blocked_design$Blocks
if (!is.list(vignette_sets) || length(vignette_sets) == 0) {
  stop("blocked_design.rds does not contain any vignette sets.")
}
header_file <- file.path(path_text_fragments, "header.txt")
static_folder <- file.path(path_text_fragments, "static")
header_text <- if (file.exists(header_file)) readr::read_file(header_file) else ""

static_files <- list.files(static_folder, pattern = "\\.txt$", full.names = TRUE)
if (length(static_files) == 0) stop("No static text fragments found in ", static_folder)
static_texts <- tibble::tibble(
  name = tools::file_path_sans_ext(basename(static_files)),
  text = vapply(static_files, readr::read_file, character(1))
)
factor_texts <- purrr::imap(
  factor_specs,
  ~ read_factor_texts(file.path(path_text_fragments, .y), .y, .x)
)

merge_order <- workflow_config$merge_order
valid_keys <- c("header", static_texts$name, names(factor_texts))
unknown_keys <- setdiff(merge_order, valid_keys)
if (length(unknown_keys) > 0) {
  stop("Unknown merge_order key(s): ", paste(unknown_keys, collapse = ", "))
}

resolve_fragment <- function(key, row) {
  if (key == "header") return(header_text)
  if (key %in% static_texts$name) {
    return(static_texts$text[static_texts$name == key][[1]])
  }
  level <- row[[key]][[1]]
  match <- factor_texts[[key]]$text[factor_texts[[key]]$level == level]
  if (length(match) != 1) stop("Cannot resolve fragment ", key, " level ", level)
  match[[1]]
}

if (isTRUE(workflow_config$clean_generated_vignettes)) {
  set_dirs <- Sys.glob(file.path(path_app_vignettes, "Set_*"))
  if (length(set_dirs) > 0) unlink(set_dirs, recursive = TRUE, force = TRUE)
}

for (set_index in seq_along(vignette_sets)) {
  set_name <- paste0("Set_", set_index)
  set_data <- vignette_sets[[set_index]]
  if (!"id" %in% names(set_data)) stop("Missing id column in ", set_name)

  for (vignette_id in set_data$id) {
    row <- dplyr::filter(full_design, id == vignette_id)
    if (nrow(row) != 1) stop("Vignette id did not resolve uniquely: ", vignette_id)
    text <- collapse_text_fragments(vapply(
      merge_order,
      resolve_fragment,
      character(1),
      row = row
    ))

    set_folder <- file.path(path_app_vignettes, set_name)
    dir.create(set_folder, showWarnings = FALSE, recursive = TRUE)
    writeLines(text, file.path(set_folder, paste0("vignette_", vignette_id, ".txt")))
  }
}

message(
  "Generated ", length(vignette_sets), " balanced vignette sets in:\n - ",
  path_app_vignettes
)
