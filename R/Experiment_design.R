# Description:
# This script generates a full-factorial vignette design, 
# constructs blocked vignette sets using AlgDesign,
# evaluates confounding structure across multiple block sizes,
# and saves output files and integrity checks.
#--------------------------------------------------------------

#--------------------------------------------------------------
# 1. Load packages
#--------------------------------------------------------------
if (!require("pacman")) install.packages("pacman")
pacman::p_load(
  AlgDesign,
  openxlsx,
  tidyverse
)

#--------------------------------------------------------------
# 2. File paths
#--------------------------------------------------------------
file_path_xlsx  <- "YOURFILEPATH"
file_path_rdata <- "YOURFILEPATH"

setwd(file_path_xlsx)

#--------------------------------------------------------------
# 3. Vignette factors - EXAMPLE
#--------------------------------------------------------------
levels.design <- c(
  2,  # A ??
  2,  # B 
  3,  # C 
  2,  # D 
  2,  # E 
  2   # F
)

#--------------------------------------------------------------
# 4. Full factorial design (96 vignettes)
#--------------------------------------------------------------
full_design <- gen.factorial(
  levels.design,
  nVars = 6,
  factors = "all"
)

colnames(full_design) <- c("A","B","C","D","E","F")
full_design$id <- seq_len(nrow(full_design))

#--------------------------------------------------------------
# 5. Helper functions
#--------------------------------------------------------------

save_full_design_to_excel <- function(df, path){
  wb <- createWorkbook()
  addWorksheet(wb, "Full_factorial")
  writeData(wb, "Full_factorial", df)
  setColWidths(wb, sheet = 1, cols = 1:ncol(df), widths = "auto")
  saveWorkbook(wb, path, overwrite = TRUE)
}

save_blocked_sets_to_excel <- function(blocked, path){
  wb <- createWorkbook()
  for(i in seq_along(blocked$Blocks)){
    addWorksheet(wb, paste0("Set_", i))
    writeData(wb, paste0("Set_", i), blocked$Blocks[[i]])
  }
  saveWorkbook(wb, path, overwrite = TRUE)
}

evaluate_block <- function(blocked_design, set_size){
  conf <- eval.blockdesign(
    frml = ~ A + B + C + D + E + F,
    design = blocked_design$design,
    blocksizes = rep(set_size, nrow(blocked_design$design) / set_size),
    center = FALSE,
    confounding = TRUE
  )
  
  # summarize confounding matrix
  conf_matrix <- conf$confounding
  avg_conf <- mean(abs(conf_matrix[lower.tri(conf_matrix)]))
  max_conf <- max(abs(conf_matrix[lower.tri(conf_matrix)]))
  
  tibble(
    set_size       = set_size,
    D_eff          = conf$within.block.efficiencies["lambda.det"],
    A_eff          = conf$within.block.efficiencies["lambda.trace"],
    rho            = conf$within.block.efficiencies["rho"],
    determinant    = conf$determinant.all.terms.within.terms.centered,
    avg_confound   = avg_conf,
    max_confound   = max_conf
  )
}

check_data_integrity_xlsx <- function(df, xlsx_path, sheet = "Full_factorial") {
  # Read back from Excel
  x <- openxlsx::read.xlsx(xlsx_path, sheet = sheet)
  
  # Helper: normalise types for robust comparison
  normalise <- function(d) {
    d <- as.data.frame(d, stringsAsFactors = FALSE)
    
    # Ensure same column order as df (if possible)
    common <- intersect(names(df), names(d))
    d <- d[, common, drop = FALSE]
    
    # Coerce character-like to character; keep numeric as numeric where possible
    for (nm in names(d)) {
      if (is.factor(d[[nm]])) d[[nm]] <- as.character(d[[nm]])
    }
    d
  }
  
  df_n <- normalise(df)
  x_n  <- normalise(x)
  
  # Basic structure checks
  same_nrow  <- nrow(df_n) == nrow(x_n)
  same_ncol  <- ncol(df_n) == ncol(x_n)
  same_names <- identical(names(df_n), names(x_n))
  
  # ID check if present
  id_ok <- NA
  if ("id" %in% names(df_n) && "id" %in% names(x_n)) {
    id_ok <- identical(as.integer(df_n$id), as.integer(x_n$id))
  }
  
  # Cell-by-cell equality (after coercions)
  # Convert to character matrix for strict equality across types
  df_mat <- as.matrix(data.frame(lapply(df_n, as.character), check.names = FALSE))
  x_mat  <- as.matrix(data.frame(lapply(x_n,  as.character), check.names = FALSE))
  
  same_cells <- identical(df_mat, x_mat)
  
  # If not identical, count mismatches
  mismatch_n <- NA_integer_
  if (same_nrow && same_ncol && same_names) {
    mismatch_n <- sum(df_mat != x_mat, na.rm = TRUE)
  }
  
  list(
    file_exists   = file.exists(xlsx_path),
    same_nrow     = same_nrow,
    same_ncol     = same_ncol,
    same_colnames = same_names,
    id_matches    = id_ok,
    identical_all_cells = same_cells,
    n_cell_mismatches   = mismatch_n
  )
}
#----------------------------------------------------------------------------------------
# 6. Generate blocked designs and compare quality (in this example 3, 4, 6 per set)
#----------------------------------------------------------------------------------------

block_sizes <- c(3, 4, 6)

blocked_designs <- list()

for (s in block_sizes) {
  num_sets <- 96 / s
  
  blocked_designs[[paste0("size", s)]] <- optBlock(
    frml = ~ A + B + C + D + E + F,
    withinData = full_design,
    blocksizes = rep(s, num_sets),
    criterion = "D",
    nRepeats = 500,
    center = FALSE
  )
}

#--------------------------------------------------------------
# 7. Compare confounding and efficiency across block sizes
#--------------------------------------------------------------
comparison_results <- map_dfr(
  block_sizes,
  ~ evaluate_block(
    blocked_designs[[paste0("size", .x)]],
    set_size = .x
  )
)

print(comparison_results)

#--------------------------------------------------------------
# 8. Save primary chosen blocked design (In this eample, set size = 4)
#--------------------------------------------------------------
chosen_size <- 4

blocked_design <- blocked_designs[[paste0("size", chosen_size)]]
combined_design <- bind_rows(blocked_design$Blocks)

save(full_design, blocked_design, combined_design,
     file = file.path(file_path_rdata, "full_factorial_design.RData"))

save_full_design_to_excel(
  full_design,
  file.path(file_path_xlsx, "full_factorial_design.xlsx")
)

save_blocked_sets_to_excel(
  blocked_design,
  file.path(file_path_xlsx, paste0("vignette_sets_size_", chosen_size, ".xlsx"))
)

#--------------------------------------------------------------
# 9. Integrity checks
#--------------------------------------------------------------
print("Checking Excel integrity of full factorial design:")
print(check_data_integrity_xlsx(
  full_design,
  file.path(file_path_xlsx, "full_factorial_design.xlsx")
))

print("Design generation complete.")

#--------------------------------------------------------------
# End of script
#--------------------------------------------------------------

