##############################################
# RESET VIGNETTE DATABASE (DEVELOPMENT ONLY)
##############################################

# ---- packages ----
if (!requireNamespace("pacman", quietly = TRUE)) {
  install.packages("pacman")
}
pacman::p_load(DBI, RPostgres)

# ---- config ----
DATABASE_URL <- Sys.getenv("DATABASE_URL")
if (DATABASE_URL == "") {
  stop("DATABASE_URL not set. Aborting.")
}

# ---- parse DATABASE_URL ----
parse_db_url <- function(url) {
  m <- regexec("^postgresql://([^:]+):([^@]+)@([^:]+):(\\d+)/(.*)$", url)
  p <- regmatches(url, m)[[1]]
  if (length(p) == 0) stop("Invalid DATABASE_URL format.")
  list(
    user     = p[2],
    password = p[3],
    host     = p[4],
    port     = as.integer(p[5]),
    dbname   = p[6]
  )
}

cfg <- parse_db_url(DATABASE_URL)

# ---- connect ----
con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = cfg$dbname,
  host     = cfg$host,
  port     = cfg$port,
  user     = cfg$user,
  password = cfg$password,
  sslmode  = "require"
)

cat("\n⚠️  WARNING\n")
cat("This will DELETE ALL experimental data:\n")
cat(" - respondents\n - assigned_vignettes\n - vignette_responses\n\n")
cat("Type YES to continue: ")

confirm <- readline(prompt = "YES > ")

if (confirm != "YES") {
  dbDisconnect(con)
  stop("Reset aborted.")
}

# ---- reset ----
dbExecute(con, "
  TRUNCATE TABLE
    vignette_responses,
    assigned_vignettes,
    respondents
  RESTART IDENTITY
  CASCADE;
")

cat("\n✅ Database reset completed successfully.\n")
