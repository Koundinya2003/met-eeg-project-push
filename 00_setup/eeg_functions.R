# ============================================================
# MET MUSIC + EEG PROJECT
# EEG HELPER FUNCTIONS (used by Phases 2, 3 and 4)
# ============================================================
#
# Every analysis decision lives HERE, in one place, so that:
#
# 1. Phase 2 (one recording) and Phase 3 (all 399 recordings)
#    use exactly the same rules.
# 2. The preregistration can point to exact numbers.
#
# If you change a number below AFTER preregistering,
# you must report it as a deviation.
# ============================================================



# ============================================================
# 0. FIXED ANALYSIS SETTINGS
# ============================================================

# Timing (from the README; there is NO onset marker in the data)
MUSIC_ONSET_S  <- 5      # music starts 5 s after recording start
MUSIC_OFFSET_S <- 125    # music ends after 120 s of playback
EPOCH_S        <- 2      # epoch length -> 0.5 Hz frequency resolution

# Bad-channel rules
FLAT_SD_UV   <- 0.5      # SD below this = flat (dead) channel
ROBUST_Z_MAX <- 3        # |robust z of log SD| above this = extreme channel

# Epoch rejection rules
AMP_THRESH_UV        <- 100   # primary: drop epoch if any channel exceeds +/-100 uV
AMP_THRESH_STRICT_UV <- 75    # sensitivity analysis only

# Trial exclusion rule
MIN_EPOCHS <- 30         # fewer than 30 clean epochs (60 s) -> trial excluded


# Frequency bands (lower edge included, upper edge excluded)
EEG_BANDS <- tibble::tribble(
  ~band,   ~f_lo, ~f_hi,
  "delta",     1,     4,
  "theta",     4,     8,
  "alpha",     8,    13,
  "beta",     13,    30,
  "gamma",    30,    45
)

TOTAL_RANGE <- c(1, 45)   # used for relative power


# Regions of interest (ROIs)
ROIS <- list(
  posterior       = c("O1", "O2", "Oz", "PO3", "PO4", "POz", "Pz"),
  frontal_midline = c("Fz", "FCz"),
  left_frontal    = c("F3", "F5", "F7", "AF3", "FC3"),
  right_frontal   = c("F4", "F6", "F8", "AF4", "FC4"),
  central         = c("C1", "C2", "C3", "C4", "Cz"),
  left_temporal   = c("T7", "TP7", "FT7"),
  right_temporal  = c("T8", "TP8", "FT8")
)



# ============================================================
# 1. READ ONE EEGLAB .set FILE
# ============================================================
#
# R.matlab::readMat() returns the EEGLAB fields directly:
# data, srate, nbchan, pnts, ref, chanlocs, event, ...
#
# data = channels x samples matrix, in MICROVOLTS
# (channels.tsv says "V", but the magnitudes show it is uV).
# ============================================================

read_set <- function(set_file) {

  m <- tryCatch(
    suppressWarnings(R.matlab::readMat(set_file)),
    error = function(e) e
  )

  # Some files make readMat fail on fields we do not need
  # (e.g. sub-01 t09). Then we read the data matrix directly.
  if (inherits(m, "error")) {
    return(read_set_binary(set_file, conditionMessage(m)))
  }

  # chanlocs is a 3-D array: field x 1 x channel
  labels <- unlist(m$chanlocs["labels", , ])

  data <- m$data
  rownames(data) <- labels

  list(
    data   = data,
    srate  = as.numeric(m$srate),
    labels = labels,
    ref    = as.character(m$ref),
    n_ica  = length(m$icaweights),   # 0 = no ICA stored in the file
    reader = "R.matlab",
    file   = set_file
  )
}



# ------------------------------------------------------------
# 1B. FALLBACK READER: THE DATA MATRIX STRAIGHT FROM THE BYTES
# ------------------------------------------------------------
#
# A MATLAB v5 file = 128-byte header, then "elements".
# In these files the FIRST element is the variable "data":
#
#   tag (type 14 = matrix, size)
#   flags | dimensions (67 x 131000) | name ("data")
#   values (type 7 = single precision, column-major order)
#
# Channel names come from channels.tsv (identical order in
# all 399 recordings - checked). Sampling rate = 1000 Hz.
#
# If the file is TRUNCATED (fewer values than the dimensions
# promise, as in sub-12 t05), we stop with a clear error.
# ------------------------------------------------------------

