# ============================================================
# MET MUSIC + EEG PROJECT
# PHASE 2: LOOK AT THE EEG BEFORE PROCESSING IT
# ============================================================
#
# BIG QUESTION:
# What is actually inside one EEG recording, and what
# preprocessing does it really need?
#
# We will answer:
# 6.  What is stored in a .set file?
# 7.  What are the channels, units, time axis and bad segments?
# 8.  What do clean EEG and artifacts look like?
# 9.  What reference was used? Is there line noise?
# 10. Are any channels bad?
# 11. Can we cut the music into clean 2-second epochs?
#
# IMPORTANT:
# This phase uses ONE or a few recordings only.
# We are still NOT looking at ratings.
# ============================================================



# ============================================================
# 0. START
# ============================================================

source(here::here("00_setup", "config.R"))          # dataset_path
source(here::here("00_setup", "eeg_functions.R"))   # our EEG functions + settings

library(tidyverse)

fig_dir <- file.path(P2_OUT, "figures")


# The recording we inspect in detail
example_file <- file.path(
  dataset_path,
  "sub-01", "ses-t01", "eeg",
  "sub-01_ses-t01_task-music_eeg.set"
)

file.exists(example_file)   # must be TRUE



# ============================================================
# 6. WHAT IS INSIDE A .set FILE?
# ============================================================
#
# EEGLAB saves a MATLAB "struct". R.matlab reads it as a list.
# The warnings readMat prints are about MATLAB object types
# it cannot convert; they do not affect the data.
# ============================================================

set_raw <- suppressWarnings(R.matlab::readMat(example_file))


# Which fields exist?
names(set_raw)


# Key recording parameters
set_raw$nbchan    # number of channels       -> expect 67
set_raw$pnts      # number of samples        -> expect 131000
set_raw$srate     # samples per second (Hz)  -> expect 1000
set_raw$xmin      # start time (s)           -> expect 0
set_raw$xmax      # end time (s)             -> expect 131
set_raw$ref       # reference label          -> "common"

dim(set_raw$data)         # channels x samples -> 67 x 131000

dim(set_raw$icaweights)   # 0 x 0 = NO ICA decomposition stored



# ============================================================
# 7. BUILD THE PIECES WE NEED
# ============================================================
#
# - channel names
# - time axis (seconds)
# - units
# - bad-segment mask
# - music-window mask
# ============================================================


# ------------------------------------------------------------
# 7A. CHANNEL NAMES
# ------------------------------------------------------------
# chanlocs is a 3-D array: field x 1 x channel.
# We take the "labels" field for every channel.

channel_labels <- unlist(set_raw$chanlocs["labels", , ])

length(channel_labels)    # 67
tail(channel_labels, 3)   # last one should be "EOG"


# ------------------------------------------------------------
# 7B. TIME AXIS
# ------------------------------------------------------------

srate  <- as.numeric(set_raw$srate)
time_s <- (seq_len(ncol(set_raw$data)) - 1) / srate

range(time_s)   # 0 to 130.999


# ------------------------------------------------------------
# 7C. UNITS: VOLTS OR MICROVOLTS?
# ------------------------------------------------------------
# channels.tsv says "V".
# Real scalp EEG is roughly 10-100 MICROvolts.
# If the numbers were volts, they would be ~0.00001.
# Look at the middle 50% of values of one channel:

quantile(set_raw$data[which(channel_labels == "Pz"), ], c(0.25, 0.5, 0.75))

# Values of a few units -> the data are in MICROVOLTS (uV).
# channels.tsv is wrong; we document this in the report.


# ------------------------------------------------------------
# 7D. BAD SEGMENTS
# ------------------------------------------------------------

events_file <- sub("_eeg\\.set$", "_events.tsv", example_file)

events <- readr::read_tsv(events_file, show_col_types = FALSE)

events   # onset (s), duration (s), trial_type = "bad"


