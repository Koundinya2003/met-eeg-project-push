# ============================================================
# MET MUSIC + EEG PROJECT
# PHASE 3: FROM EEG SIGNALS TO NUMBERS (FEATURES) + QC
# ============================================================
#
# BIG QUESTION:
# How do we turn 120 s of 66-channel EEG into a few
# meaningful numbers per song, and can we trust them?
#
# We will answer:
# 13. Does our spectrum code give the right answer on a
#     signal where we KNOW the answer?
# 14. What are band power, ROI power and frontal asymmetry?
# 15. Run all 399 recordings + build the QC table.
# 16. Do the features look like real EEG? (sanity checks)
#
# IMPORTANT:
# We still do NOT relate EEG to ratings in this phase.
# ============================================================



# ============================================================
# 0. START
# ============================================================

source(here::here("analysis", "setup", "config.R"))
source(here::here("analysis", "setup", "eeg_functions.R"))

library(tidyverse)

fig_dir <- FIG_FEATURES
res_dir <- TAB_FEATURES



# ============================================================
# 13. VALIDATE THE SPECTRUM CODE ON A KNOWN SIGNAL
# ============================================================
#
# A Fourier transform says: "this signal = a sum of sine waves;
# here is how much power each frequency has."
#
# Before trusting it on EEG, test it on a fake signal:
#
#   10 Hz sine wave, amplitude 10 uV, plus random noise
#
# EXPECT:
#   - a peak at exactly 10 Hz
#   - Parseval check: total power in spectrum ~= signal variance
# ============================================================

set.seed(1)

fake_srate   <- 1000
fake_n       <- 2 * fake_srate          # 2-s epochs, like the real data
fake_epochs  <- 60
fake_time    <- (0:(fake_n - 1)) / fake_srate

fake <- array(NA_real_, c(1, fake_n, fake_epochs), dimnames = list("fake", NULL, NULL))

for (k in 1:fake_epochs) {
  fake[1, , k] <- 10 * sin(2 * pi * 10 * fake_time + runif(1, 0, 2 * pi)) +
                  rnorm(fake_n, sd = 2)
}

fake_spec <- epoch_psd(fake, fake_srate)

fake_mean_psd <- apply(fake_spec$psd, c(1, 2), mean)

# Where is the peak?
fake_spec$freqs[which.max(fake_mean_psd[1, ])]          # expect 10


# Parseval check: area under spectrum vs variance of the signal
df <- fake_spec$freqs[2] - fake_spec$freqs[1]

parseval_ratio <- (sum(fake_mean_psd[1, ]) * df) / mean(apply(fake[1, , ], 2, var))

parseval_ratio                                          # expect ~1


p_fake <- tibble(freq = fake_spec$freqs, psd = fake_mean_psd[1, ]) |>
  filter(freq <= 40) |>
  ggplot(aes(freq, log10(psd))) +
  geom_line() +
  labs(x = "Frequency (Hz)", y = "log10 power",
       title = "Validation: 10 Hz sine + noise") +
  theme_minimal()

p_fake

ggsave(file.path(fig_dir, "p3_validation_sine.png"), p_fake, width = 7, height = 4)



# ------------------------------------------------------------
# 13B. REAL SPECTRA FOR ONE RECORDING
# ------------------------------------------------------------
# Frequency resolution = 1 / epoch length = 1 / 2 s = 0.5 Hz.
# Longer epochs -> finer resolution but FEWER epochs to average
# (noisier). 2 s is a common compromise.

example_file <- file.path(dataset_path, "sub-01", "ses-t01", "eeg",
                          "sub-01_ses-t01_task-music_eeg.set")

pp_example <- preprocess(example_file)

keep_example <- !pp_example$epoch_info$overlaps_bad &
                 pp_example$epoch_info$max_abs_uv <= AMP_THRESH_UV

spec_example <- epoch_psd(pp_example$epochs[, , keep_example, drop = FALSE],
                          pp_example$srate)

mean_psd_example <- apply(spec_example$psd, c(1, 2), mean)

p_spec <- as_tibble(t(mean_psd_example[c("O1", "Oz", "Fz", "F3", "F4"), ])) |>
  mutate(freq = spec_example$freqs) |>
  pivot_longer(-freq, names_to = "channel", values_to = "psd") |>
  filter(freq >= 1, freq < 45) |>
  ggplot(aes(freq, log10(psd), colour = channel)) +
  geom_line() +
  annotate("rect", xmin = 8, xmax = 13, ymin = -Inf, ymax = Inf, alpha = 0.1) +
  labs(x = "Frequency (Hz)", y = "log10 power (uV^2/Hz)",
       title = "Spectra, sub-01 t01 (shaded = alpha 8-13 Hz)") +
  theme_minimal()

