# ==============================================================================
# Script: 01b_generate_factorial_design.R
# Purpose: Generate and export the full factorial vignette universe.
# ==============================================================================

source(file.path("scripts", "00_setup.R"))
require_workflow_packages(c("AlgDesign", "openxlsx", "tibble"))
print_study_design_summary <- FALSE
source(file.path(path_scripts, "01a_define_study_design.R"))
source(file.path(path_helpers, "design_helpers.R"))

full_design <- AlgDesign::gen.factorial(
  levels_design,
  nVars = length(levels_design),
  factors = "all"
)
full_design <- as.data.frame(full_design)
colnames(full_design) <- factor_names
full_design$id <- seq_len(nrow(full_design))

saveRDS(full_design, file.path(path_design, "full_factorial_design.rds"))
save(full_design, file = file.path(path_design, "full_factorial_design.RData"))
save_full_design_to_excel(
  full_design,
  file.path(path_design, "full_factorial_design.xlsx")
)
message("Full factorial design created with ", nrow(full_design), " vignettes.")