# Cross-check with the events stored inside the .set file
# (latency is in SAMPLES there)
tibble(
  type    = unlist(set_raw$event["type", , ]),
  latency = unlist(set_raw$event["latency", , ])
)


bad <- read_bad_mask(example_file, ncol(set_raw$data), srate)

music <- time_s >= MUSIC_ONSET_S & time_s < MUSIC_OFFSET_S

tibble(
  total_bad_s           = sum(bad) / srate,
  bad_inside_music_s    = sum(bad & music) / srate,
  clean_inside_music_s  = sum(music & !bad) / srate     # expect 120
)



# ============================================================
# 8. LOOK AT RAW EEG AND ARTIFACTS
# ============================================================
#
# We draw several channels stacked on top of each other.
# Each channel is shifted vertically so they do not overlap.
# ============================================================

plot_channels <- c("Fp1", "Fp2", "F3", "F4", "Cz", "Pz", "O1", "EOG")

stacked_plot <- function(data, labels, time_s, t_from, t_to,
                         channels, spacing_uv, title) {

  idx <- which(time_s >= t_from & time_s < t_to)

  map_dfr(seq_along(channels), function(i) {
    tibble(
      time    = time_s[idx],
      value   = data[which(labels == channels[i]), idx],
      channel = channels[i],
      offset  = -(i - 1) * spacing_uv
    )
  }) |>
    mutate(
      channel = factor(channel, levels = channels),
      y = value + offset
    ) |>
    ggplot(aes(time, y, group = channel)) +
    geom_line(linewidth = 0.25) +
    scale_y_continuous(
      breaks = -(seq_along(channels) - 1) * spacing_uv,
      labels = channels
    ) +
    labs(x = "Time (s)", y = NULL, title = title) +
    theme_minimal()
}


# ------------------------------------------------------------
# 8A. CLEAN MUSIC SEGMENT (30-40 s)
# ------------------------------------------------------------
# EOG is much larger than EEG, so we plot EEG channels only here.

p_clean <- stacked_plot(
  set_raw$data, channel_labels, time_s,
  t_from = 30, t_to = 40,
  channels = setdiff(plot_channels, "EOG"),
  spacing_uv = 40,
  title = "Clean EEG, 30-40 s (sub-01, t01) - spacing 40 uV"
)

p_clean

ggsave(file.path(fig_dir, "p2_raw_clean.png"), p_clean, width = 9, height = 5)


# ------------------------------------------------------------
# 8B. SEGMENT CONTAINING "bad" ANNOTATIONS (120-131 s)
# ------------------------------------------------------------
# Expect HUGE values (thousands of uV) inside the bad seconds.
# This is why respecting the annotations is non-negotiable.

p_bad <- stacked_plot(
  set_raw$data, channel_labels, time_s,
  t_from = 120, t_to = 131,
  channels = setdiff(plot_channels, "EOG"),
  spacing_uv = 40,
  title = "120-131 s: bad segments start at 127 s"
) +
  annotate("rect", xmin = 127, xmax = 131, ymin = -Inf, ymax = Inf,
           alpha = 0.15, fill = "red")

p_bad

ggsave(file.path(fig_dir, "p2_raw_bad_segment.png"), p_bad, width = 9, height = 5)


# Numbers instead of pictures: max |amplitude| clean vs bad
eeg_rows <- channel_labels != "EOG"

tibble(
  max_abs_clean_uv = max(abs(set_raw$data[eeg_rows, music & !bad])),
  max_abs_bad_uv   = max(abs(set_raw$data[eeg_rows, bad]))
)


# ------------------------------------------------------------
# 8C. BLINK CHECK: DO FRONTAL CHANNELS FOLLOW THE EOG?
# ------------------------------------------------------------
# Blinks are large in the EOG channel. If they were NOT removed
# upstream, Fp1/Fp2 should follow the EOG closely.

clean <- music & !bad

eog_signal <- set_raw$data[which(channel_labels == "EOG"), ]

