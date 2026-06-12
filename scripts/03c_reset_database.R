# ==============================================================================
# Script: 03c_reset_database.R
# Purpose: Delete all participant data before a new data-collection run.
# ==============================================================================

source(file.path("scripts", "00_setup.R"))
source(file.path(path_helpers, "database_helpers.R"))

reset_blocks_database <- function() {
if (Sys.getenv("BLOCKS_ALLOW_DATABASE_RESET") != "YES") {
  stop(
    "Reset disabled. Set BLOCKS_ALLOW_DATABASE_RESET=YES only when you intend ",
    "to erase all respondent and response data."
  )
}
if (!interactive()) {
  stop("Database reset must be run interactively from R/RStudio.")
}

connection <- connect_blocks_database()
on.exit(DBI::dbDisconnect(connection), add = TRUE)
assert_blocks_schema(connection)

cat("\nWARNING: this permanently deletes all experimental data.\n")
cat("Type DELETE ALL BLOCKS DATA to continue.\n")
confirmation <- readline("Confirmation: ")
if (confirmation != "DELETE ALL BLOCKS DATA") stop("Database reset aborted.")

DBI::dbWithTransaction(connection, {
  DBI::dbExecute(connection, "
    TRUNCATE TABLE vignette_responses, assigned_vignettes, respondents
    RESTART IDENTITY CASCADE
  ")
  DBI::dbExecute(connection, "
    INSERT INTO allocation_lock (id) VALUES (1)
    ON CONFLICT (id) DO NOTHING
  ")
})
message("Database reset completed successfully.")
}

reset_blocks_database()