read_set_binary <- function(set_file, original_error = "") {

  con <- file(set_file, "rb")
  on.exit(close(con))

  read_int <- function(n = 1) readBin(con, "integer", n, size = 4, endian = "little")

  readBin(con, "raw", 128)                         # header

  matrix_tag <- read_int(2)
  if (matrix_tag[1] != 14) stop("Unexpected MAT layout. readMat error: ", original_error)

  read_int(4)                                      # array flags (tag + 8 bytes)

  dims_tag <- read_int(2)
  dims <- read_int(dims_tag[2] / 4)
  if (dims_tag[2] %% 8 != 0) readBin(con, "raw", 8 - dims_tag[2] %% 8)

  name_tag <- read_int(1)
  if (bitwShiftR(name_tag, 16) > 0) {              # "small element": name fits in 4 bytes
    readBin(con, "raw", 4)
  } else {
    name_len <- read_int(1)
    readBin(con, "raw", name_len + (8 - name_len %% 8) %% 8)
  }

  value_tag  <- read_int(2)
  value_size <- if (value_tag[1] == 7) 4 else if (value_tag[1] == 9) 8 else
    stop("Unsupported data type ", value_tag[1])

  n_expected <- value_tag[2] / value_size

  values <- readBin(con, "double", n_expected, size = value_size, endian = "little")

  if (length(values) < n_expected) {
    stop(sprintf("FILE TRUNCATED: expected %d values, found %d (%.0f%%)",
                 n_expected, length(values), 100 * length(values) / n_expected))
  }

  data <- matrix(values, nrow = dims[1], ncol = dims[2])

  channels_file <- sub("_eeg\\.set$", "_channels.tsv", set_file)
  labels <- readr::read_tsv(channels_file, show_col_types = FALSE)$name

  rownames(data) <- labels

  list(
    data   = data,
    srate  = 1000,
    labels = labels,
    ref    = NA_character_,
    n_ica  = NA_integer_,
    reader = "binary fallback",
    file   = set_file
  )
}



# ============================================================
# 2. TURN THE "bad" ANNOTATIONS INTO A TRUE/FALSE MASK
# ============================================================
#
# events.tsv lists bad segments as onset + duration (seconds).
# We mark every sample inside a bad segment as TRUE.
# ============================================================

read_bad_mask <- function(set_file, n_samples, srate) {

  events_file <- sub("_eeg\\.set$", "_events.tsv", set_file)

  events <- readr::read_tsv(events_file, show_col_types = FALSE)

  bad_events <- events[events$trial_type == "bad", ]

  bad <- rep(FALSE, n_samples)

  for (i in seq_len(nrow(bad_events))) {

    first_sample <- floor(bad_events$onset[i] * srate) + 1

    last_sample <- min(
      n_samples,
      floor((bad_events$onset[i] + bad_events$duration[i]) * srate)
    )

    bad[first_sample:last_sample] <- TRUE
  }

  bad
}



# ============================================================
# 3. DETECT BAD CHANNELS
# ============================================================
#
# Two rules, applied to CLEAN music-window samples only:
#
# FLAT    : SD < 0.5 uV  (no real signal)
# EXTREME : |robust z| > 3, where
#           robust z = (log SD - median log SD) / MAD
#
# Why log SD? Channel SDs are skewed; logs make them symmetric.
# Why median/MAD? A few bad channels cannot distort them,
# unlike the mean/SD.
# ============================================================

detect_bad_channels <- function(eeg, clean_idx) {

  # Almost no clean data (e.g. sub-18 t17): channel QC is
  # impossible, and the trial will fail the epoch rule anyway.
  if (length(clean_idx) < 2) {
    return(tibble::tibble(
      channel = rownames(eeg), sd_uv = NA_real_, robust_z = NA_real_,
      flat = FALSE, extreme = FALSE, flagged = FALSE
    ))
  }

  channel_sd <- apply(eeg[, clean_idx, drop = FALSE], 1, sd)

  flat <- channel_sd < FLAT_SD_UV

  robust_z <- rep(NA_real_, length(channel_sd))

  log_sd <- log(channel_sd[!flat])

  robust_z[!flat] <- (log_sd - median(log_sd)) / mad(log_sd)

  extreme <- !flat & abs(robust_z) > ROBUST_Z_MAX

  tibble::tibble(
    channel  = rownames(eeg),
    sd_uv    = channel_sd,
    robust_z = robust_z,
    flat     = flat,
    extreme  = extreme,
    flagged  = flat | extreme
  )
}



# ============================================================
# 4. PREPROCESS ONE RECORDING
# ============================================================
#
# Steps (in this order):
#
# 1. Read data, drop the EOG channel from the EEG matrix.
# 2. Build the bad-sample mask and the music-window mask.
# 3. Detect bad channels -> set them to NA.
# 4. Cut the music window (5-125 s) into 60 epochs of 2 s.
# 5. Mark epochs that overlap ANY bad sample.
# 6. Record each epoch's maximum absolute amplitude
#    (the amplitude threshold is applied later, so we can
#     run the 100 uV and 75 uV versions from the same data).
#
# NOT done (and why):
# - No new filtering: data are already 0.5-70 Hz filtered.
# - No re-referencing: data are already average-referenced.
# - No ICA: not available in the files, not standard in R.
# ============================================================

