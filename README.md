# BLOCKS - Blocked Vignette Designs for Case Studies

**Design, deploy, and run blocked vignette experiments with transparent allocation and researcher-controlled data.**

BLOCKS is a free, open-source FastAPI application for blocked vignette experiments. It combines an R design workflow, file-based vignette and question configuration, PostgreSQL data storage, protected CSV export, and R monitoring tools.

The application does not require names, email addresses, or other directly identifying fields. Data protection compliance still depends on the study protocol, token design, hosting configuration, retention policy, participant information, and applicable law.

## Core functionality

- Allocates new respondents to one of the currently least-filled vignette sets
- Randomly chooses between tied least-filled sets under a database lock
- Randomises and permanently stores vignette order within the assigned set
- Resumes returning respondents from the first unanswered vignette when they use the same token
- Loads vignette text from `vignette_content/`
- Loads outcome items and response scales from structured Excel files in `question_batteries/`
- Validates sequence, required answers, question IDs, and response values on the server
- Presents one randomly positioned arithmetic attention check when a set has at least three vignettes
- Saves each vignette when the respondent selects `Next`; the final submission marks the respondent completed
- Records response latency, clicks, answer changes, lifecycle timestamps, attention-check timing, and version metadata
- Provides a protected wide CSV export and read-only R database monitoring

## Improvements in the current version

Compared with the original single-file application, the current version adds:

- A modular `app/` structure separating routes, services, configuration, database models, and experiment loading
- Persistent participant lifecycle states: `allocated`, `started`, `completed`, and `abandoned`
- Resumable participation and server-enforced vignette order
- Concurrency-safe, quota-balanced allocation
- Expiry of unused allocations so respondents who never submit a vignette do not permanently occupy a set quota
- Server-side submission validation and duplicate-submission protection
- Attention-check presentation time, submission time, latency, and correctness
- Per-vignette answer-change counts in addition to latency and click counts
- Alembic database migrations, automated tests, and a protected export endpoint
- A staged R workflow with typed RDS machine inputs and XLSX inspection copies
- A responsive interface with clearer progress, accessible controls, horizontal scale scrolling, and guarded submission buttons

## Respondent flow

1. A respondent opens `https://YOUR_APP_DOMAIN/?token=RESPONDENT_ID`.
2. A new token is assigned to a least-filled vignette set. Its vignette order is shuffled once and stored.
3. The respondent reads a vignette and answers every configured outcome item.
4. Selecting `Next` validates and stores that vignette's complete response episode.
5. An attention check appears at its preassigned point in the sequence.
6. The respondent continues until the final vignette is submitted. Completion is automatic; there is no separate data-saving action on the finished page.
7. Reopening the original token resumes at the first vignette that has not been submitted.

Answers selected on the currently displayed page are not stored until `Next` is selected. Responses submitted on earlier pages remain stored if the respondent leaves.

## Scientific data flow

1. Define factors, factor levels, block size, seed, and text merge order in `config/workflow_config.R`.
2. Generate the factorial design and selected vignette sets with the numbered R scripts.
3. Inspect the XLSX outputs and retain the RDS files as the typed machine-readable source of truth.
4. Generate application-ready vignette text under `vignette_content/`.
5. Define outcome variables and scales in structured Excel workbooks under `question_batteries/`.
6. Deploy a versioned app and collect responses in PostgreSQL.
7. Monitor collection without modifying the database, export the protected CSV, and run the integrity checker.

## R design workflow

Run the complete example workflow from the repository root:

```bash
Rscript scripts/run_design_workflow.R
```

The committed example contains 96 variations of a short morning-coffee story, arranged into 24 balanced sets of four. It is illustrative rather than substantively meaningful.

The numbered stages are:

- `scripts/00_setup.R`: shared paths and package checks
- `scripts/01a_define_study_design.R`: study-design definition
- `scripts/01b_generate_factorial_design.R`: full factorial generation
- `scripts/01c_construct_and_evaluate_vignette_sets.R`: set construction and evaluation
- `scripts/02a_generate_vignette_texts.R`: application text generation

