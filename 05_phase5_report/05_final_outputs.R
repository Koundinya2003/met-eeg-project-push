# ============================================================
# MET MUSIC + EEG PROJECT
# PHASE 5 (PART 1): FINAL FIGURES, TABLES AND INTERPRETATION
# ============================================================
#
# BIG QUESTION:
# What exactly did we find - and what kind of finding is each
# result (descriptive, confirmatory, exploratory)?
#
# We will:
# 23. Assemble the final figures and one results table.
# 24. Build the interpretation worksheet YOU fill in.
#
# Then write report/report.qmd (Step 25) and run
# run_all.R (Step 26).
# ============================================================



# ============================================================
# 0. START
# ============================================================

source(here::here("00_setup", "config.R"))
source(here::here("00_setup", "eeg_functions.R"))

library(tidyverse)
library(patchwork)

p4_tables <- file.path(P4_OUT, "tables")      # inputs from Phase 4
fig_dir   <- file.path(P5_OUT, "figures")     # outputs of this phase
table_dir <- file.path(P5_OUT, "tables")



# ============================================================
# 23. FINAL RESULTS TABLE
# ============================================================
#
# One table that shows every confirmatory test at a glance.
# ============================================================

confirmatory <- read_csv(file.path(p4_tables, "step18_confirmatory_H1_H2.csv"),
                         show_col_types = FALSE)
deviation    <- read_csv(file.path(p4_tables, "step19_consensus_deviation.csv"),
                         show_col_types = FALSE)
h3           <- read_csv(file.path(p4_tables, "step20_H3_random_slopes.csv"),
                         show_col_types = FALSE)
exploratory  <- read_csv(file.path(p4_tables, "step21_exploratory_grid.csv"),
                         show_col_types = FALSE)
sensitivity  <- read_csv(file.path(p4_tables, "step22_sensitivity.csv"),
                         show_col_types = FALSE)
qc           <- read_csv(file.path(P3_OUT, "tables", "qc_table.csv"), show_col_types = FALSE)


fmt_ci <- function(est, lo, hi, digits = 3) {
  sprintf(paste0("%.", digits, "f [%.", digits, "f, %.", digits, "f]"), est, lo, hi)
}

results_table <- bind_rows(
  confirmatory |>
    filter(!is.na(predicted_sign)) |>
    transmute(test = hypothesis, type = "confirmatory",
              estimate_95ci = fmt_ci(estimate, ci_low, ci_high),
              standardized  = fmt_ci(std_estimate, std_ci_low, std_ci_high, 2),
              p = signif(p, 3), supported),
  deviation |>
    transmute(test = hypothesis,
              type = if_else(is.na(predicted_sign), "descriptive", "confirmatory"),
              estimate_95ci = fmt_ci(estimate, ci_low, ci_high),
              standardized  = fmt_ci(std_estimate, std_ci_low, std_ci_high, 2),
              p = signif(p, 3), supported),
  h3 |>
    transmute(test = hypothesis, type = "confirmatory",
              estimate_95ci = sprintf("slope SD = %.3f [%.3f, %.3f]",
                                      slope_sd, slope_sd_ci_low, slope_sd_ci_high),
              standardized = NA_character_,
              p = signif(p_mixture, 3), supported = supported_at_.05)
)

results_table

write_csv(results_table, file.path(table_dir, "final_results_table.csv"))


# QC summary for the report
qc_summary <- qc |>
  summarise(
    participant_song_pairs = n(),
    eeg_recordings         = sum(!is.na(file)),
    included               = sum(included),
    excluded               = sum(!included),
    recordings_with_flagged_channels = sum(!is.na(flagged_channels) & flagged_channels != "")
  )

qc_summary

write_csv(qc_summary, file.path(table_dir, "qc_summary.csv"))



# ------------------------------------------------------------
# 23B. ONE SUMMARY FIGURE: ALL WITHIN-PERSON EFFECTS
# ------------------------------------------------------------

summary_effects <- bind_rows(
  confirmatory |> filter(!is.na(predicted_sign)),
  deviation    |> filter(!is.na(predicted_sign))
)

p_summary <- ggplot(summary_effects,
                    aes(std_estimate, fct_rev(hypothesis))) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(xmin = std_ci_low, xmax = std_ci_high), width = 0.2, orientation = "y") +
  geom_point(size = 2.5) +
  labs(x = "Standardized within-person effect (95% CI)", y = NULL,
       title = "Confirmatory within-person effects") +
  theme_minimal()

p_summary

ggsave(file.path(fig_dir, "p5_confirmatory_summary.png"), p_summary, width = 9, height = 4)



# ============================================================
# 24. INTERPRETATION WORKSHEET (YOU FILL THIS IN)
# ============================================================
#
# One row per finding. For each, write:
#
#   what_data_show    : the descriptive fact
#   what_stats_show   : estimate, CI, p - and what the CI RULES OUT
#   what_we_infer     : cautious interpretation
#   what_is_uncertain : alternative explanations, limitations
#
# RULES:
#   - A non-significant result is NOT "no effect". Use the CI:
#     "effects larger than X are unlikely given these data".
#   - No reverse inference: "lower alpha" does NOT mean
#     "more aroused" - many states lower alpha.
#   - Exploratory hits are hypotheses for future studies,
#     not findings.
# ============================================================

worksheet <- tibble(
  finding = c(
    "Ratings: song vs person variance (Phase 1)",
    "Manipulation check: categories vs ratings (Phase 1)",
    "Valence-arousal correlation (Phase 1)",
    "QC: exclusions and flagged channels (Phase 3)",
    "Step 17: naive vs two-stage vs between-person",
    "H1: posterior alpha ~ within-person arousal",
    "H2: FAA ~ within-person valence",
    "Person-specific (deviation) effects",
    "Song consensus effects",
    "H3: individual differences in slopes",
    "Exploratory grid",
    "Sensitivity + LOSO"
  ),
  type = c("descriptive", "descriptive", "descriptive", "descriptive",
           "methodological", "confirmatory", "confirmatory", "confirmatory",
           "descriptive", "confirmatory", "exploratory", "robustness"),
  what_data_show    = "",
  what_stats_show   = "",
  what_we_infer     = "",
  what_is_uncertain = ""
)

worksheet_file <- file.path(table_dir, "interpretation_worksheet.csv")

if (!file.exists(worksheet_file)) {
  write_csv(worksheet, worksheet_file)   # never overwrite your edits
}

worksheet_file   # open in RStudio / Excel and fill it in



# ============================================================
#                 END OF PHASE 5 (PART 1)
# ============================================================
#
# NEXT:
#   Step 25: write 05_phase5_report/report.qmd
#   Step 26: Session > Restart R, then source("run_all.R")
# ============================================================
