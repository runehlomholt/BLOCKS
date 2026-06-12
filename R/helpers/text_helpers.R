read_factor_texts <- function(folder, factor_name, levels) {
  files <- file.path(folder, paste0(factor_name, levels, ".txt"))
  missing <- files[!file.exists(files)]
  if (length(missing) > 0) {
    stop("Missing factor text files: ", paste(missing, collapse = ", "))
  }

  tibble::tibble(
    level = levels,
    text = vapply(files, readr::read_file, character(1))
  )
}

collapse_text_fragments <- function(fragments) {
  paste(trimws(fragments), collapse = "\n\n")
}
