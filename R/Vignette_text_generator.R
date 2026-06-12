#--------------------------------------------------------------
# Title: Vignette Text Generator
# Author: ??
# Date: ??
# Institution: ??
#--------------------------------------------------------------
#
# Description:
# This script:
#  1. Loads the full factorial design and blocked vignette sets
#  2. Loads vignette text fragments stored as .txt files
#  3. Loads ALSO static text fragments (non-manipulated)
#  4. Merges text in ANY order specified by the researcher
#  5. Generates vignette .txt files grouped into vignette-set folders
#
# Safety/robustness features:
#  - PLACEHOLDER/scaffold creation is OFF by default (won't overwrite your real files)
#  - When scaffold creation is ON, files are created ONLY if missing
#  - Optional "fail fast" check prevents generating vignettes with placeholder text
#--------------------------------------------------------------

#--------------------------------------------------------------
# 0. Settings
#--------------------------------------------------------------
CREATE_PLACEHOLDERS <- FALSE
FAIL_ON_PLACEHOLDERS <- FALSE  # Placeholder content is intentional in this example repository

#--------------------------------------------------------------
# 1. Load packages
#--------------------------------------------------------------
if (!require("pacman")) install.packages("pacman")
pacman::p_load(
  tidyverse,
  openxlsx,
  stringr,
  readr
)

