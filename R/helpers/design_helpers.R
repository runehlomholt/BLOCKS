save_full_design_to_excel <- function(design, path) {
  workbook <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(workbook, "Full_factorial")
  openxlsx::writeData(workbook, "Full_factorial", design)
  openxlsx::setColWidths(
    workbook,
    sheet = "Full_factorial",
    cols = seq_len(ncol(design)),
    widths = "auto"
  )
  openxlsx::saveWorkbook(workbook, path, overwrite = TRUE)
}

save_blocked_sets_to_excel <- function(blocked_design, path) {
  workbook <- openxlsx::createWorkbook()
  for (index in seq_along(blocked_design$Blocks)) {
    sheet_name <- paste0("Set_", index)
    openxlsx::addWorksheet(workbook, sheet_name)
    openxlsx::writeData(workbook, sheet_name, blocked_design$Blocks[[index]])
  }
  openxlsx::saveWorkbook(workbook, path, overwrite = TRUE)
}

evaluate_block_design <- function(blocked_design, set_size, formula) {
  evaluation <- AlgDesign::eval.blockdesign(
    frml = formula,
    design = blocked_design$design,
    blocksizes = rep(set_size, length(blocked_design$Blocks)),
    center = FALSE,
    confounding = TRUE
  )

  efficiencies <- as.numeric(evaluation$within.block.efficiencies)
  confounding <- as.matrix(evaluation$confounding)
  diag(confounding) <- NA_real_

  tibble::tibble(
    set_size = set_size,
    n_sets = length(blocked_design$Blocks),
    n_vignettes = nrow(blocked_design$design),
    determinant_efficiency = efficiencies[[1]],
    trace_efficiency = efficiencies[[2]],
    rho = efficiencies[[3]],
    max_abs_confounding = max(abs(confounding), na.rm = TRUE)
  )
}

check_blocked_design_integrity <- function(full_design, workbook_path) {
  sheets <- openxlsx::getSheetNames(workbook_path)
  ids <- unlist(lapply(sheets, function(sheet) {
    data <- openxlsx::read.xlsx(workbook_path, sheet = sheet)
    if (!"id" %in% names(data)) {
      stop("Sheet ", sheet, " does not contain an id column.")
    }
    data$id
  }))

  expected_ids <- sort(full_design$id)
  actual_ids <- sort(ids)
  list(
    n_sets = length(sheets),
    n_rows = length(ids),
    unique_ids = length(unique(ids)),
    duplicate_ids = unique(ids[duplicated(ids)]),
    missing_ids = setdiff(expected_ids, actual_ids),
    unexpected_ids = setdiff(actual_ids, expected_ids),
    passed = length(ids) == length(expected_ids) &&
      length(unique(ids)) == length(expected_ids) &&
      setequal(as.numeric(expected_ids), as.numeric(actual_ids))
  )
}

print_blocked_design_integrity <- function(result) {
  cat("\n============================================================\n")
  cat("BLOCKED-DESIGN INTEGRITY\n")
  cat("============================================================\n")
  cat("Sets:", result$n_sets, "\n")
  cat("Rows:", result$n_rows, "\n")
  cat("Unique vignette IDs:", result$unique_ids, "\n")
  cat("Status:", if (result$passed) "PASS" else "FAIL", "\n")
  if (!result$passed) {
    cat("Duplicate IDs:", paste(result$duplicate_ids, collapse = ", "), "\n")
    cat("Missing IDs:", paste(result$missing_ids, collapse = ", "), "\n")
    cat("Unexpected IDs:", paste(result$unexpected_ids, collapse = ", "), "\n")
    stop("Blocked-design integrity check failed.")
  }
}
