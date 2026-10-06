# ============================================================
# MET MUSIC + EEG PROJECT
# STEP 26: REPRODUCE THE WHOLE PROJECT FROM RAW DATA
# ============================================================
#
# HOW TO USE:
#   1. Session > Restart R   (clean environment, nothing hidden)
#   2. source("run_all.R")
#
# If this runs from start to finish and the numbers in the
# report match what you saw before, the project is
# reproducible.
# ============================================================

start <- Sys.time()

# Each script runs in its OWN clean environment so no object
# from one phase can silently leak into the next.
run_phase <- function(folder, file) {
  message("\n==== Running ", folder, "/", file, " ====\n")
  source(here::here(folder, file), local = new.env())
}

run_phase("01_phase1_ratings",        "01_ratings.R")         # ratings
run_phase("02_phase2_eeg_inspection", "02_eeg_inspect.R")     # one-recording inspection
run_phase("03_phase3_features",       "03_features.R")        # all 399 recordings + QC (~10 min)
run_phase("04_phase4_statistics",     "04_stats.R")           # stops if preregistration not committed
run_phase("05_phase5_report",         "05_final_outputs.R")   # final tables + worksheet

# The report
quarto::quarto_render(here::here("05_phase5_report", "report.qmd"))

Sys.time() - start

sessionInfo()
