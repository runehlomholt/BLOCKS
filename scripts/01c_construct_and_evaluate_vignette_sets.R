# ==============================================================================
# Script: 01c_construct_and_evaluate_vignette_sets.R
# Purpose: Construct, evaluate, and export blocked vignette sets.
# ==============================================================================

source(file.path("scripts", "00_setup.R"))
require_workflow_packages(c("AlgDesign", "openxlsx", "dplyr", "tibble", "readr"))
print_study_design_summary <- FALSE
source(file.path(path_scripts, "01a_define_study_design.R"))
source(file.path(path_helpers, "design_helpers.R"))

full_design_file <- file.path(path_design, "full_factorial_design.rds")
if (!file.exists(full_design_file)) {
  stop("Run scripts/01b_generate_factorial_design.R first.")
}
full_design <- readRDS(full_design_file)
set.seed(design_seed)

blocked_designs <- list()
comparison <- lapply(block_sizes, function(set_size) {
  n_sets <- nrow(full_design) / set_size
  blocked <- AlgDesign::optBlock(
    frml = model_formula,
    withinData = full_design,
    blocksizes = rep(set_size, n_sets),
    criterion = "D",
    nRepeats = optblock_repeats,
    center = FALSE
  )
  blocked_designs[[paste0("size", set_size)]] <<- blocked
  evaluate_block_design(blocked, set_size, model_formula)
})
comparison <- dplyr::bind_rows(comparison)

cat("\n============================================================\n")
cat("CANDIDATE BLOCKED-DESIGN COMPARISON\n")
cat("============================================================\n")
print(comparison, width = Inf)

blocked_design <- blocked_designs[[paste0("size", chosen_block_size)]]
canonical_workbook <- file.path(path_design, "vignette_sets.xlsx")
legacy_workbook <- file.path(
  path_design,
  paste0("vignette_sets_size_", chosen_block_size, ".xlsx")
)
saveRDS(blocked_design, file.path(path_design, "blocked_design.rds"))
save_blocked_sets_to_excel(blocked_design, canonical_workbook)
save_blocked_sets_to_excel(blocked_design, legacy_workbook)
readr::write_csv(comparison, file.path(path_design, "block_design_comparison.csv"))

integrity <- check_blocked_design_integrity(full_design, canonical_workbook)
print_blocked_design_integrity(integrity)
message("Chosen block size exported: ", chosen_block_size)
