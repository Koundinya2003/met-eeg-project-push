# ============================================================
# MET MUSIC + EEG PROJECT - PROJECT SETTINGS
# ============================================================
#
# The ONLY file with a machine-specific path.
# Everything else is relative to the project folder.
# ============================================================

# Where the BIDS dataset lives (read-only; never modified)
dataset_path <- "/Users/adityakkoundinya/Documents/ds008701-full"


# Each phase keeps its code AND its outputs together.
P1_OUT <- here::here("01_phase1_ratings",        "outputs")
P2_OUT <- here::here("02_phase2_eeg_inspection", "outputs")
P3_OUT <- here::here("03_phase3_features",       "outputs")
P4_OUT <- here::here("04_phase4_statistics",     "outputs")
P5_OUT <- here::here("05_phase5_report",         "outputs")

PREREG_FILE <- here::here("02_phase2_eeg_inspection", "PREREGISTRATION.md")

for (d in c(P1_OUT, P2_OUT, P3_OUT, P4_OUT, P5_OUT)) {
  dir.create(file.path(d, "figures"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(d, "tables"),  showWarnings = FALSE, recursive = TRUE)
}
rm(d)