tibble(
  channel = c("Fp1", "Fp2", "Pz", "O1"),
  sd_uv = map_dbl(channel, ~ sd(set_raw$data[which(channel_labels == .x), clean])),
  cor_with_EOG = map_dbl(channel, ~ cor(set_raw$data[which(channel_labels == .x), clean],
                                        eog_signal[clean]))
) |>
  add_row(channel = "EOG", sd_uv = sd(eog_signal[clean]), cor_with_EOG = 1)


# Overlay Fp1 and EOG (each scaled to z-scores so they fit together)
idx <- which(time_s >= 30 & time_s < 40)

p_blink <- tibble(
  time = time_s[idx],
  Fp1  = as.numeric(scale(set_raw$data[which(channel_labels == "Fp1"), idx])),
  EOG  = as.numeric(scale(eog_signal[idx]))
) |>
  pivot_longer(-time, names_to = "channel", values_to = "z") |>
  ggplot(aes(time, z, colour = channel)) +
  geom_line(linewidth = 0.3) +
  labs(x = "Time (s)", y = "z-score", title = "Fp1 vs EOG (30-40 s)") +
  theme_minimal()

p_blink

ggsave(file.path(fig_dir, "p2_blink_check.png"), p_blink, width = 9, height = 4)

# INTERPRETATION GUIDE:
# - High correlation + matching blink shapes -> blinks remain in EEG.
# - Low correlation, tiny Fp1 SD -> ocular artifacts were probably
#   removed upstream (inherited preprocessing we cannot audit).



# ============================================================
# 9. REFERENCE, LINE NOISE, FIRST SPECTRUM
# ============================================================


# ------------------------------------------------------------
# 9A. WHICH REFERENCE?
# ------------------------------------------------------------
# Average reference = every channel minus the mean of all channels.
# Consequence: the 66 EEG channels SUM TO ZERO at every sample.

channel_sum <- colSums(set_raw$data[eeg_rows, ])

summary(channel_sum)

# Values ~0 (tiny rounding noise) -> already AVERAGE-REFERENCED.
# Decision: do NOT re-reference.


# ------------------------------------------------------------
# 9B. FIRST SPECTRUM (O1 and Fz), 1-80 Hz
# ------------------------------------------------------------
# We cut the clean music window into 2-s pieces and average
# their spectra (Welch's method; explained fully in Phase 3).

pp_example <- preprocess(example_file)

spec <- epoch_psd(
  pp_example$epochs[, , !pp_example$epoch_info$overlaps_bad, drop = FALSE],
  pp_example$srate
)

mean_psd <- apply(spec$psd, c(1, 2), mean)

p_psd <- tibble(
  freq = spec$freqs,
  O1   = mean_psd["O1", ],
  Fz   = mean_psd["Fz", ]
) |>
  pivot_longer(-freq, names_to = "channel", values_to = "psd") |>
  filter(freq >= 1, freq <= 80) |>
  ggplot(aes(freq, log10(psd), colour = channel)) +
  geom_line() +
  geom_vline(xintercept = c(50, 60), linetype = "dashed", alpha = 0.4) +
  labs(
    x = "Frequency (Hz)",
    y = "log10 power (uV^2/Hz)",
    title = "Power spectrum, sub-01 t01 (dashed: 50 / 60 Hz)"
  ) +
  theme_minimal()

p_psd

ggsave(file.path(fig_dir, "p2_first_psd.png"), p_psd, width = 8, height = 4.5)

# WHAT TO LOOK FOR:
# - Falling "1/f" shape.
# - Bump around 8-12 Hz (alpha), bigger at O1 than Fz.
# - Steep drop above ~70 Hz (the existing low-pass filter).
# - A sharp spike at 50 or 60 Hz = line noise.
#   A sharp DIP at 50 Hz = a notch filter was ALREADY applied upstream
#   (this is what sub-01 t01 shows -> 50 Hz mains, undocumented).
#   Our bands stop at 45 Hz, so no notch filter is needed either way.
# - A flat "floor" above ~30 Hz at some channels may be muscle or
#   amplifier noise -> one reason gamma is treated with caution.