p_spec

ggsave(file.path(fig_dir, "p3_spectra_example.png"), p_spec, width = 8, height = 4.5)



# ============================================================
# 14. BAND POWER, ROIs AND FRONTAL ALPHA ASYMMETRY
# ============================================================
#
# BAND POWER = area under the spectrum inside a band (uV^2)
#
#   delta 1-4, theta 4-8, alpha 8-13, beta 13-30, gamma 30-45 Hz
#
# WHY LOG?
#   Power is very skewed (a few huge values). log10 makes it
#   roughly symmetric and turns "twice as much" into "+0.30".
#
# ROI = average of log10 power over a group of channels
#   (e.g. posterior = O1, O2, Oz, PO3, PO4, POz, Pz)
#
# FAA = ln(alpha at F4) - ln(alpha at F3)
#   Higher FAA = relatively MORE left-frontal activity
#   (alpha is treated as inversely related to activity).
# ============================================================

feat_example <- compute_features(pp_example)

feat_example$qc

feat_example$channel_features |>
  filter(amp_thresh_uv == AMP_THRESH_UV, band == "alpha",
         channel %in% c("O1", "Oz", "Pz", "Fz", "F3", "F4"))


roi_example <- roi_features(feat_example$channel_features)

roi_example$roi |>
  filter(amp_thresh_uv == AMP_THRESH_UV, band == "alpha")

roi_example$faa

# EXPECT: posterior alpha > frontal alpha; FAA within about +/-0.5



# ============================================================
# 15. RUN ALL 399 RECORDINGS + QC TABLE
# ============================================================
#
# purrr::safely() means: if ONE file fails, record the error
# and keep going, instead of crashing the whole run.
#
# Runtime: roughly 1-2 s per file -> ~10 minutes.
# ============================================================

set_files <- list.files(
  dataset_path,
  pattern    = "_eeg\\.set$",
  recursive  = TRUE,
  full.names = TRUE
)

length(set_files)   # must be 399


process_one <- function(set_file) {

  pp <- preprocess(set_file)

  feats <- compute_features(pp)

  ids <- parse_ids(set_file)

  recording_qc <- tibble(
    participant_id    = ids$participant_id,
    song_id           = ids$song_id,
    file              = basename(set_file),
    reader            = pp$reader,
    reference         = pp$ref,
    n_ica_weights     = pp$n_ica,
    clean_s           = pp$clean_s,
    n_flat_channels   = sum(pp$channel_qc$flat),
    n_extreme_channels = sum(pp$channel_qc$extreme),
    flagged_channels  = paste(pp$channel_qc$channel[pp$channel_qc$flagged],
                              collapse = ", ")
  )

  list(
    channel_features = feats$channel_features,
    epoch_qc         = feats$qc,
    recording_qc     = recording_qc
  )
}

safe_process <- safely(process_one)

start_time <- Sys.time()

batch <- map(set_files, safe_process, .progress = TRUE)

Sys.time() - start_time


# ------------------------------------------------------------
# 15A. DID ANY FILE FAIL?
# ------------------------------------------------------------

failed <- map_lgl(batch, ~ !is.null(.x$error))

sum(failed)                     # expect 1: sub-12 t05 is truncated in the dataset

set_files[failed]               # which ones (if any)

map_chr(batch[failed], ~ conditionMessage(.x$error))


# ------------------------------------------------------------
# 15B. COMBINE RESULTS
# ------------------------------------------------------------

ok <- batch[!failed]

channel_features <- map_dfr(ok, ~ .x$result$channel_features)
epoch_qc         <- map_dfr(ok, ~ .x$result$epoch_qc)
recording_qc     <- map_dfr(ok, ~ .x$result$recording_qc)


# ------------------------------------------------------------
# 15C. BUILD THE QC TABLE (ONE ROW PER RECORDING)
# ------------------------------------------------------------
# A recording is INCLUDED if at least 30 clean epochs (60 s)
# survive the primary 100 uV rule.

