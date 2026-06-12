# ==============================================================================
# Script: 01a_define_study_design.R
# Purpose: Define and validate factors and blocking settings.
# ==============================================================================

if (!exists("base_path")) source(file.path("scripts", "00_setup.R"))

factor_specs <- workflow_config$factor_specs
factor_names <- names(factor_specs)
levels_design <- unname(vapply(factor_specs, length, integer(1)))
block_sizes <- as.integer(workflow_config$block_sizes)
chosen_block_size <- as.integer(workflow_config$chosen_block_size)
design_seed <- as.integer(workflow_config$design_seed)
optblock_repeats <- as.integer(workflow_config$optblock_repeats)
model_formula <- stats::as.formula(paste("~", paste(factor_names, collapse = " + ")))

if (any(levels_design < 2)) stop("Every factor must have at least two levels.")
n_full_design_rows <- prod(levels_design)
invalid_sizes <- block_sizes[n_full_design_rows %% block_sizes != 0]
if (length(invalid_sizes) > 0) {
  stop("Block sizes must divide the full design: ", paste(invalid_sizes, collapse = ", "))
}
if (!chosen_block_size %in% block_sizes) {
  stop("chosen_block_size must be included in block_sizes.")
}
if (is.na(optblock_repeats) || optblock_repeats < 1) {
  stop("optblock_repeats must be a positive integer.")
}

study_design_specification <- list(
  factor_specs = factor_specs,
  design_settings = list(
    factor_names = factor_names,
    levels_design = levels_design,
    block_sizes = block_sizes,
    chosen_block_size = chosen_block_size,
    design_seed = design_seed,
    optblock_repeats = optblock_repeats,
    model_formula = model_formula
  )
)

if (!exists("print_study_design_summary", inherits = FALSE)) {
  print_study_design_summary <- TRUE
}
if (isTRUE(print_study_design_summary)) {
  cat("\n============================================================\n")
  cat("STUDY DESIGN CONFIGURATION\n")
  cat("============================================================\n")
  print(tibble::tibble(
    factor = factor_names,
    levels = vapply(factor_specs, paste, character(1), collapse = ", "),
    n_levels = levels_design
  ))
  cat("Full factorial vignettes:", n_full_design_rows, "\n")
  cat("Candidate block sizes:", paste(block_sizes, collapse = ", "), "\n")
  cat("Chosen block size:", chosen_block_size, "\n")
  cat("Design seed:", design_seed, "\n")
  cat("optBlock repeats:", optblock_repeats, "\n")
}