# ============================================================
# 10. BAD CHANNELS
# ============================================================
#
# preprocess() already ran detect_bad_channels().
# Look at the result for the example recording:
# ============================================================

pp_example$channel_qc |>
  arrange(desc(abs(robust_z)))

pp_example$channel_qc |>
  filter(flagged)


# A recording KNOWN to contain a flat channel:
file_flat <- file.path(
  dataset_path, "sub-02", "ses-t05", "eeg",
  "sub-02_ses-t05_task-music_eeg.set"
)

pp_flat <- preprocess(file_flat)

pp_flat$channel_qc |>
  filter(flagged)

# EXPECT: one channel with SD = 0, flagged as flat.
# channels.tsv calls it "good" -> never trust metadata blindly.


# Distribution of channel SDs (one recording)
p_chsd <- ggplot(pp_example$channel_qc, aes(sd_uv)) +
  geom_histogram(bins = 30) +
  scale_x_log10() +
  labs(x = "Channel SD in clean music window (uV, log scale)",
       y = "Number of channels",
       title = "Channel variability, sub-01 t01") +
  theme_minimal()

p_chsd



# ============================================================
# 11. EPOCHS: TEST preprocess() ON FOUR RECORDINGS
# ============================================================
#
# For each: how many of the 60 epochs survive?
#
# EXPECT:
#   sub-01 t01 : 60
#   sub-02 t05 : 59  (bad seconds 35-36 fall in one epoch)
#   sub-17 t01 : ~52-53 (106 clean seconds)
#   sub-10 t20 : 60
# ============================================================

test_files <- file.path(
  dataset_path,
  c("sub-01/ses-t01/eeg/sub-01_ses-t01_task-music_eeg.set",
    "sub-02/ses-t05/eeg/sub-02_ses-t05_task-music_eeg.set",
    "sub-17/ses-t01/eeg/sub-17_ses-t01_task-music_eeg.set",
    "sub-10/ses-t20/eeg/sub-10_ses-t20_task-music_eeg.set")
)

epoch_test <- map_dfr(test_files, function(f) {

  pp <- preprocess(f)
  ids <- parse_ids(f)

  tibble(
    participant_id    = ids$participant_id,
    song_id           = ids$song_id,
    clean_s           = pp$clean_s,
    epochs_total      = nrow(pp$epoch_info),
    epochs_overlap_bad = sum(pp$epoch_info$overlaps_bad),
    epochs_over_100uv = sum(!pp$epoch_info$overlaps_bad &
                              pp$epoch_info$max_abs_uv > AMP_THRESH_UV),
    epochs_kept_100uv = sum(!pp$epoch_info$overlaps_bad &
                              pp$epoch_info$max_abs_uv <= AMP_THRESH_UV),
    flagged_channels  = paste(pp$channel_qc$channel[pp$channel_qc$flagged],
                              collapse = ", ")
  )
})

epoch_test

# If MANY epochs exceed 100 uV, stop and investigate before Phase 3.



# ============================================================
#                 END OF PHASE 2
# ============================================================
#
# Decisions made (copy into the preregistration):
#
# - Data are in uV (not V), average-referenced, 0.5-70 Hz filtered.
# - No re-filtering, no re-referencing, no ICA.
# - Music window assumed 5-125 s (no onset marker exists).
# - 2-s non-overlapping epochs; drop epochs overlapping "bad".
# - Drop epochs with any channel beyond +/-100 uV.
# - Flag channels: flat (SD < 0.5 uV) or |robust z| > 3 -> set to NA.
#
# NEXT (Step 12):
# Review and COMMIT 02_phase2_eeg_inspection/PREREGISTRATION.md before Phase 4.
# ============================================================
