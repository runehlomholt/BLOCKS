
# Description:
# This script:
#  1. Loads the full factorial design and blocked vignette sets
#  2. Loads vignette text fragments stored as .txt files
#  3. Loads ALSO static text fragments (non-manipulated)
#  4. Merges text in ANY order specified by the researcher
#  5. Generates vignette .txt files grouped into vignette-set folders
#--------------------------------------------------------------


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
base_path <- "YOURFILEPATH"
setwd(base_path)

full_design_file   <- file.path(base_path, "full_factorial_design.RData")
vignette_sets_file <- file.path(base_path, "vignette_sets.xlsx")

fragment_base_path <- file.path(base_path, "text_fragments")
output_path        <- file.path(base_path, "generated_vignettes")

dir.create(output_path, showWarnings = FALSE)


#-----------------------------------------------------------------------------
# 3. AUTO-GENERATE STATIC FOLDER AND FACTOR FOLDERS + PLACEHOLDER .TXT FILES
#-----------------------------------------------------------------------------

#--- 3.1 Create static folder -------------------------------------------------
static_folder <- file.path(fragment_base_path, "static")
dir.create(static_folder, showWarnings = FALSE)

# Placeholder files for static text
static_templates <- list(
  S1 = "S1 – EXAMPLETEXT\n\n[EXAMPLETEXT]",
  S2 = "S2 – EXAMPLETEXT\n\n[EXAMPLETEXT]",
  S3 = "S3 – EXAMPLETEXT\n\n[EXAMPLETEXT]"
)

for (nm in names(static_templates)) {
  write_file(
    static_templates[[nm]],
    file.path(static_folder, paste0(nm, ".txt"))
  )
}

#--- 3.2 Function: Generate factor folders + placeholder files ----------------
generate_factor_folders <- function(base_path, factor_specs) {
  
  for (factor_name in names(factor_specs)) {
    
    levels <- factor_specs[[factor_name]]
    
    # Create folder for factor if it doesn't exist
    factor_folder <- file.path(base_path, factor_name)
    dir.create(factor_folder, showWarnings = FALSE)
    
    # Create placeholder .txt files for each factor level
    for (lvl in levels) {
      file_path <- file.path(factor_folder, paste0(factor_name, lvl, ".txt"))
      
      if (!file.exists(file_path)) {
        placeholder_text <- paste0("[", factor_name, lvl, " – Placeholder tekst]")
        writeLines(placeholder_text, file_path)
      }
    }
  }
}

#--- 3.3 Define factor structure + run generator ------------------------------
factor_specs <- list(
  A = 1:2,
  B = 1:2,
  C = 1:3,
  D = 1:2,
  E = 1:2,
  F = 1:2
)

generate_factor_folders(fragment_base_path, factor_specs)

#--------------------------------------------------------------
# 4. Load full factorial design (A–F + id)
#--------------------------------------------------------------
load(full_design_file)


#--------------------------------------------------------------
# 5. Load vignette-set definitions
#--------------------------------------------------------------
set_names <- openxlsx::getSheetNames(vignette_sets_file)


#--------------------------------------------------------------
# 6. Helper: Load factor-text fragments
#--------------------------------------------------------------
read_factor_texts <- function(folder, prefix, levels){
  tibble(
    level = levels,
    text = map_chr(
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

static_texts <- tibble(
  name = basename(static_files) |> str_remove(".txt"),
  text = map_chr(static_files, read_file)
)


#--------------------------------------------------------------
# 9. DECLARE THE MERGE ORDER (FULL CONTROL HERE)
#--------------------------------------------------------------
# YOU CAN CHANGE THIS ORDER AS YOU WISH.
merge_order <- c(
  "header",
  "S1",
  "S2",
  "A",
  "B",
  "C",
  "S3",
  "D",
  "E",
  "F"
)


#--------------------------------------------------------------
# 10. Helper: Fetch correct text fragment
#--------------------------------------------------------------
get_fragment_text <- function(element, row_data){
  
  # Header
  if (element == "header") return(header_text)
  
  # Static text (e.g., S1, S2, S3)
  if (element %in% static_texts$name) {
    return(static_texts$text[static_texts$name == element])
  }
  
  # Factor-based text (A–F)
  if (element %in% names(text_list)) {
    lvl <- row_data[[element]]
    return(text_list[[element]]$text[text_list[[element]]$level == lvl])
  }
  
  stop(paste("Unknown merge-order key:", element))
}


#--------------------------------------------------------------
# 11. Construct full vignette text following merge_order
#--------------------------------------------------------------
construct_vignette_text <- function(row_data, merge_order){
  
  fragments <- map_chr(
    merge_order,
    ~ get_fragment_text(.x, row_data)
  )
  
  vignette <- paste(fragments, collapse = "\n\n")
  return(vignette)
}


#--------------------------------------------------------------
# 12. Generate all vignette text files for each set
#--------------------------------------------------------------
for (s in seq_along(set_names)) {
  
  set_name <- set_names[s]
  
  # Create folder for this vignette set
  set_folder <- file.path(output_path, set_name)
  dir.create(set_folder, showWarnings = FALSE)
  
  # Read vignette IDs for this set
  set_data <- openxlsx::read.xlsx(vignette_sets_file, sheet = set_name)
  
  # Loop over vignette rows
  for (i in 1:nrow(set_data)) {
    
    vign_id  <- set_data$id[i]
    row_data <- full_design %>% filter(id == vign_id)
    
    vignette_text <- construct_vignette_text(row_data, merge_order)
    
    # Write output file
    writeLines(
      vignette_text,
      file.path(set_folder, paste0("vignette_", vign_id, ".txt"))
    )
  }
}

cat("\n-----------------------------------------\n")
cat("Vignette text generation complete.\n")
cat("-----------------------------------------\n")

