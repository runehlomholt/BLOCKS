# BLOCKS: an application for administering blocked, text-based factorial vignette studies

**Design, deploy, and run blocked vignette experiments without consultancy fees.**

BLOCKS is a free, open-source web application for researchers who want to conduct blocked vignette experiments with control over design, randomisation, data storage, and study flow.

Respondents enter through a personal study link, are assigned to a balanced vignette set, answer one vignette at a time, and can return to an unfinished session using the same link. The researcher defines the experimental design in R, writes the vignette content, configures question batteries in Excel, and receives analysis-ready data from PostgreSQL.

The app is designed for researchers, not software companies:

- No licence or per-respondent fees
- No black-box allocation or randomisation
- No required storage outside infrastructure you control
- No requirement to collect names or email addresses
- Transparent and auditable study logic

## The respondent flow

### 1. Entering the study

The respondent follows a link containing a study token:

```text
https://YOUR_APP_DOMAIN/?token=RESPONDENT_ID
```

For a new token, BLOCKS assigns the respondent to one of the vignette sets with the fewest participants. If several sets are equally available, the app chooses randomly between them. This keeps allocation balanced, including when several respondents enter at nearly the same time.

The vignette order is shuffled once for that respondent and then stored. The respondent therefore keeps the same set and order throughout the study.

### 2. Answering the vignettes

The respondent sees one vignette at a time, followed by the question batteries configured for the study. All required questions must be answered before the respondent can continue.

When `Next` is selected, the app validates and stores the complete response to that vignette. Earlier submitted pages remain saved if the respondent closes the browser. Answers selected on the page currently being viewed are not stored until `Next` is selected.

For each submitted vignette, the app can record:

- Responses to all configured questions
- Vignette order and assigned set
- Response latency
- Click count
- Number of times selected answers were changed
- Presentation, submission, and server timestamps
- App and experimental-design versions

### 3. Attention check

One easy arithmetic attention check is placed at a random point in the sequence when a set contains at least three vignettes. Its position is determined for the respondent in advance.

The app records whether it was completed correctly as well as its presentation time, submission time, and response latency.

### 4. Leaving and returning

If a respondent leaves after submitting at least one vignette, opening the original link again resumes the study at the first unanswered vignette. Previously submitted responses and the original randomised order are retained.

If someone enters but never submits a vignette, the unused allocation can expire after a configurable period. It then stops occupying a set quota. A respondent who later returns with that same token can still reactivate the original assignment.

### 5. Completing the study

Submitting the final vignette marks the respondent as completed. There is no separate save action on the finished page.

The app distinguishes between respondents who are:

- `allocated`: assigned, but have not submitted a vignette
- `started`: have submitted at least one vignette
- `completed`: have submitted the final vignette
- `abandoned`: had an unused allocation expire before beginning

This makes it possible to monitor recruitment, dropout, set balance, and completed participation separately.

## What the app does

- Assigns respondents to quota-balanced vignette sets
- Randomises and stores vignette order within each set
- Presents text-based vignettes with flexible question batteries
- Validates required answers and permitted scale values
- Supports returning respondents and partial participation
- Presents and records an arithmetic attention check
- Records response timing and interaction paradata
- Stores responses in PostgreSQL
- Provides protected, analysis-ready CSV export
- Supports read-only monitoring and data-integrity checks in R
- Integrates with external survey platforms through respondent tokens

## Typical research workflow

### Step 1: Design the experiment in R

Define factors, levels, block size, random seed, and text order in:

```text
config/workflow_config.R
```

Run the complete example workflow from the repository root:

```bash
Rscript scripts/run_design_workflow.R
```

The included scripts:

- Generate a full factorial design
- Construct blocked vignette sets
- Evaluate balance, confounding, and efficiency
- Generate application-ready vignette texts

The main outputs are typed RDS files used by later scripts and XLSX copies for human inspection:

```text
outputs/full_factorial_design.rds
outputs/blocked_design.rds
outputs/full_factorial_design.xlsx
outputs/vignette_sets.xlsx
```

The committed example contains 96 variations of a short morning-coffee story arranged into 24 balanced sets of four. It demonstrates the workflow rather than a substantively meaningful experiment.

### Step 2: Generate vignette texts

The text generator combines static passages and factor-level fragments in a researcher-defined order. It creates the folder structure expected by the app:

```text
vignette_content/
  Set_1/
    vignette_12.txt
    vignette_47.txt
  Set_2/
    vignette_3.txt
    vignette_88.txt
```

Each folder represents one block or vignette set. The app reads the available folders and files automatically, so another study can use a different number of sets and vignettes without changing the application code.

Balanced set sizes are checked when the app starts. Unequal set sizes can be allowed deliberately with `ALLOW_UNBALANCED_SETS=1`.

### Step 3: Add question batteries

Questions and response scales are defined in one or more `.xlsx` files in `question_batteries/`. This supports multiple batteries and multiple outcome items per vignette.