preprocess <- function(set_file) {

  rec <- read_set(set_file)

  srate     <- rec$srate
  n_samples <- ncol(rec$data)

  eeg <- rec$data[rec$labels != "EOG", , drop = FALSE]
  eog <- rec$data[rec$labels == "EOG", ]

  bad <- read_bad_mask(set_file, n_samples, srate)

  time_s <- (seq_len(n_samples) - 1) / srate

  music <- time_s >= MUSIC_ONSET_S & time_s < MUSIC_OFFSET_S

  clean_idx <- which(music & !bad)


  # --- bad channels -------------------------------------------
  channel_qc <- detect_bad_channels(eeg, clean_idx)

  eeg[channel_qc$flagged, ] <- NA


  # --- epochs -------------------------------------------------
  epoch_len <- EPOCH_S * srate

  epoch_starts <- seq(
    from = MUSIC_ONSET_S * srate + 1,
    to   = MUSIC_OFFSET_S * srate - epoch_len + 1,
    by   = epoch_len
  )

  n_epochs <- length(epoch_starts)

  epochs <- array(
    NA_real_,
    dim      = c(nrow(eeg), epoch_len, n_epochs),
    dimnames = list(rownames(eeg), NULL, NULL)
  )

  overlaps_bad <- logical(n_epochs)
  max_abs_uv   <- numeric(n_epochs)

  for (k in seq_len(n_epochs)) {

    idx <- epoch_starts[k]:(epoch_starts[k] + epoch_len - 1)

    epochs[, , k] <- eeg[, idx]

    overlaps_bad[k] <- any(bad[idx])

    max_abs_uv[k] <- suppressWarnings(max(abs(eeg[, idx]), na.rm = TRUE))
  }

  epoch_info <- tibble::tibble(
    epoch        = seq_len(n_epochs),
    start_s      = (epoch_starts - 1) / srate,
    overlaps_bad = overlaps_bad,
    max_abs_uv   = max_abs_uv
  )

  list(
    file       = set_file,
    srate      = srate,
    ref        = rec$ref,
    n_ica      = rec$n_ica,
    reader     = rec$reader,
    clean_s    = length(clean_idx) / srate,
    channel_qc = channel_qc,
    epochs     = epochs,
    epoch_info = epoch_info,
    eog        = eog,
    bad        = bad,
    time_s     = time_s
  )
}



# ============================================================
# 5. POWER SPECTRUM OF EVERY EPOCH (Welch building block)
# ============================================================
#
# For each channel and each epoch:
#
# 1. Remove the epoch mean.
# 2. Multiply by a Hann window (tapers the edges to zero,
#    which reduces "spectral leakage").
# 3. FFT -> squared magnitude -> power spectral density (PSD).
# 4. Keep 0 ... srate/2 and double the non-edge bins
#    (one-sided spectrum).
#
# Units: uV^2 / Hz.
# Averaging these epoch spectra = Welch's method.
# ============================================================

epoch_psd <- function(epochs, srate) {

  n_channels <- dim(epochs)[1]
  n_samples  <- dim(epochs)[2]
  n_epochs   <- dim(epochs)[3]

  hann <- 0.5 - 0.5 * cos(2 * pi * (0:(n_samples - 1)) / n_samples)

  window_power <- sum(hann^2)

  freqs <- (0:(n_samples / 2)) * srate / n_samples

  n_freqs <- length(freqs)

  psd <- array(
    NA_real_,
    dim      = c(n_channels, n_freqs, n_epochs),
    dimnames = list(dimnames(epochs)[[1]], freqs, NULL)
  )

  for (ch in seq_len(n_channels)) {

    x <- matrix(epochs[ch, , ], nrow = n_samples, ncol = n_epochs)

    if (all(is.na(x))) next

    x <- sweep(x, 2, colMeans(x))

    spectrum <- mvfft(x * hann)

    power <- Mod(spectrum[1:n_freqs, , drop = FALSE])^2 / (srate * window_power)

    power[2:(n_freqs - 1), ] <- 2 * power[2:(n_freqs - 1), ]

    psd[ch, , ] <- power
  }

  list(psd = psd, freqs = freqs)
}



# ============================================================
# 6. BAND POWER FROM AN AVERAGE SPECTRUM
# ============================================================
#
# band power = sum of PSD inside the band x frequency step
#            = area under the spectrum (uV^2)
#
# relative power = band power / total power (1-45 Hz)
# ============================================================

