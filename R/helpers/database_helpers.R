require_database_packages <- function() {
  required <- c("DBI", "RPostgres", "dplyr", "tibble")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop(
      "Missing R package(s): ", paste(missing, collapse = ", "),
      ". Install them before running database scripts."
    )
  }
}

get_database_url <- function(database_url = NULL) {
  placeholders <- c(
    "YOUR_URL_HERE",
    "postgresql://USER:PASSWORD@HOST:PORT/DATABASE?sslmode=require"
  )
  supplied_placeholder <- !is.null(database_url) && database_url %in% placeholders
  if (is.null(database_url) || !nzchar(database_url) || supplied_placeholder) {
    environment_url <- Sys.getenv("DATABASE_URL")
    if (nzchar(environment_url)) database_url <- environment_url
  }
  if (is.null(database_url) || !nzchar(database_url)) {
    stop(
      "No database URL is configured. Edit the database_url line near the top ",
      "of scripts/03a_monitor_database.R or set DATABASE_URL in .Renviron."
    )
  }
  if (database_url %in% placeholders) {
    stop(
      "The database monitor still contains its placeholder URL. Replace the ",
      "database_url line near the top of scripts/03a_monitor_database.R with ",
      "Railway's public PostgreSQL URL, or set DATABASE_URL in .Renviron."
    )
  }
  database_url
}

parse_database_url <- function(database_url) {
  pattern <- paste0(
    "^postgres(?:ql)?://",
    "([^:]+):([^@]+)@",
    "([^:/?]+)",
    "(?::([0-9]+))?/",
    "([^?]+)",
    "(?:\\?(.*))?$"
  )
  match <- regexec(pattern, database_url, perl = TRUE)
  parts <- regmatches(database_url, match)[[1]]
  if (length(parts) == 0) {
    stop(
      "DATABASE_URL must have the form ",
      "postgresql://USER:PASSWORD@HOST:PORT/DATABASE?sslmode=require"
    )
  }

  query <- parts[[7]]
  query_values <- list()
  if (nzchar(query)) {
    entries <- strsplit(query, "&", fixed = TRUE)[[1]]
    for (entry in entries) {
      key_value <- strsplit(entry, "=", fixed = TRUE)[[1]]
      key <- utils::URLdecode(key_value[[1]])
      value <- if (length(key_value) > 1) {
        utils::URLdecode(paste(key_value[-1], collapse = "="))
      } else {
        ""
      }
      query_values[[key]] <- value
    }
  }

  list(
    user = utils::URLdecode(parts[[2]]),
    password = utils::URLdecode(parts[[3]]),
    host = parts[[4]],
    port = if (nzchar(parts[[5]])) as.integer(parts[[5]]) else 5432L,
    dbname = utils::URLdecode(parts[[6]]),
    sslmode = query_values$sslmode %||% "require"
  )
}

`%||%` <- function(value, fallback) {
  if (is.null(value) || !nzchar(value)) fallback else value
}

connect_blocks_database <- function(database_url = NULL) {
  require_database_packages()
  config <- parse_database_url(get_database_url(database_url))
  message(
    "Connecting read-only monitor to PostgreSQL at ",
    config$host, ":", config$port, "/", config$dbname, " ..."
  )
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = config$dbname,
    host = config$host,
    port = config$port,
    user = config$user,
    password = config$password,
    sslmode = config$sslmode
  )
}

assert_blocks_schema <- function(connection) {
  required_tables <- c(
    "allocation_lock", "respondents", "assigned_vignettes", "vignette_responses"
  )
  existing_tables <- DBI::dbListTables(connection)
  missing_tables <- setdiff(required_tables, existing_tables)
  if (length(missing_tables) > 0) {
    stop(
      "Database migration is incomplete. Missing table(s): ",
      paste(missing_tables, collapse = ", "),
      ". Run `alembic upgrade head` in the deployed application."
    )
  }

  required_columns <- list(
    respondents = c(
      "status", "allocated_at", "started_at", "completed_at", "abandoned_at",
      "last_activity_at", "attention_presented_at", "attention_submitted_at",
      "attention_latency_ms"
    ),
    vignette_responses = c(
      "server_received_at", "answer_change_count", "latency_ms", "click_count"
    )
  )

  for (table in names(required_columns)) {
    fields <- DBI::dbListFields(connection, table)
    missing <- setdiff(required_columns[[table]], fields)
    if (length(missing) > 0) {
      stop(
        "Database migration is incomplete. Missing column(s) in ", table, ": ",
        paste(missing, collapse = ", "),
        ". Run `alembic upgrade head`."
      )
    }
  }

  invisible(TRUE)
}