Study settings are centralised in `config/workflow_config.R`. The workflow writes four canonical design artifacts:

- `outputs/full_factorial_design.rds`: typed factorial design used by later R stages
- `outputs/blocked_design.rds`: typed selected vignette sets used by text generation
- `outputs/full_factorial_design.xlsx`: human-readable factorial inspection copy
- `outputs/vignette_sets.xlsx`: human-readable set and evaluation copy

The RDS files are machine inputs. XLSX outputs are for human inspection and are not used as intermediate workflow inputs.

Generated application content has this structure:

```text
vignette_content/
  Set_1/
    vignette_12.txt
    vignette_47.txt
  Set_2/
    vignette_3.txt
    vignette_88.txt
```

Each set folder is one allocation block. Balanced set sizes are enforced at startup unless `ALLOW_UNBALANCED_SETS=1` is deliberately configured.

## Structured question batteries

Outcome variables and response scales remain defined in Excel. Place one or more `.xlsx` workbooks in `question_batteries/`. Each workbook must contain these columns:

| Column | Meaning |
| --- | --- |
| `question_id` | Stable item name used as the CSV column name; it must be unique across all workbooks |
| `question_text` | Text displayed to respondents |
| `scale_min` | Lowest permitted integer response value |
| `scale_max` | Highest permitted integer response value |
| `scale_labels` | Semicolon-separated labels for every value from minimum to maximum |

The first data row defines the shared response scale for that workbook. The number of labels must equal `scale_max - scale_min + 1`. For example, a 1-5 scale requires five semicolon-separated labels. All items in one workbook share that scale.

To provide a display heading, add a text file with the same stem and `_heading.txt`, for example:

```text
question_batteries/Battery_1_example.xlsx
question_batteries/Battery_1_example_heading.txt
```

If the heading file is absent, the workbook filename is converted into a title. The app refuses invalid or incomplete answer values even if a request bypasses the browser interface.

## Allocation, dropout, and quotas

The quota count includes respondents with status `allocated`, `started`, or `completed`.

- `allocated`: a set has been reserved, but no vignette has been submitted
- `started`: at least one vignette has been submitted, but the sequence is incomplete
- `completed`: the final vignette has been submitted
- `abandoned`: an unused allocation expired before the first vignette submission

Unused `allocated` records become eligible for abandonment after `ALLOCATION_EXPIRY_MINUTES` of inactivity. Expiry is applied when a later new participant is allocated. `Abandoned` records are excluded from quota counts, so people who never begin answering do not permanently fill a block.

Respondents who have submitted at least one vignette remain `started` if they drop out. Their submitted responses are retained and they continue to count in the quota. The current application does not automatically expire partial responders.

Using the same token reopens the same assignment. An abandoned token is reactivated and resumes its original assignment.

## Export and paradata

Set a strong `EXPORT_KEY`. The protected export endpoint is:

```text
https://YOUR_APP_DOMAIN/export
```

Bearer authentication is preferred:

```bash
curl -H "Authorization: Bearer YOUR_EXPORT_KEY" \
  https://YOUR_APP_DOMAIN/export -o vignette_data.csv
```

For quick browser testing, `https://YOUR_APP_DOMAIN/export?key=YOUR_EXPORT_KEY` is also supported. A real key must never be committed to GitHub or shared in screenshots.

The export is a wide episode-level CSV: one row per respondent and submitted vignette, with each `question_id` as a response column. It includes:

- Internal UUID and external respondent token
- Assigned block, vignette ID, and vignette order
- Participant status and lifecycle timestamps
- Design and application versions
- Client presentation and submission timestamps
- Server receipt timestamp and calculated vignette latency
- Click count and answer-change count
- Attention position, completion, correctness, timestamps, and latency

Respondents with no submitted vignette are absent from this response export because they have no response episode. Partial respondents are included for the vignettes they submitted and retain status `started`.

Answer-change count records how often a participant revised a selected answer before submitting a vignette. It may indicate reconsideration but is not, by itself, a validated measure of insecurity.

