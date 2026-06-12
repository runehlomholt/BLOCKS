#--------------------------------------------------------------
# Title: Full-Factorial Vignette Design and Blocking Script
#--------------------------------------------------------------
#
# Purpose:
# This script:
#   1. Generates a full-factorial vignette design from user-specified factors
#   2. Creates blocked vignette sets using AlgDesign
#   3. Evaluates confounding and efficiency across candidate block sizes
#   4. Saves output files and runs a simple integrity check
#
# How to use:
#   1. Set `project_dir` below to your project folder
#   2. Adjust `levels_design` to match the number of levels for each factor
#   3. Adjust `candidate_block_sizes` as needed
#   4. Set `chosen_size` to the preferred final block size
#   5. Run the script
#
# Expected outputs:
#   - full_factorial_design.RData
#   - full_factorial_design.xlsx
#   - vignette_sets_size_<chosen_size>.xlsx
#
# Notes:
#   - The script uses generic factor labels A-F by default
#   - If you want descriptive factor names, modify `factor_names`
#   - No working-directory changes are required
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
# 2. User settings: paths and design choices
#--------------------------------------------------------------

# Store generated design artifacts beside this script. This works when the
# script is run from the repository root with `Rscript R/Experiment_design.R`.
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
project_dir <- if (length(script_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", script_arg[[1]])))
} else {
  normalizePath("R", mustWork = TRUE)
}

# Create output folder if needed
dir.create(project_dir, showWarnings = FALSE, recursive = TRUE)

# Output paths
file_path_xlsx  <- project_dir
file_path_rdata <- project_dir

# Number of levels for each factor
# Illustrative BLOCKS example:
#   A = 2 levels
#   B = 2 levels
#   C = 3 levels
#   D = 2 levels
#   E = 2 levels
#   F = 2 levels
levels_design <- c(2, 2, 3, 2, 2, 2)

# Factor names used in the design matrix
factor_names <- c("A", "B", "C", "D", "E", "F")

# Candidate block sizes to compare
candidate_block_sizes <- c(4)

# Final selected block size for export
chosen_size <- 4

# Number of repeated optimisation attempts used by AlgDesign
n_repeats <- as.integer(Sys.getenv("BLOCK_OPTIMISATION_REPEATS", "200"))

# Make the illustrative design reproducible across regenerations.
set.seed(20260612)

#--------------------------------------------------------------
# 3. Generate full-factorial design
#--------------------------------------------------------------
full_design <- gen.factorial(
  levels_design,
  nVars = length(levels_design),
  factors = "all"
)

colnames(full_design) <- factor_names
full_design$id <- seq_len(nrow(full_design))

#--------------------------------------------------------------
# 4. Helper functions
#--------------------------------------------------------------

save_full_design_to_excel <- function(df, path) {
  wb <- createWorkbook()
  addWorksheet(wb, "Full_factorial")
  writeData(wb, "Full_factorial", df)
  setColWidths(wb, sheet = 1, cols = 1:ncol(df), widths = "auto")
  saveWorkbook(wb, path, overwrite = TRUE)
}

save_blocked_sets_to_excel <- function(blocked, path) {
  wb <- createWorkbook()
  for (i in seq_along(blocked$Blocks)) {
    addWorksheet(wb, paste0("Set_", i))
    writeData(wb, paste0("Set_", i), blocked$Blocks[[i]])
  }
  saveWorkbook(wb, path, overwrite = TRUE)
}

check_data_integrity_xlsx <- function(df, xlsx_path, sheet = "Full_factorial") {
  x <- openxlsx::read.xlsx(xlsx_path, sheet = sheet)

  normalise <- function(d) {
    d <- as.data.frame(d, stringsAsFactors = FALSE)

    common <- intersect(names(df), names(d))
    d <- d[, common, drop = FALSE]

    for (nm in names(d)) {
      if (is.factor(d[[nm]])) d[[nm]] <- as.character(d[[nm]])
    }

    d
  }

  df_n <- normalise(df)
  x_n  <- normalise(x)

  same_nrow  <- nrow(df_n) == nrow(x_n)
  same_ncol  <- ncol(df_n) == ncol(x_n)
  same_names <- identical(names(df_n), names(x_n))

  id_ok <- NA
  if ("id" %in% names(df_n) && "id" %in% names(x_n)) {
    id_ok <- identical(as.integer(df_n$id), as.integer(x_n$id))
  }

  df_mat <- as.matrix(data.frame(lapply(df_n, as.character), check.names = FALSE))
  x_mat  <- as.matrix(data.frame(lapply(x_n,  as.character), check.names = FALSE))

  same_cells <- identical(df_mat, x_mat)

  mismatch_n <- NA_integer_
  if (same_nrow && same_ncol && same_names) {
    mismatch_n <- sum(df_mat != x_mat, na.rm = TRUE)
  }

  list(
    file_exists          = file.exists(xlsx_path),
    same_nrow            = same_nrow,
    same_ncol            = same_ncol,
    same_colnames        = same_names,
    id_matches           = id_ok,
    identical_all_cells  = same_cells,
    n_cell_mismatches    = mismatch_n
  )
}

# Build formula dynamically from factor names
build_main_effects_formula <- function(factor_names) {
  reformulate(factor_names)
}

evaluate_block <- function(blocked_design, set_size, factor_names) {
  frml <- build_main_effects_formula(factor_names)

  conf <- eval.blockdesign(
    frml = frml,
    design = blocked_design$design,
    blocksizes = rep(set_size, nrow(blocked_design$design) / set_size),
    center = FALSE,
    confounding = TRUE
  )

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

get_model_matrix_names <- function(df, factor_names) {
  colnames(model.matrix(build_main_effects_formula(factor_names), data = df))
}

ensure_named_matrix <- function(cm, fallback_names = NULL) {
  cm <- as.matrix(cm)

  if (!is.null(fallback_names) &&
      nrow(cm) == length(fallback_names) &&
      ncol(cm) == length(fallback_names)) {
    rownames(cm) <- fallback_names
    colnames(cm) <- fallback_names
  } else {
    if (is.null(rownames(cm))) rownames(cm) <- paste0("V", seq_len(nrow(cm)))
    if (is.null(colnames(cm))) colnames(cm) <- paste0("V", seq_len(ncol(cm)))
  }

  cm
}

extract_efficiencies <- function(conf_obj) {
  eff <- conf_obj$within.block.efficiencies

  if (is.null(eff)) return(numeric(0))

  vals <- as.numeric(eff)
  names(vals) <- names(eff)
  vals
}

term_to_factor <- function(term, factor_names) {
  if (term == "(Intercept)") return("(Intercept)")

  pattern <- paste0("^(", paste(factor_names, collapse = "|"), ").*$")
  out <- sub(pattern, "\\1", term)

  ifelse(out %in% factor_names, out, term)
}

top_alias_pairs <- function(conf_matrix, design_label, top_n = 10) {
  cm <- as.matrix(conf_matrix)
  diag(cm) <- NA_real_

  idx <- which(upper.tri(cm), arr.ind = TRUE)

  tibble(
    design = design_label,
    term_1 = rownames(cm)[idx[, 1]],
    term_2 = colnames(cm)[idx[, 2]],
    alias = cm[idx],
    abs_alias = abs(cm[idx])
  ) %>%
    filter(!is.na(abs_alias)) %>%
    arrange(desc(abs_alias), term_1, term_2) %>%
    slice_head(n = top_n)
}

factor_alias_burden <- function(conf_matrix, design_label, factor_names) {
  cm <- as.matrix(conf_matrix)
  diag(cm) <- NA_real_

  idx <- which(upper.tri(cm), arr.ind = TRUE)

  pairs <- tibble(
    term_1 = rownames(cm)[idx[, 1]],
    term_2 = colnames(cm)[idx[, 2]],
    abs_alias = abs(cm[idx])
  ) %>%
    filter(!is.na(abs_alias))

  bind_rows(
    pairs %>%
      mutate(factor = vapply(term_1, term_to_factor, character(1), factor_names = factor_names)) %>%
      select(factor, abs_alias),
    pairs %>%
      mutate(factor = vapply(term_2, term_to_factor, character(1), factor_names = factor_names)) %>%
      select(factor, abs_alias)
  ) %>%
    group_by(factor) %>%
    summarise(
      mean_abs_alias = mean(abs_alias, na.rm = TRUE),
      max_abs_alias  = max(abs_alias, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(design = design_label) %>%
    select(design, factor, mean_abs_alias, max_abs_alias) %>%
    arrange(desc(max_abs_alias), desc(mean_abs_alias), factor)
}

term_r2_aliasing <- function(df, design_label, factor_names) {
  X <- as.data.frame(model.matrix(build_main_effects_formula(factor_names), data = df))

  if ("(Intercept)" %in% names(X)) {
    X <- X[, setdiff(names(X), "(Intercept)"), drop = FALSE]
  }

  map_dfr(names(X), function(target_term) {
    other_terms <- setdiff(names(X), target_term)

    fit <- lm(
      reformulate(other_terms, response = target_term),
      data = X
    )

    tibble(
      design = design_label,
      term = target_term,
      factor = term_to_factor(target_term, factor_names),
      R2_with_other_terms = summary(fit)$r.squared
    )
  }) %>%
    arrange(desc(R2_with_other_terms), term)
}

evaluate_block_deep <- function(blocked_design, set_size, factor_names) {
  frml <- build_main_effects_formula(factor_names)

  conf <- eval.blockdesign(
    frml = frml,
    design = blocked_design$design,
    blocksizes = rep(set_size, nrow(blocked_design$design) / set_size),
    center = FALSE,
    confounding = TRUE
  )

  design_label <- paste0("size", set_size)

  true_names <- get_model_matrix_names(blocked_design$design, factor_names)

  cm <- ensure_named_matrix(conf$confounding, fallback_names = true_names)
  diag(cm) <- NA_real_

  avg_conf <- mean(abs(cm), na.rm = TRUE)
  max_conf <- max(abs(cm), na.rm = TRUE)

  eff <- extract_efficiencies(conf)

  D_eff <- NA_real_
  A_eff <- NA_real_

  if (length(eff) > 0) {
    eff_names <- names(eff)

    if (!is.null(eff_names) && any(nzchar(eff_names))) {
      d_match <- eff[grepl("lambda\\.det|det", eff_names, ignore.case = TRUE)]
      a_match <- eff[grepl("lambda\\.trace|trace", eff_names, ignore.case = TRUE)]

      if (length(d_match) > 0) D_eff <- unname(d_match[1])
      if (length(a_match) > 0) A_eff <- unname(a_match[1])
    }

    if (is.na(D_eff) && length(eff) >= 1) D_eff <- unname(eff[1])
    if (is.na(A_eff) && length(eff) >= 2) A_eff <- unname(eff[2])
  }

  list(
    summary = tibble(
      design       = design_label,
      set_size     = set_size,
      n_sets       = length(blocked_design$Blocks),
      n_vignettes  = nrow(blocked_design$design),
      D_eff        = D_eff,
      A_eff        = A_eff,
      determinant  = conf$determinant.all.terms.within.terms.centered,
      avg_confound = avg_conf,
      max_confound = max_conf
    ),
    top_alias = top_alias_pairs(cm, design_label, top_n = 10),
    factor_burden = factor_alias_burden(cm, design_label, factor_names),
    term_r2 = term_r2_aliasing(blocked_design$design, design_label, factor_names),
    confounding_matrix = cm,
    raw_efficiencies = eff
  )
}

#--------------------------------------------------------------
# 5. Generate blocked designs for candidate block sizes
#--------------------------------------------------------------
blocked_designs <- list()
frml <- build_main_effects_formula(factor_names)

for (s in candidate_block_sizes) {
  if (nrow(full_design) %% s != 0) {
    stop("Block size ", s, " does not divide the full design exactly.")
  }

  num_sets <- nrow(full_design) / s

  blocked_designs[[paste0("size", s)]] <- optBlock(
    frml = frml,
    withinData = full_design,
    blocksizes = rep(s, num_sets),
    criterion = "D",
    nRepeats = n_repeats,
    center = FALSE
  )

  cat(
    "Set size =", s,
    "| Number of sets =", length(blocked_designs[[paste0("size", s)]]$Blocks),
    "| Number of selected rows =", nrow(blocked_designs[[paste0("size", s)]]$design),
    "\n"
  )
}

#--------------------------------------------------------------
# 6. Compare confounding and efficiency across block sizes
#--------------------------------------------------------------
deep_results <- map(
  candidate_block_sizes,
  ~ evaluate_block_deep(
    blocked_designs[[paste0("size", .x)]],
    set_size = .x,
    factor_names = factor_names
  )
)

names(deep_results) <- paste0("size", candidate_block_sizes)

comparison_results <- bind_rows(map(deep_results, "summary")) %>%
  mutate(
    across(c(D_eff, A_eff, determinant, avg_confound, max_confound), ~ round(.x, 4))
  ) %>%
  arrange(set_size)

cat("\n================ OVERALL DESIGN COMPARISON ================\n")
print(comparison_results)

top_alias_results <- bind_rows(map(deep_results, "top_alias")) %>%
  mutate(
    alias = round(alias, 4),
    abs_alias = round(abs_alias, 4)
  ) %>%
  arrange(design, desc(abs_alias), term_1, term_2)

cat("\n================ TOP ALIASED TERM PAIRS ===================\n")
print(top_alias_results, n = nrow(top_alias_results))

factor_alias_results <- bind_rows(map(deep_results, "factor_burden")) %>%
  mutate(
    mean_abs_alias = round(mean_abs_alias, 4),
    max_abs_alias  = round(max_abs_alias, 4)
  ) %>%
  arrange(design, desc(max_abs_alias), desc(mean_abs_alias), factor)

cat("\n================ FACTOR-LEVEL ALIAS BURDEN ================\n")
print(factor_alias_results, n = nrow(factor_alias_results))

term_r2_results <- bind_rows(map(deep_results, "term_r2")) %>%
  mutate(
    R2_with_other_terms = round(R2_with_other_terms, 4)
  ) %>%
  arrange(design, desc(R2_with_other_terms), term)

cat("\n================ TERM-WISE R2 WITH OTHER TERMS ============\n")
print(term_r2_results, n = nrow(term_r2_results))

cat("\n================ RAW within.block.efficiencies ============\n")
for (nm in names(deep_results)) {
  cat("\n---", nm, "---\n")
  print(deep_results[[nm]]$raw_efficiencies)
}

#--------------------------------------------------------------
# 7. Save selected blocked design
#--------------------------------------------------------------
if (!chosen_size %in% candidate_block_sizes) {
  stop("`chosen_size` must be one of `candidate_block_sizes`.")
}

blocked_design <- blocked_designs[[paste0("size", chosen_size)]]
combined_design <- bind_rows(blocked_design$Blocks)

save(
  full_design,
  blocked_design,
  combined_design,
  file = file.path(file_path_rdata, "full_factorial_design.RData")
)

save_full_design_to_excel(
  full_design,
  file.path(file_path_xlsx, "full_factorial_design.xlsx")
)

save_blocked_sets_to_excel(
  blocked_design,
  file.path(file_path_xlsx, paste0("vignette_sets_size_", chosen_size, ".xlsx"))
)

#--------------------------------------------------------------
# 8. Integrity checks
#--------------------------------------------------------------
print("Checking Excel integrity of full factorial design:")
print(
  check_data_integrity_xlsx(
    full_design,
    file.path(file_path_xlsx, "full_factorial_design.xlsx")
  )
)

print("Design generation complete.")

#--------------------------------------------------------------
# End of script
#--------------------------------------------------------------
