repair_openxlsx_relationships <- function(path) {
  unpacked <- tempfile("blocks_xlsx_")
  repaired <- tempfile(fileext = ".xlsx")
  dir.create(unpacked)
  on.exit(unlink(c(unpacked, repaired), recursive = TRUE, force = TRUE), add = TRUE)

  utils::unzip(path, exdir = unpacked)
  relationship_files <- list.files(
    file.path(unpacked, "xl", "worksheets", "_rels"),
    pattern = "[.]rels$",
    full.names = TRUE
  )

  for (relationship_file in relationship_files) {
    document <- xml2::read_xml(relationship_file)
    relationships <- xml2::xml_find_all(
      document,
      "//*[local-name()='Relationship']"
    )
    source_directory <- dirname(dirname(relationship_file))

    for (relationship in relationships) {
      target <- xml2::xml_attr(relationship, "Target")
      target_mode <- xml2::xml_attr(relationship, "TargetMode")
      if (!is.na(target_mode) && target_mode == "External") next
      target_path <- normalizePath(
        file.path(source_directory, target),
        winslash = "/",
        mustWork = FALSE
      )
      if (!file.exists(target_path)) xml2::xml_remove(relationship)
    }
    xml2::write_xml(document, relationship_file)
  }

  package_files <- list.files(
    unpacked,
    recursive = TRUE,
    all.files = TRUE,
    no.. = TRUE
  )
  zip::zipr(repaired, package_files, root = unpacked, mode = "mirror")
  if (!file.copy(repaired, path, overwrite = TRUE)) {
    stop("Could not replace repaired workbook: ", path)
  }
  invisible(path)
}

save_full_design_to_excel <- function(design, path) {
  workbook <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(workbook, "Full_factorial")
  openxlsx::writeDataTable(
    workbook,
    "Full_factorial",
    design,
    tableName = "FullFactorialDesign",
    tableStyle = "TableStyleMedium2"
  )
  openxlsx::freezePane(workbook, "Full_factorial", firstRow = TRUE)
  openxlsx::setColWidths(
    workbook,
    sheet = "Full_factorial",
    cols = seq_len(ncol(design)),
    widths = "auto"
  )
  openxlsx::saveWorkbook(workbook, path, overwrite = TRUE)
  repair_openxlsx_relationships(path)
}

save_blocked_sets_to_excel <- function(blocked_design, comparison, path) {
  workbook <- openxlsx::createWorkbook()

  openxlsx::addWorksheet(workbook, "Design_evaluation")
  openxlsx::writeDataTable(
    workbook,
    "Design_evaluation",
    comparison,
    tableName = "DesignEvaluation",
    tableStyle = "TableStyleMedium2"
  )
  openxlsx::freezePane(workbook, "Design_evaluation", firstRow = TRUE)
  openxlsx::setColWidths(
    workbook,
    "Design_evaluation",
    cols = seq_len(ncol(comparison)),
    widths = "auto"
  )

  for (index in seq_along(blocked_design$Blocks)) {
    sheet_name <- paste0("Set_", index)
    openxlsx::addWorksheet(workbook, sheet_name)
    openxlsx::writeDataTable(
      workbook,
      sheet_name,
      blocked_design$Blocks[[index]],
      tableName = paste0("VignetteSet", index),
      tableStyle = "TableStyleMedium2"
    )
    openxlsx::freezePane(workbook, sheet_name, firstRow = TRUE)
    openxlsx::setColWidths(
      workbook,
      sheet_name,
      cols = seq_len(ncol(blocked_design$Blocks[[index]])),
      widths = "auto"
    )
  }
  openxlsx::saveWorkbook(workbook, path, overwrite = TRUE)
  repair_openxlsx_relationships(path)
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

check_blocked_design_integrity <- function(full_design, blocked_design) {
  blocks <- blocked_design$Blocks
  if (!is.list(blocks) || length(blocks) == 0) {
    stop("Blocked design does not contain any sets.")
  }
  missing_id <- which(!vapply(
    blocks,
    function(block) "id" %in% names(block),
    logical(1)
  ))
  if (length(missing_id) > 0) {
    stop("Missing id column in set(s): ", paste(missing_id, collapse = ", "))
  }

  ids <- unlist(lapply(blocks, function(block) block$id), use.names = FALSE)

  expected_ids <- sort(full_design$id)
  actual_ids <- sort(ids)
  list(
    n_sets = length(blocks),
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