#--------------------------------------------------------------
# 2. File paths
#--------------------------------------------------------------
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
base_path <- if (length(script_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", script_arg[[1]])))
} else {
  normalizePath("R", mustWork = TRUE)
}
repository_path <- dirname(base_path)

full_design_file <- file.path(base_path, "full_factorial_design.RData")
vignette_sets    <- file.path(base_path, "vignette_sets_size_4.xlsx")

fragment_base_path <- file.path(base_path, "text_fragments")
output_paths <- c(
  file.path(base_path, "generated_vignettes"),
  file.path(repository_path, "vignette_content")
)

for (output_path in output_paths) {
  dir.create(output_path, showWarnings = FALSE, recursive = TRUE)
  old_set_dirs <- Sys.glob(file.path(output_path, "Set_*"))
  if (length(old_set_dirs) > 0) {
    unlink(old_set_dirs, recursive = TRUE, force = TRUE)
  }
}

#--------------------------------------------------------------
# 3. Optional: scaffold folders + placeholder .txt files (SAFE)
#--------------------------------------------------------------

#--- 3.1 Function: Generate factor folders + placeholder files ----------------
generate_factor_folders <- function(base_path, factor_specs) {
  
  for (factor_name in names(factor_specs)) {
    
    levels <- factor_specs[[factor_name]]
    
    # Create folder for factor if it doesn't exist
    factor_folder <- file.path(base_path, factor_name)
    dir.create(factor_folder, showWarnings = FALSE, recursive = TRUE)
    
    # Create placeholder .txt files for each factor level ONLY if missing
    for (lvl in levels) {
      fp <- file.path(factor_folder, paste0(factor_name, lvl, ".txt"))
      
      if (!file.exists(fp)) {
        placeholder_text <- paste0("[", factor_name, lvl, " – Placeholder tekst]")
        writeLines(placeholder_text, fp)
      }
    }
  }
}

#--- 3.2 Scaffold block (OFF by default) --------------------------------------
static_folder <- file.path(fragment_base_path, "static")
dir.create(static_folder, showWarnings = FALSE, recursive = TRUE)

if (CREATE_PLACEHOLDERS) {
  
  message("CREATE_PLACEHOLDERS = TRUE -> creating missing folders/files (no overwrites).")
  
  # Placeholder files for static text (ONLY created if missing)
  static_templates <- list(
    S1 = "S1 – Klasseoplysninger (ret tekst)\n\n[fx: Klassen består af 22 elever med forskellige forudsætninger.]",
    S2 = "S2 – Skolekontekst (ret tekst)\n\n[fx: Undervisningen foregår i en almindelig dansk folkeskole.]",
    S3 = "S3 – Fag og lektionsramme (ret tekst)\n\n[fx: Lektionen handler om danskfaglige kompetencer.]"
  )
  
  for (nm in names(static_templates)) {
    target <- file.path(static_folder, paste0(nm, ".txt"))
    if (!file.exists(target)) {
      write_file(static_templates[[nm]], target)
    }
  }
  
  # Create factor folders/files
  factor_specs <- list(
    A = 1:2,
    B = 1:2,
    C = 1:3,
    D = 1:2,
    E = 1:2,
    F = 1:2
  )
  
  generate_factor_folders(fragment_base_path, factor_specs)
}

#--------------------------------------------------------------
# 4. Load full factorial design (A–F + id)
#--------------------------------------------------------------
if (!file.exists(full_design_file)) stop("Missing file: ", full_design_file)
load(full_design_file)

if (!exists("full_design")) {
  stop("Loaded .RData but object `full_design` was not found. Check your saved object name.")
}
if (!"id" %in% names(full_design)) stop("`full_design` must contain an `id` column.")

#--------------------------------------------------------------
# 5. Load vignette-set definitions
#--------------------------------------------------------------
if (!file.exists(vignette_sets)) stop("Missing file: ", vignette_sets)
set_names <- openxlsx::getSheetNames(vignette_sets)

#--------------------------------------------------------------
# 6. Helper: Load factor-text fragments
#--------------------------------------------------------------
read_factor_texts <- function(folder, prefix, levels) {
  
  missing <- levels[!file.exists(file.path(folder, paste0(prefix, levels, ".txt")))]
  if (length(missing) > 0) {
    stop(
      "Missing factor text files in folder: ", folder, "\n",
      "Missing: ", paste0(prefix, missing, ".txt", collapse = ", ")
    )
  }
  
  tibble(
    level = levels,
    text  = map_chr(
      levels,
      ~ read_file(file.path(folder, paste0(prefix, .x, ".txt")))
    )
  )
}

#--------------------------------------------------------------
# 7. Load all varying factor text fragments (A–F)
#--------------------------------------------------------------
text_list <- list(
  A = read_factor_texts(file.path(fragment_base_path, "A"), "A", 1:2),
  B = read_factor_texts(file.path(fragment_base_path, "B"), "B", 1:2),
  C = read_factor_texts(file.path(fragment_base_path, "C"), "C", 1:3),
  D = read_factor_texts(file.path(fragment_base_path, "D"), "D", 1:2),
  E = read_factor_texts(file.path(fragment_base_path, "E"), "E", 1:2),
  F = read_factor_texts(file.path(fragment_base_path, "F"), "F", 1:2)
)

#--------------------------------------------------------------
# 8. Load header + static text fragments
#--------------------------------------------------------------
header_file <- file.path(fragment_base_path, "header.txt")
header_text <- if (file.exists(header_file)) read_file(header_file) else ""

static_files <- list.files(static_folder, pattern = "\\.txt$", full.names = TRUE)

if (length(static_files) == 0) {
  stop("No static .txt files found in: ", static_folder)
}

static_texts <- tibble(
  name = basename(static_files) |> str_remove("\\.txt$"),
  text = map_chr(static_files, read_file)
)

# Optional: Fail fast if any static file still looks like a placeholder
if (FAIL_ON_PLACEHOLDERS) {
  bad_static <- static_texts %>%
    filter(str_detect(text, "Placeholder|ret tekst|\\[fx:"))
  
  if (nrow(bad_static) > 0) {
    stop(
      paste0(
        "These static files still look like placeholders: ",
        paste(bad_static$name, collapse = ", "),
        "\nEdit them in: ", static_folder,
        "\nOr set FAIL_ON_PLACEHOLDERS <- FALSE."
      )
    )
  }
}

#--------------------------------------------------------------
# 9. DECLARE THE MERGE ORDER (FULL CONTROL HERE)
#--------------------------------------------------------------
merge_order <- c(
  "header",
  "S1",
  "S2",
  "S3",
  "A",
  "B",
  "C",
  "D",
  "E",
  "F"
)

# Validate merge_order keys early
valid_keys <- c("header", static_texts$name, names(text_list))
unknown_keys <- setdiff(merge_order, valid_keys)
if (length(unknown_keys) > 0) {
  stop("Unknown merge_order key(s): ", paste(unknown_keys, collapse = ", "))
}

#--------------------------------------------------------------
# 10. Helper: Fetch correct text fragment
#--------------------------------------------------------------
get_fragment_text <- function(element, row_data) {
  
  # Header
  if (element == "header") return(header_text)
  
  # Static text (e.g., S1, S2, S3)
  if (element %in% static_texts$name) {
    return(static_texts$text[static_texts$name == element] |> as.character())
  }
  
  # Factor-based text (A–F)
  if (element %in% names(text_list)) {
    lvl <- row_data[[element]]
    return(text_list[[element]]$text[text_list[[element]]$level == lvl] |> as.character())
  }
  
  stop(paste("Unknown merge-order key:", element))
}

#--------------------------------------------------------------
# 11. Construct full vignette text following merge_order
#--------------------------------------------------------------
construct_vignette_text <- function(row_data, merge_order) {
  
  fragments <- map_chr(
    merge_order,
    ~ get_fragment_text(.x, row_data)
  )
  
  paste(fragments, collapse = "\n\n")
}

#--------------------------------------------------------------
# 12. Generate all vignette text files for each set
#--------------------------------------------------------------
for (set_name in set_names) {
  set_data <- openxlsx::read.xlsx(vignette_sets, sheet = set_name)
  
  if (!"id" %in% names(set_data)) {
    stop("Sheet '", set_name, "' must contain an `id` column.")
  }
  
  for (i in 1:nrow(set_data)) {
    
    vign_id <- set_data$id[i]
    
    row_data <- full_design %>% filter(id == vign_id)
    if (nrow(row_data) != 1) {
      stop("Could not uniquely match vignette id = ", vign_id, " in `full_design`.")
    }
    
    vignette_text <- construct_vignette_text(row_data, merge_order)
    
    for (output_path in output_paths) {
      set_folder <- file.path(output_path, set_name)
      dir.create(set_folder, showWarnings = FALSE, recursive = TRUE)
      out_file <- file.path(set_folder, paste0("vignette_", vign_id, ".txt"))
      writeLines(vignette_text, out_file)
    }
  }
}

cat("\n-----------------------------------------\n")
cat("Vignette text generation complete.\n")
cat("Output folders:\n")
cat(paste0(" - ", output_paths, collapse = "\n"), "\n")
cat("-----------------------------------------\n")

