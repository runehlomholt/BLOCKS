# Edit this file when adapting BLOCKS to a new illustrative or real study.

workflow_config <- list(
  factor_specs = list(
    A = 1:2,
    B = 1:2,
    C = 1:3,
    D = 1:2,
    E = 1:2,
    F = 1:2
  ),
  block_sizes = c(4L),
  chosen_block_size = 4L,
  design_seed = 20260612L,
  optblock_repeats = as.integer(
    Sys.getenv("BLOCK_OPTIMISATION_REPEATS", "200")
  ),
  merge_order = c(
    "header", "S1", "S2", "S3", "A", "B", "C", "D", "E", "F"
  ),
  clean_generated_vignettes = TRUE
)
