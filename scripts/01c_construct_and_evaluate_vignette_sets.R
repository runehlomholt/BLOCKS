# ==============================================================================
# Script: 01c_construct_and_evaluate_vignette_sets.R
# Purpose: Construct, evaluate, and export blocked vignette sets.
# ==============================================================================

source(file.path("scripts", "00_setup.R"))
require_workflow_packages(c(
  "AlgDesign", "openxlsx", "dplyr", "tibble", "xml2", "zip"
))
print_study_design_summary <- FALSE
source(file.path(path_scripts, "01a_define_study_design.R"))
source(file.path(path_helpers, "design_helpers.R"))

full_design_file <- file.path(path_outputs, "full_factorial_design.rds")
if (!file.exists(full_design_file)) {
  stop("Run scripts/01b_generate_factorial_design.R first.")
}
full_design <- readRDS(full_design_file)
set.seed(design_seed)

if (nrow(full_design) %% chosen_block_size != 0) {
  stop("chosen_block_size must divide the full design exactly.")
}

n_sets <- nrow(full_design) / chosen_block_size
blocked_design <- AlgDesign::optBlock(
  frml = model_formula,
  withinData = full_design,
  blocksizes = rep(chosen_block_size, n_sets),
  criterion = "D",
  nRepeats = optblock_repeats,
  center = FALSE
)

algdesign_evaluation <- evaluate_algdesign_block_design(
  blocked_design = blocked_design,
  set_size = chosen_block_size,
  formula = model_formula,
  confounding = TRUE,
  center = FALSE
)
algdesign_evaluation <- label_algdesign_confounding_matrix(algdesign_evaluation)
selected_evaluation <- evaluate_block_summary(
  blocked_design = blocked_design,
  set_size = chosen_block_size,
  formula = model_formula,
  algdesign_evaluation = algdesign_evaluation
)

print_selected_block_design_evaluation(selected_evaluation)
print_algdesign_block_evaluation(
  evaluation = algdesign_evaluation,
  set_size = chosen_block_size,
  n_sets = length(blocked_design$Blocks)
)

canonical_workbook <- file.path(path_outputs, "vignette_sets.xlsx")
saveRDS(blocked_design, file.path(path_outputs, "blocked_design.rds"))
save_blocked_sets_to_excel(blocked_design, selected_evaluation, canonical_workbook)

integrity <- check_blocked_design_integrity(full_design, blocked_design)
print_blocked_design_integrity(integrity)
workbook_integrity <- check_vignette_set_workbook_integrity(
  full_design,
  canonical_workbook
)
print_vignette_set_workbook_integrity(workbook_integrity)
message("Selected blocked-design evaluation complete. Chosen block size: ", chosen_block_size)
