# ==============================================================================
# Script: 00_setup.R
# Purpose: Define shared paths, configuration, and package checks.
# Run workflow scripts from the repository root.
# ==============================================================================

base_path <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
required_root_dirs <- c("app", "config", "R", "scripts", "vignette_content")
missing_root_dirs <- required_root_dirs[
  !dir.exists(file.path(base_path, required_root_dirs))
]
if (length(missing_root_dirs) > 0) {
  stop(
    "Set the working directory to the BLOCKS repository root. Missing: ",
    paste(missing_root_dirs, collapse = ", ")
  )
}

require_workflow_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop(
      "Missing R package(s): ", paste(missing, collapse = ", "),
      ". Install them with install.packages()."
    )
  }
}

path_scripts <- file.path(base_path, "scripts")
path_config <- file.path(base_path, "config")
path_R <- file.path(base_path, "R")
path_helpers <- file.path(path_R, "helpers")
path_design <- path_R
path_text_fragments <- file.path(path_R, "text_fragments")
path_generated_vignettes <- file.path(path_R, "generated_vignettes")
path_app_vignettes <- file.path(base_path, "vignette_content")
path_monitoring <- file.path(path_R, "Database monitoring after app deployement")

source(file.path(path_config, "workflow_config.R"))

workflow_paths <- list(
  base_path = base_path,
  path_scripts = path_scripts,
  path_config = path_config,
  path_R = path_R,
  path_helpers = path_helpers,
  path_design = path_design,
  path_text_fragments = path_text_fragments,
  path_generated_vignettes = path_generated_vignettes,
  path_app_vignettes = path_app_vignettes,
  path_monitoring = path_monitoring
)