Validate a downloaded export with:

```bash
Rscript scripts/03b_check_export_integrity.R vignette_data.csv
```

The checker verifies required columns, episode uniqueness, valid statuses, non-negative latency and answer-change values, and complete item responses. It writes a `_checked.csv` copy when all checks pass.

## Database monitoring

`scripts/03a_monitor_database.R` is read-only. It reports lifecycle counts, set occupancy, submitted vignette episodes, answer revisions, attention-check results, and attention-gate diagnostics. It does not remove, abandon, or otherwise update respondents.

For a transparent local setup, replace the line near the top of the script:

```r
database_url <- "YOUR_URL_HERE"
```

with Railway's public PostgreSQL URL, then run:

```bash
Rscript scripts/03a_monitor_database.R
```

The public database URL is different from the app's public web URL. In Railway, obtain it from the PostgreSQL service's external connection/TCP proxy information. It contains a database password. Restore the placeholder before committing or publishing the branch.

For a safer persistent setup, leave the placeholder and set `DATABASE_URL` in `~/.Renviron`; database helpers use the environment variable when no URL is supplied.

The destructive reset utility is separate: `scripts/03c_reset_database.R`. It requires `BLOCKS_ALLOW_DATABASE_RESET=YES`, an interactive R session, and the exact confirmation phrase before participant data can be erased.

## Configuration

The application reads these environment variables:

| Variable | Purpose | Default |
| --- | --- | --- |
| `DATABASE_URL` | PostgreSQL connection; local development falls back to `sqlite:///./app.db` | local SQLite |
| `EXPORT_KEY` | Secret required for `/export`; export is disabled when empty | empty |
| `TOKEN_REQUIRED` | Require `?token=...` to enter the study | `1` |
| `ALLOCATION_EXPIRY_MINUTES` | Inactivity period before an unused allocation may be abandoned | `60` |
| `APP_VERSION` | Application version stored with each participant | `development` |
| `DESIGN_VERSION` | Experimental design version stored with each participant | `unspecified` |
| `VIGNETTE_CONTENT_PATH` | Vignette set directory | `vignette_content` |
| `ALLOW_UNBALANCED_SETS` | Allow unequal numbers of vignettes across sets | `0` |

Database changes are versioned with Alembic:

```bash
alembic upgrade head
```

The Railway `Procfile` runs migrations before starting Uvicorn. Application startup also verifies that vignette content and question batteries can be loaded.

## Installation and deployment

See `Installation guide.txt` for local setup, Railway PostgreSQL attachment, branch selection, environment variables, public networking, online testing, export, and monitoring.

Railway pricing and product steps can change. Check Railway's current documentation and pricing before choosing a production hosting plan.

## Privacy and data protection

The application database stores an internal UUID, the external token, the browser user-agent string, participant lifecycle metadata, responses, interaction paradata, and version fields. It does not require names, email addresses, or a dedicated IP-address field.

Hosting providers and reverse proxies may keep network and access logs independently of this application. External tokens can also become identifying if they contain personal information or can be linked to another dataset. Use pseudonymous random tokens, restrict database and export access, define retention rules, and document the setup in the study's ethics and data-management materials.

A common integration pattern is:

1. Collect identifying or sensitive variables in an approved survey platform.
2. Generate or pass a pseudonymous respondent token.
3. Redirect to `https://YOUR_APP_DOMAIN/?token=RESPONDENT_ID`.
4. Merge datasets later using the controlled linkage key.

The researcher or institution remains responsible for legal compliance, ethical approval, participant information, security, and appropriate use.

## Tests

Install development dependencies and run:

```bash
pip install -r requirements-dev.txt
pytest -q
```

## License and citation

BLOCKS is released under the MIT License and may be used, adapted, and extended.

Please cite:

Lomholt, R. (2026). *BLOCKS: an application for administering blocked, text-based factorial vignette studies* (v2.0.0). Zenodo. https://doi.org/10.5281/zenodo.19106987
