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
# from one script can silently leak into the next.
run_script <- function(file) {
  message("\n==== Running analysis/", file, " ====\n")
  source(here::here("analysis", file), local = new.env())
}

run_script("01_ratings.R")             # song ratings
run_script("02_eeg_inspection.R")      # inspect one EEG recording
run_script("03_feature_extraction.R")  # band power from all 399 recordings + QC (~10 min)
run_script("04_statistics.R")          # hypothesis tests; stops if preregistration not committed
run_script("05_final_tables.R")        # final tables + worksheet

# The report
quarto::quarto_render(here::here("report", "report.qmd"))

Sys.time() - start

sessionInfo()