qc_table <- recording_qc |>
  left_join(
    epoch_qc |>
      filter(amp_thresh_uv == AMP_THRESH_UV) |>
      select(participant_id, song_id, epochs_total, epochs_overlap_bad,
             epochs_over_amp, epochs_kept),
    by = c("participant_id", "song_id")
  ) |>
  left_join(
    epoch_qc |>
      filter(amp_thresh_uv == AMP_THRESH_STRICT_UV) |>
      select(participant_id, song_id, epochs_kept_75uv = epochs_kept),
    by = c("participant_id", "song_id")
  ) |>
  mutate(
    included = epochs_kept >= MIN_EPOCHS,
    exclusion_reason = case_when(
      included ~ NA_character_,
      TRUE ~ paste0("only ", epochs_kept, " clean epochs (< ", MIN_EPOCHS, ")")
    )
  )

# Add failed files (if any) so EVERY recording is accounted for
if (any(failed)) {
  qc_table <- bind_rows(
    qc_table,
    tibble(
      participant_id   = map_chr(set_files[failed], ~ parse_ids(.x)$participant_id),
      song_id          = map_chr(set_files[failed], ~ parse_ids(.x)$song_id),
      file             = basename(set_files[failed]),
      included         = FALSE,
      exclusion_reason = paste("processing error:",
                               map_chr(batch[failed], ~ conditionMessage(.x$error)))
    )
  )
}

# Add the one participant-song with NO EEG file at all
qc_table <- bind_rows(
  qc_table,
  tibble(participant_id = "sub-17", song_id = "t17",
         file = NA_character_, included = FALSE,
         exclusion_reason = "EEG file missing from dataset")
) |>
  arrange(participant_id, song_id)

nrow(qc_table)                   # 400 = 399 recordings + 1 missing

count(qc_table, included)

qc_table |> filter(!included)    # every exclusion, with its reason

qc_table |> filter(flagged_channels != "") |>
  select(participant_id, song_id, flagged_channels)


# Summary numbers for the report
qc_table |>
  filter(!is.na(clean_s)) |>
  summarise(
    recordings_processed    = n(),
    read_with_fallback      = sum(reader == "binary fallback"),
    median_clean_s          = median(clean_s),
    min_clean_s             = min(clean_s),
    median_epochs_kept      = median(epochs_kept),
    total_epochs_over_100uv = sum(epochs_over_amp),
    recordings_with_flagged = sum(flagged_channels != ""),
    recordings_with_ica     = sum(n_ica_weights > 0, na.rm = TRUE),
    references              = paste(unique(na.omit(reference)), collapse = ", ")
  )


# ------------------------------------------------------------
# 15D. SAVE
# ------------------------------------------------------------

write_csv(channel_features, file.path(res_dir, "bandpower_channels.csv"))
write_csv(qc_table,         file.path(res_dir, "qc_table.csv"))



# ============================================================
# 16. SANITY CHECKS (EEG ONLY - NO RATINGS)
# ============================================================

rois <- roi_features(channel_features)

roi_tbl <- rois$roi
faa_tbl <- rois$faa

write_csv(roi_tbl, file.path(res_dir, "bandpower_roi.csv"))
write_csv(faa_tbl, file.path(res_dir, "faa.csv"))


included_trials <- qc_table |>
  filter(included) |>
  select(participant_id, song_id)

roi_primary <- roi_tbl |>
  filter(amp_thresh_uv == AMP_THRESH_UV) |>
  semi_join(included_trials, by = c("participant_id", "song_id"))


# ------------------------------------------------------------
# 16A. MEAN BAND POWER PER ROI
# ------------------------------------------------------------
# EXPECT: alpha highest in the posterior ROI.