Each workbook contains:

| Column | Meaning |
| --- | --- |
| `question_id` | Unique, stable item name used as the CSV column name |
| `question_text` | Text displayed to respondents |
| `scale_min` | Lowest permitted integer response |
| `scale_max` | Highest permitted integer response |
| `scale_labels` | Semicolon-separated label for each scale value |

All items in one workbook share the response scale defined by its first data row. For example, a 1-5 scale requires five labels.

An optional heading can be added with a text file sharing the workbook name:

```text
question_batteries/Battery_1_example.xlsx
question_batteries/Battery_1_example_heading.txt
```

The application checks question IDs, scale definitions, required answers, and submitted values. Invalid or incomplete responses are rejected even if someone bypasses the browser interface.

### Step 4: Deploy the app

The app can be deployed with GitHub for source control and Railway for application hosting and PostgreSQL. See `Installation guide.txt` for local setup, database attachment, environment variables, public networking, testing, export, and monitoring.

Railway products and prices can change, so consult its current documentation before selecting a production setup.

### Step 5: Invite respondents

BLOCKS can be used on its own or as one part of a larger survey. A common setup is:

1. Collect background or sensitive variables in an approved survey platform.
2. Generate or pass a pseudonymous respondent token.
3. Redirect the respondent to `https://YOUR_APP_DOMAIN/?token=RESPONDENT_ID`.
4. Merge the datasets later using the controlled linkage key.

Sensitive information does not need to enter the vignette application.

### Step 6: Monitor and export data

The read-only script `scripts/03a_monitor_database.R` reports:

- Respondent lifecycle counts
- Occupancy of each vignette set
- Submitted vignette episodes
- Answer changes and response latency
- Attention-check results and diagnostics

It does not alter respondent records. The script can use Railway's public PostgreSQL URL directly or read `DATABASE_URL` from `~/.Renviron`. A database URL contains a password and must not be committed or shared.

Set a strong `EXPORT_KEY` to enable the protected CSV export:

```bash
curl -H "Authorization: Bearer YOUR_EXPORT_KEY" \
  https://YOUR_APP_DOMAIN/export -o vignette_data.csv
```

The export contains one row per respondent and submitted vignette, with question responses in separate columns. Partial respondents are included for the vignettes they submitted. Respondents who never submitted a vignette are absent because they have no response episode.

Check a downloaded file with:

```bash
Rscript scripts/03b_check_export_integrity.R vignette_data.csv
```

The checker verifies required columns, unique response episodes, valid participant states, valid timing and answer-change values, and complete item responses.

## Privacy and data protection

BLOCKS is intentionally limited in the data it requires. The application stores:

- An internally generated respondent UUID
- The external token supplied through the study link
- Assigned set and randomised vignette order
- Responses, timing, clicks, and answer changes
- Attention-check results and timing
- Participant lifecycle and version metadata
- The browser user-agent string

It does not require names, email addresses, or a dedicated IP-address field.

This alone does not make a study GDPR-compliant. Hosting providers and reverse proxies may retain access logs, and an external token may be identifying if it contains personal information or can be linked to another dataset. Use pseudonymous random tokens, restrict database and export access, define retention rules, and document the setup in the study's ethics and data-management materials.

The researcher or institution remains responsible for data protection compliance, ethical approval, participant information, security, and appropriate use.

## Configuration

The most important environment variables are:

| Variable | Purpose | Default |
| --- | --- | --- |
| `DATABASE_URL` | PostgreSQL connection; local development uses SQLite if omitted | local SQLite |
| `EXPORT_KEY` | Secret required for `/export`; export is disabled when empty | empty |
| `TOKEN_REQUIRED` | Require a token to enter the study | `1` |
| `ALLOCATION_EXPIRY_MINUTES` | Time before an unused allocation may expire | `60` |
| `APP_VERSION` | Application version saved with each respondent | `development` |
| `DESIGN_VERSION` | Experimental-design version saved with each respondent | `unspecified` |
| `VIGNETTE_CONTENT_PATH` | Location of vignette-set folders | `vignette_content` |
| `ALLOW_UNBALANCED_SETS` | Permit different numbers of vignettes across sets | `0` |

Database changes are versioned with Alembic. The Railway `Procfile` applies migrations before starting the app, and startup checks that vignette content and question batteries are valid.

## Tests

Install the development dependencies and run:

```bash
pip install -r requirements-dev.txt
pytest -q
```

## License and citation

BLOCKS is released under the MIT License and is free to use, adapt, and extend.

To cite this exact release:

Lomholt, R. (2026). *BLOCKS: an application for administering blocked, text-based factorial vignette studies* (Version 2.0.0). Zenodo. https://doi.org/10.5281/zenodo.20671911

For the latest version of BLOCKS:

https://doi.org/10.5281/zenodo.17974420