band_power_table <- function(mean_psd, freqs) {

  df <- freqs[2] - freqs[1]

  total_bins <- freqs >= TOTAL_RANGE[1] & freqs < TOTAL_RANGE[2]

  total_power <- rowSums(mean_psd[, total_bins, drop = FALSE]) * df

  purrr::map_dfr(seq_len(nrow(EEG_BANDS)), function(b) {

    bins <- freqs >= EEG_BANDS$f_lo[b] & freqs < EEG_BANDS$f_hi[b]

    power <- rowSums(mean_psd[, bins, drop = FALSE]) * df

    tibble::tibble(
      channel     = rownames(mean_psd),
      band        = EEG_BANDS$band[b],
      power_uv2   = power,
      log10_power = log10(power),
      rel_power   = power / total_power
    )
  })
}



# ============================================================
# 7. FEATURES FOR ONE PREPROCESSED RECORDING
# ============================================================
#
# Returns:
#   $channel_features : one row per amp threshold x channel x band
#   $qc               : one row per amp threshold (QC numbers)
# ============================================================

compute_features <- function(pp,
                             thresholds = c(AMP_THRESH_UV, AMP_THRESH_STRICT_UV)) {

  not_bad <- !pp$epoch_info$overlaps_bad

  ids <- parse_ids(pp$file)

  spectra <- if (any(not_bad)) {
    epoch_psd(pp$epochs[, , not_bad, drop = FALSE], pp$srate)
  } else {
    NULL
  }

  max_abs_not_bad <- pp$epoch_info$max_abs_uv[not_bad]

  results <- purrr::map(thresholds, function(th) {

    keep <- max_abs_not_bad <= th

    n_keep <- sum(keep)

    qc_row <- tibble::tibble(
      participant_id      = ids$participant_id,
      song_id             = ids$song_id,
      amp_thresh_uv       = th,
      epochs_total        = nrow(pp$epoch_info),
      epochs_overlap_bad  = sum(pp$epoch_info$overlaps_bad),
      epochs_over_amp     = sum(!keep),
      epochs_kept         = n_keep
    )

    if (n_keep == 0) {
      return(list(features = NULL, qc = qc_row))
    }

    mean_psd <- apply(spectra$psd[, , keep, drop = FALSE], c(1, 2), mean)

    feats <- band_power_table(mean_psd, spectra$freqs) |>
      dplyr::mutate(
        participant_id = ids$participant_id,
        song_id        = ids$song_id,
        amp_thresh_uv  = th,
        n_epochs       = n_keep,
        .before = 1
      )

    list(features = feats, qc = qc_row)
  })

  list(
    channel_features = dplyr::bind_rows(purrr::map(results, "features")),
    qc               = dplyr::bind_rows(purrr::map(results, "qc"))
  )
}



# ============================================================
# 8. SMALL UTILITIES
# ============================================================

# "sub-01/ses-t05/..." -> participant_id = "sub-01", song_id = "t05"
parse_ids <- function(path) {
  list(
    participant_id = stringr::str_extract(path, "sub-[0-9]+"),
    song_id        = stringr::str_remove(stringr::str_extract(path, "ses-t[0-9]+"), "ses-")
  )
}


# Channel features -> ROI features + frontal alpha asymmetry (FAA)
#
# ROI value = mean of log10 power over the ROI's AVAILABLE channels
# FAA       = ln(alpha F4) - ln(alpha F3)
#             (positive = relatively more LEFT-frontal activity,
#              because alpha is treated as inversely related to activity)
roi_features <- function(channel_features) {

  roi_lookup <- tibble::enframe(ROIS, name = "roi", value = "channel") |>
    tidyr::unnest(channel)

  roi_tbl <- channel_features |>
    dplyr::inner_join(roi_lookup, by = "channel", relationship = "many-to-many") |>
    dplyr::group_by(participant_id, song_id, amp_thresh_uv, roi, band) |>
    dplyr::summarise(
      log10_power     = mean(log10_power, na.rm = TRUE),
      log10_rel_power = mean(log10(rel_power), na.rm = TRUE),
      n_channels      = sum(!is.na(power_uv2)),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      log10_power     = dplyr::if_else(n_channels == 0, NA_real_, log10_power),
      log10_rel_power = dplyr::if_else(n_channels == 0, NA_real_, log10_rel_power)
    )

  faa_tbl <- channel_features |>
    dplyr::filter(band == "alpha", channel %in% c("F3", "F4")) |>
    dplyr::select(participant_id, song_id, amp_thresh_uv, channel, power_uv2, rel_power) |>
    tidyr::pivot_wider(names_from = channel, values_from = c(power_uv2, rel_power)) |>
    dplyr::mutate(
      faa     = log(power_uv2_F4) - log(power_uv2_F3),
      faa_rel = log(rel_power_F4) - log(rel_power_F3)
    ) |>
    dplyr::select(participant_id, song_id, amp_thresh_uv, faa, faa_rel)

  list(roi = roi_tbl, faa = faa_tbl)
}
