##############################################
# Vignette experiment – database monitoring  #
# Portable R script (Railway PostgreSQL)      #
##############################################

# -------------------------------
# 0. Package management
# -------------------------------

if (!requireNamespace("pacman", quietly = TRUE)) {
  install.packages("pacman")
}

pacman::p_load(
  DBI,
  RPostgres,
  dplyr,
  glue,
  tibble
)

# -------------------------------
# 1. Database connection details
# -------------------------------
# OPTION A (recommended):
#   Set DATABASE_URL as an environment variable, e.g. in .Renviron
#
# OPTION B:
#   Fill in the fields below manually from Railway or other source

DATABASE_URL <- Sys.getenv("DATABASE_URL")

if (DATABASE_URL == "") {
  stop("DATABASE_URL not set. Add it to your environment before running.")
}

# -------------------------------
# 2. Parse DATABASE_URL
# -------------------------------

parse_db_url <- function(url) {
  # Expected format:
  # postgresql://user:password@host:port/dbname
  m <- regexec(
    "^postgresql://([^:]+):([^@]+)@([^:]+):(\\d+)/(.*)$",
    url
  )
  parts <- regmatches(url, m)[[1]]
  
  if (length(parts) == 0) {
    stop("DATABASE_URL has unexpected format.")
  }
  
  list(
    user     = parts[2],
    password = parts[3],
    host     = parts[4],
    port     = as.integer(parts[5]),
    dbname   = parts[6]
  )
}

db_cfg <- parse_db_url(DATABASE_URL)

# -------------------------------
# 3. Connect to PostgreSQL
# -------------------------------

con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = db_cfg$dbname,
  host     = db_cfg$host,
  port     = db_cfg$port,
  user     = db_cfg$user,
  password = db_cfg$password,
  sslmode  = "require"
)

message("✔ Connected to PostgreSQL")

# -------------------------------
# 4. Monitoring queries
# -------------------------------

# 4.1 Number of respondents
respondents <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_respondents
  FROM respondents
")

# 4.2 Respondents per condition set
respondents_by_set <- dbGetQuery(con, "
  SELECT condition_set, COUNT(*) AS n
  FROM respondents
  GROUP BY condition_set
  ORDER BY condition_set
")

# 4.3 Vignette episodes (respondent × vignette)
episodes <- dbGetQuery(con, "
  SELECT COUNT(DISTINCT respondent_id, vignette_id) AS n_episodes
  FROM vignette_responses
")

# 4.4 Item-level observations (true long format)
item_responses <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_item_responses
  FROM vignette_responses
")

# 4.5 Attention check outcomes
attention <- dbGetQuery(con, "
  SELECT attention_correct, COUNT(*) AS n
  FROM respondents
  WHERE attention_completed = TRUE
  GROUP BY attention_correct
")

# -------------------------------
# 5. Print summary (console)
# -------------------------------

cat("\n==============================\n")
cat("VIGNETTE EXPERIMENT – STATUS\n")
cat("==============================\n\n")

print(respondents)
cat("\n")

print(respondents_by_set)
cat("\n")

print(episodes)
cat("\n")

print(item_responses)
cat("\n")

print(attention)
cat("\n")
