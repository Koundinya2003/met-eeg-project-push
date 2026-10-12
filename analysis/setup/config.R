# ============================================================
# MET MUSIC + EEG PROJECT - PROJECT SETTINGS
# ============================================================
#
# The ONLY file with a machine-specific path.
# Everything else is relative to the project folder.
# ============================================================

# Where the BIDS dataset lives (read-only; never modified).
# Default: data/ds008701 inside this project, filled by
# analysis/setup/download_data.sh. To use a copy elsewhere, set the
# environment variable MET_DATA to its folder before running.
dataset_path <- Sys.getenv("MET_DATA", unset = here::here("data", "ds008701"))

if (!file.exists(file.path(dataset_path, "dataset_description.json"))) {
  stop("MET dataset not found at '", dataset_path, "'. ",
       "Run analysis/setup/download_data.sh from the project folder, ",
       "or set MET_DATA to the dataset folder.")
}


# All outputs live under results/, one subfolder per analysis step.
# Figures and tables are kept apart so each is easy to browse.
FIG_RATINGS        <- here::here("results", "figures", "ratings")         # 01_ratings.R
TAB_RATINGS        <- here::here("results", "tables",  "ratings")
FIG_EEG_INSPECTION <- here::here("results", "figures", "eeg_inspection")  # 02_eeg_inspection.R
FIG_FEATURES       <- here::here("results", "figures", "features")        # 03_feature_extraction.R
TAB_FEATURES       <- here::here("results", "tables",  "features")
FIG_STATS          <- here::here("results", "figures", "statistics")      # 04_statistics.R
TAB_STATS          <- here::here("results", "tables",  "statistics")
FIG_SUMMARY        <- here::here("results", "figures", "summary")         # 05_final_tables.R
TAB_SUMMARY        <- here::here("results", "tables",  "summary")

PREREG_FILE <- here::here("preregistration", "PREREGISTRATION.md")

for (d in c(FIG_RATINGS, TAB_RATINGS, FIG_EEG_INSPECTION,
            FIG_FEATURES, TAB_FEATURES, FIG_STATS, TAB_STATS,
            FIG_SUMMARY, TAB_SUMMARY)) {
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
}
rm(d)
