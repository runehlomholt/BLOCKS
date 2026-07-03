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

  worksheet_files <- list.files(
    file.path(unpacked, "xl", "worksheets"),
    pattern = "[.]xml$",
    full.names = TRUE
  )
  for (worksheet_file in worksheet_files) {
    document <- xml2::read_xml(worksheet_file)
    cells <- xml2::xml_find_all(document, "//*[local-name()='c']")
    refs <- xml2::xml_attr(cells, "r")
    refs <- refs[!is.na(refs)]
    if (length(refs) == 0) next

    col_to_num <- function(col) {
      values <- utf8ToInt(col) - utf8ToInt("A") + 1
      sum(values * 26^rev(seq_along(values) - 1))
    }
    num_to_col <- function(num) {
      out <- character()
      while (num > 0) {
        rem <- (num - 1) %% 26
        out <- c(intToUtf8(utf8ToInt("A") + rem), out)
        num <- (num - rem - 1) %/% 26
      }
      paste(out, collapse = "")
    }

    columns <- gsub("[0-9]", "", refs)
    rows <- as.integer(gsub("[A-Z]", "", refs))
    max_col <- num_to_col(max(vapply(columns, col_to_num, numeric(1))))
    max_row <- max(rows, na.rm = TRUE)
    dimension <- xml2::xml_find_first(document, "//*[local-name()='dimension']")
    if (!is.na(xml2::xml_name(dimension))) {
      xml2::xml_set_attr(dimension, "ref", paste0("A1:", max_col, max_row))
      xml2::write_xml(document, worksheet_file)
    }
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

save_blocked_sets_to_excel <- function(blocked_design, evaluation, path) {
  workbook <- openxlsx::createWorkbook()

  openxlsx::addWorksheet(workbook, "Design_evaluation")
  openxlsx::writeDataTable(
    workbook,
    "Design_evaluation",
    evaluation,
    tableName = "DesignEvaluation",
    tableStyle = "TableStyleMedium2"
  )
  openxlsx::freezePane(workbook, "Design_evaluation", firstRow = TRUE)
  openxlsx::setColWidths(
    workbook,
    "Design_evaluation",
    cols = seq_len(ncol(evaluation)),
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

combine_blocked_design <- function(blocked_design) {
  if (is.null(blocked_design$Blocks) || length(blocked_design$Blocks) == 0) {
    stop("blocked_design must be an AlgDesign::optBlock object with a non-empty $Blocks element.")
  }

  dplyr::bind_rows(lapply(seq_along(blocked_design$Blocks), function(index) {
    block <- as.data.frame(blocked_design$Blocks[[index]])
    block$set_id <- index
    block
  }))
}

evaluate_algdesign_block_design <- function(
    blocked_design,
    set_size,
    formula,
    confounding = TRUE,
    center = FALSE,
    rho = 1
) {
  combined <- combine_blocked_design(blocked_design)
  design_for_eval <- combined[, setdiff(names(combined), "set_id"), drop = FALSE]

  AlgDesign::eval.blockdesign(
    frml = formula,
    design = design_for_eval,
    blocksizes = rep(set_size, length(blocked_design$Blocks)),
    rho = rho,
    confounding = confounding,
    center = center
  )
}

label_algdesign_confounding_matrix <- function(evaluation) {
  if (
    !is.null(evaluation$confounding) &&
      is.matrix(evaluation$confounding) &&
      is.null(colnames(evaluation$confounding)) &&
      nrow(evaluation$confounding) == ncol(evaluation$confounding)
  ) {
    colnames(evaluation$confounding) <- rownames(evaluation$confounding)
  }

  evaluation
}

extract_efficiency <- function(within_efficiencies, name, index) {
  if (is.null(within_efficiencies)) return(NA_real_)

  if (is.matrix(within_efficiencies) || is.data.frame(within_efficiencies)) {
    if (!is.null(rownames(within_efficiencies)) && name %in% rownames(within_efficiencies)) {
      return(unname(as.numeric(within_efficiencies[name, 1])))
    }
    if (!is.null(colnames(within_efficiencies)) && name %in% colnames(within_efficiencies)) {
      return(unname(as.numeric(within_efficiencies[1, name])))
    }
  }

  values <- as.numeric(within_efficiencies)
  names(values) <- names(within_efficiencies)
  if (!is.null(names(values)) && name %in% names(values)) {
    return(unname(values[[name]]))
  }
  if (length(values) >= index) values[[index]] else NA_real_
}

summarise_confounding_matrix <- function(confounding_matrix) {
  if (is.null(confounding_matrix) || length(confounding_matrix) == 0) {
    return(tibble::tibble(
      max_abs_confounding_offdiag_lower_is_better = NA_real_,
      strongest_confounding_terms = NA_character_,
      n_abs_confounding_ge_0_10 = NA_integer_,
      n_abs_confounding_ge_0_25 = NA_integer_,
      max_abs_cross_factor_confounding_lower_is_better = NA_real_,
      strongest_cross_factor_confounding_terms = NA_character_,
      n_abs_cross_factor_confounding_ge_0_10 = NA_integer_,
      n_abs_cross_factor_confounding_ge_0_25 = NA_integer_
    ))
  }

  matrix <- as.matrix(confounding_matrix)
  if (is.null(colnames(matrix)) && nrow(matrix) == ncol(matrix)) {
    colnames(matrix) <- rownames(matrix)
  }
  if (is.null(rownames(matrix))) {
    rownames(matrix) <- paste0("term_", seq_len(nrow(matrix)))
  }
  if (is.null(colnames(matrix))) {
    colnames(matrix) <- paste0("term_", seq_len(ncol(matrix)))
  }

  offdiag <- matrix
  if (nrow(matrix) == ncol(matrix)) diag(offdiag) <- NA_real_
  offdiag[rownames(matrix) == "(Intercept)", ] <- NA_real_
  offdiag[, colnames(matrix) == "(Intercept)"] <- NA_real_

  abs_offdiag <- abs(offdiag)
  if (all(is.na(abs_offdiag))) {
    return(tibble::tibble(
      max_abs_confounding_offdiag_lower_is_better = NA_real_,
      strongest_confounding_terms = NA_character_,
      n_abs_confounding_ge_0_10 = 0L,
      n_abs_confounding_ge_0_25 = 0L,
      max_abs_cross_factor_confounding_lower_is_better = NA_real_,
      strongest_cross_factor_confounding_terms = NA_character_,
      n_abs_cross_factor_confounding_ge_0_10 = 0L,
      n_abs_cross_factor_confounding_ge_0_25 = 0L
    ))
  }

  strongest_index <- which(
    abs_offdiag == max(abs_offdiag, na.rm = TRUE),
    arr.ind = TRUE
  )[1, ]

  strongest_terms <- paste(
    rownames(matrix)[strongest_index[["row"]]],
    "with",
    colnames(matrix)[strongest_index[["col"]]]
  )

  term_family <- function(term) {
    ifelse(
      is.na(term) | term == "(Intercept)",
      term,
      sub("[0-9].*$", "", term)
    )
  }

  row_families <- term_family(rownames(matrix))
  col_families <- term_family(colnames(matrix))
  same_factor <- outer(row_families, col_families, FUN = "==")
  cross_factor <- offdiag
  cross_factor[same_factor] <- NA_real_
  abs_cross_factor <- abs(cross_factor)

  if (all(is.na(abs_cross_factor))) {
    max_abs_cross_factor <- NA_real_
    strongest_cross_factor_terms <- NA_character_
    n_cross_ge_0_10 <- 0L
    n_cross_ge_0_25 <- 0L
  } else {
    max_abs_cross_factor <- max(abs_cross_factor, na.rm = TRUE)
    strongest_cross_index <- which(
      abs_cross_factor == max_abs_cross_factor,
      arr.ind = TRUE
    )[1, ]
    strongest_cross_factor_terms <- if (isTRUE(max_abs_cross_factor == 0)) {
      "none"
    } else {
      paste(
        rownames(matrix)[strongest_cross_index[["row"]]],
        "with",
        colnames(matrix)[strongest_cross_index[["col"]]]
      )
    }
    n_cross_ge_0_10 <- sum(abs_cross_factor >= 0.10, na.rm = TRUE)
    n_cross_ge_0_25 <- sum(abs_cross_factor >= 0.25, na.rm = TRUE)
  }

  tibble::tibble(
    max_abs_confounding_offdiag_lower_is_better = max(abs_offdiag, na.rm = TRUE),
    strongest_confounding_terms = strongest_terms,
    n_abs_confounding_ge_0_10 = sum(abs_offdiag >= 0.10, na.rm = TRUE),
    n_abs_confounding_ge_0_25 = sum(abs_offdiag >= 0.25, na.rm = TRUE),
    max_abs_cross_factor_confounding_lower_is_better = max_abs_cross_factor,
    strongest_cross_factor_confounding_terms = strongest_cross_factor_terms,
    n_abs_cross_factor_confounding_ge_0_10 = n_cross_ge_0_10,
    n_abs_cross_factor_confounding_ge_0_25 = n_cross_ge_0_25
  )
}

evaluate_block_summary <- function(
    blocked_design,
    set_size,
    formula,
    algdesign_evaluation = NULL
) {
  combined <- combine_blocked_design(blocked_design)
  factor_vars <- intersect(all.vars(formula), names(combined))
  if (length(factor_vars) == 0) {
    stop("No factor columns from the model formula were found in the blocked design.")
  }

  combined_for_matrix <- combined
  combined_for_matrix[factor_vars] <- lapply(combined_for_matrix[factor_vars], as.factor)

  model_matrix <- stats::model.matrix(formula, data = combined_for_matrix)
  xtx <- crossprod(model_matrix)
  rank_x <- qr(model_matrix)$rank
  n_parameters <- ncol(model_matrix)
  n_rows <- nrow(model_matrix)
  condition_number <- tryCatch(
    kappa(xtx, exact = TRUE),
    error = function(e) NA_real_
  )
  log_det_xtx <- as.numeric(determinant(xtx, logarithm = TRUE)$modulus)
  d_score <- if (rank_x == n_parameters && is.finite(log_det_xtx)) {
    exp(log_det_xtx / n_parameters) / n_rows
  } else {
    NA_real_
  }

  if (is.null(algdesign_evaluation)) {
    algdesign_evaluation <- evaluate_algdesign_block_design(
      blocked_design = blocked_design,
      set_size = set_size,
      formula = formula,
      confounding = TRUE,
      center = FALSE
    )
  }
  algdesign_evaluation <- label_algdesign_confounding_matrix(algdesign_evaluation)
  confounding_summary <- summarise_confounding_matrix(algdesign_evaluation$confounding)

  within_eff <- algdesign_evaluation$within.block.efficiencies
  centered_determinant <- if (!is.null(algdesign_evaluation$determinant.all.terms.within.terms.centered)) {
    as.numeric(algdesign_evaluation$determinant.all.terms.within.terms.centered)
  } else {
    NA_real_
  }

  evaluation <- tibble::tibble(
    candidate_design = paste0(
      length(blocked_design$Blocks),
      " respondent sets x ",
      set_size,
      " vignettes"
    ),
    set_size = set_size,
    n_sets = length(blocked_design$Blocks),
    n_vignettes = n_rows,
    model_terms = paste(attr(stats::terms(formula), "term.labels"), collapse = " + "),
    n_parameters = n_parameters,
    design_matrix_rank = rank_x,
    parameters_estimable = paste0(rank_x, "/", n_parameters),
    full_rank = rank_x == n_parameters,
    condition_number_lower_is_better = condition_number,
    d_score_higher_is_better = d_score,
    optblock_d_higher_is_better = if (is.null(blocked_design$D)) NA_real_ else as.numeric(blocked_design$D),
    optblock_diagonality_higher_is_better = if (is.null(blocked_design$diagonality)) NA_real_ else as.numeric(blocked_design$diagonality),
    centered_within_term_determinant_higher_is_better = centered_determinant,
    within_block_efficiency_det_higher_is_better = extract_efficiency(within_eff, "lambda.det", 1),
    within_block_efficiency_trace_higher_is_better = extract_efficiency(within_eff, "lambda.trace", 2),
    rho = extract_efficiency(within_eff, "rho", 3)
  )
  dplyr::bind_cols(evaluation, confounding_summary)
}

print_algdesign_block_evaluation <- function(
    evaluation,
    set_size,
    n_sets,
    digits = 3
) {
  evaluation <- label_algdesign_confounding_matrix(evaluation)
  evaluation_for_print <- evaluation

  if (!is.null(evaluation_for_print$confounding)) {
    evaluation_for_print$confounding <- round(evaluation_for_print$confounding, digits)
  }
  if (!is.null(evaluation_for_print$within.block.efficiencies)) {
    evaluation_for_print$within.block.efficiencies <- round(
      evaluation_for_print$within.block.efficiencies,
      digits
    )
  }
  if (!is.null(evaluation_for_print$determinant.all.terms.within.terms.centered)) {
    evaluation_for_print$determinant.all.terms.within.terms.centered <- round(
      evaluation_for_print$determinant.all.terms.within.terms.centered,
      digits
    )
  }

  cat("\n============================================================\n")
  cat("AlgDesign::eval.blockdesign() output\n")
  cat("Selected design: ", n_sets, " respondent sets x ", set_size, " vignettes\n", sep = "")
  cat("============================================================\n")
  print(evaluation_for_print)
  invisible(evaluation)
}

print_selected_block_design_evaluation <- function(evaluation) {
  cat("\n============================================================\n")
  cat("SELECTED BLOCKED-DESIGN EVALUATION\n")
  cat("============================================================\n")
  cat("Short labels used below:\n")
  cat("- sets: number of respondent-facing vignette sets\n")
  cat("- k: vignettes per set\n")
  cat("- rank: estimable model parameters / total model parameters\n")
  cat("- D: AlgDesign D criterion; higher is better\n")
  cat("- diag: AlgDesign diagonality; higher is better\n")
  cat("- effD / effTr: within-block determinant/trace efficiency; higher is better\n")
  cat("- xconf: largest cross-factor confounding coefficient; lower is better\n")
  cat("- strongest xconf: term pair with the largest cross-factor confounding\n\n")

  display <- dplyr::select(
    evaluation,
    sets = n_sets,
    k = set_size,
    rank = parameters_estimable,
    full_rank,
    D = optblock_d_higher_is_better,
    diag = optblock_diagonality_higher_is_better,
    effD = within_block_efficiency_det_higher_is_better,
    effTr = within_block_efficiency_trace_higher_is_better,
    xconf = max_abs_cross_factor_confounding_lower_is_better,
    `strongest xconf` = strongest_cross_factor_confounding_terms
  )
  print(display, width = Inf)
  invisible(evaluation)
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

check_vignette_set_workbook_integrity <- function(full_design, path) {
  if (!file.exists(path)) {
    stop("Workbook not found: ", path)
  }
  if (!"id" %in% names(full_design)) {
    stop("full_design must contain an id column.")
  }

  sheet_names <- openxlsx::getSheetNames(path)
  set_sheets <- sheet_names[grepl("^Set_[0-9]+$", sheet_names)]
  if (length(set_sheets) == 0) {
    stop("No Set_* sheets were found in workbook: ", path)
  }

  sheet_data <- lapply(set_sheets, function(sheet) {
    data <- openxlsx::read.xlsx(path, sheet = sheet)
    data$.sheet <- sheet
    data
  })
  combined <- dplyr::bind_rows(sheet_data)
  if (!"id" %in% names(combined)) {
    stop("The Set_* sheets do not contain an id column: ", path)
  }

  expected_ids <- sort(unique(full_design$id))
  observed_ids <- sort(unique(combined$id))

  tibble::tibble(
    file = normalizePath(path, winslash = "/", mustWork = TRUE),
    n_set_sheets = length(set_sheets),
    n_expected_vignettes = length(expected_ids),
    n_rows_observed = nrow(combined),
    n_unique_ids_observed = length(observed_ids),
    n_missing_ids = length(setdiff(expected_ids, observed_ids)),
    n_extra_ids = length(setdiff(observed_ids, expected_ids)),
    n_duplicate_id_rows = sum(duplicated(combined$id)),
    integrity_ok = length(setdiff(expected_ids, observed_ids)) == 0 &&
      length(setdiff(observed_ids, expected_ids)) == 0 &&
      sum(duplicated(combined$id)) == 0
  )
}

print_vignette_set_workbook_integrity <- function(integrity) {
  row <- integrity[1, ]
  display <- tibble::tibble(
    source = "full factorial design",
    expected_ids = row$n_expected_vignettes,
    workbook_rows = row$n_rows_observed,
    workbook_unique_ids = row$n_unique_ids_observed,
    missing_ids = row$n_missing_ids,
    extra_ids = row$n_extra_ids,
    duplicate_rows = row$n_duplicate_id_rows,
    ok = row$integrity_ok
  )

  cat("\n============================================================\n")
  cat("VIGNETTE-SET WORKBOOK INTEGRITY CHECK\n")
  cat("============================================================\n")
  cat("Question: does vignette_sets.xlsx contain every full-design vignette id exactly once?\n")
  cat("Workbook checked: ", basename(row$file), "\n\n", sep = "")
  print(display, width = Inf)
  if (!isTRUE(row$integrity_ok)) {
    stop("Vignette-set workbook integrity check failed.")
  }
  invisible(integrity)
}