p_roi <- roi_primary |>
  mutate(band = factor(band, levels = EEG_BANDS$band)) |>
  group_by(roi, band) |>
  summarise(mean_log10 = mean(log10_power, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(band, mean_log10, colour = roi, group = roi)) +
  geom_line() + geom_point() +
  labs(x = NULL, y = "Mean log10 band power (uV^2)",
       title = "Band power by ROI (all included trials)") +
  theme_minimal()

p_roi

ggsave(file.path(fig_dir, "p3_band_by_roi.png"), p_roi, width = 8, height = 4.5)


# ------------------------------------------------------------
# 16B. ALPHA "TOPOGRAPHY" (electrode positions, top view)
# ------------------------------------------------------------

electrodes <- read_tsv(
  file.path(dataset_path, "sub-01", "ses-t01", "eeg",
            "sub-01_ses-t01_space-CapTrak_electrodes.tsv"),
  show_col_types = FALSE
)

alpha_by_channel <- channel_features |>
  filter(amp_thresh_uv == AMP_THRESH_UV, band == "alpha") |>
  semi_join(included_trials, by = c("participant_id", "song_id")) |>
  group_by(channel) |>
  summarise(mean_log10_alpha = mean(log10_power, na.rm = TRUE), .groups = "drop") |>
  left_join(electrodes, by = c("channel" = "name"))

p_topo <- ggplot(alpha_by_channel, aes(x, y, colour = mean_log10_alpha)) +
  geom_point(size = 7) +
  geom_text(aes(label = channel), colour = "white", size = 2) +
  scale_colour_viridis_c() +
  coord_equal() +
  labs(title = "Mean log10 alpha power (top view, nose up)",
       colour = "log10 alpha") +
  theme_void()

p_topo

ggsave(file.path(fig_dir, "p3_alpha_topography.png"), p_topo, width = 7, height = 7)


# ------------------------------------------------------------
# 16C. PARTICIPANT DIFFERENCES IN POSTERIOR ALPHA
# ------------------------------------------------------------
# EXPECT: big differences between people.
# -> this is why models need a random intercept per participant.

p_subj <- roi_primary |>
  filter(roi == "posterior", band == "alpha") |>
  ggplot(aes(participant_id, log10_power)) +
  geom_jitter(width = 0.15, alpha = 0.5) +
  stat_summary(fun = mean, geom = "point", size = 3, colour = "red") +
  labs(x = "Participant", y = "Posterior log10 alpha",
       title = "Posterior alpha: each dot = one song") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90))

p_subj

ggsave(file.path(fig_dir, "p3_alpha_by_participant.png"), p_subj, width = 9, height = 4.5)


# How much of posterior alpha variance is BETWEEN people?
roi_primary |>
  filter(roi == "posterior", band == "alpha") |>
  group_by(participant_id) |>
  mutate(person_mean = mean(log10_power)) |>
  ungroup() |>
  summarise(
    total_var   = var(log10_power),
    between_var = var(person_mean),
    share_between_person = between_var / total_var
  )


# ------------------------------------------------------------
# 16D. FAA DISTRIBUTION
# ------------------------------------------------------------

faa_primary <- faa_tbl |>
  filter(amp_thresh_uv == AMP_THRESH_UV) |>
  semi_join(included_trials, by = c("participant_id", "song_id"))

summary(faa_primary$faa)

p_faa <- ggplot(faa_primary, aes(faa)) +
  geom_histogram(bins = 40) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  labs(x = "FAA = ln(alpha F4) - ln(alpha F3)", y = "Trials",
       title = "Frontal alpha asymmetry, all included trials") +
  theme_minimal()

p_faa

ggsave(file.path(fig_dir, "p3_faa_hist.png"), p_faa, width = 7, height = 4)


# ------------------------------------------------------------
# 16E. GAMMA CHECK (MUSCLE?)
# ------------------------------------------------------------
# Muscle activity (jaw, temples) produces broadband high-frequency
# power, strongest at temporal sites.

roi_primary |>
  filter(band == "gamma") |>
  group_by(roi) |>
  summarise(mean_log10_gamma = mean(log10_power, na.rm = TRUE)) |>
  arrange(desc(mean_log10_gamma))


# ------------------------------------------------------------
# 16F. MERGE WITH RATINGS (COUNT ROWS ONLY - NO PLOTS!)
# ------------------------------------------------------------

ratings_dev <- read_tsv(
  file.path(TAB_RATINGS, "ratings_with_consensus_deviation.tsv"),
  show_col_types = FALSE
)

analysis_trials <- included_trials |>
  inner_join(ratings_dev, by = c("participant_id", "song_id"))

nrow(analysis_trials)   # 398 minus EEG-excluded trials

count(analysis_trials, participant_id) |> arrange(n)   # trials per person



# ============================================================
#                 END OF PHASE 3
# ============================================================
#
# Saved:
#   results/tables/features/bandpower_channels.csv
#   results/tables/features/bandpower_roi.csv
#   results/tables/features/faa.csv
#   results/tables/features/qc_table.csv  (all 400 participant-songs)
#
# NEXT:
# PREREGISTRATION.md must be COMMITTED before Phase 4.
# ============================================================
