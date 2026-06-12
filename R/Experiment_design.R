# Compatibility entry point.
# Prefer: Rscript scripts/run_design_workflow.R

source(file.path("scripts", "01b_generate_factorial_design.R"))
source(file.path("scripts", "01c_construct_and_evaluate_vignette_sets.R"))
