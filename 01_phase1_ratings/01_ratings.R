# ============================================================
# MET MUSIC + EEG PROJECT
# PHASE 1: UNDERSTAND THE RATINGS BEFORE TOUCHING THE EEG
# ============================================================
#
# BIG QUESTION:
# What do people feel when they listen to the songs?
#
# We will answer:
# 1. Are the ratings valid?
# 2. Do different people use the rating scales differently?
# 3. Are valence and arousal related?
# 4. Do the song categories produce the expected emotions?
# 5. How much of a rating comes from the SONG vs the PERSON?
# 6. How different is each person's reaction from the group?
# 7. In what order were the songs actually presented?
#
# IMPORTANT:
# This phase uses ONLY the ratings and metadata.
# We are NOT analysing EEG yet.
# ============================================================



# ============================================================
# 0. START THE PROJECT
# ============================================================

# Load the project settings.
# This tells R where the EEG dataset is stored.

source(here::here("00_setup", "config.R"))


# Load the packages we need.

library(tidyverse)
library(lme4)
library(lmerTest)
library(broom.mixed)



# ============================================================
# 1. LOAD THE RATINGS
# ============================================================
#
# The ratings file contains what each person said about each song.
#
# Valence   = unpleasant -------- pleasant
# Arousal   = calm ------------- excited
# Likeability = how much they liked the song
# Familiarity = how familiar the song was
#
# One row = one person's rating of one song.
# ============================================================

ratings <- readr::read_tsv(
  file.path(dataset_path, "ratings.tsv")
)


# How many rows and columns are there?

dim(ratings)


# What are the names of the columns?

names(ratings)


# What kinds of remarks/problems are recorded?

dplyr::count(ratings, Remark)



# ============================================================
# 2. FIND RATINGS WITH SPECIAL REMARKS
# ============================================================
#
# Normally Remark should be empty.
# Here we look for rows where something unusual was recorded.
# ============================================================

ratings |>
  dplyr::filter(!is.na(Remark)) |>
  dplyr::select(
    participant_id,
    song_id,
    Remark
  )



# ============================================================
# 3. CHECK WHETHER THE RATING VALUES MAKE SENSE
# ============================================================
#
# Expected:
#
# Valence:     1 to 9
# Arousal:     1 to 9
# Likeability: 1 to 5
# Familiarity: 1 to 5
#
# We are checking whether anything falls outside these ranges.
# ============================================================

ratings |>
  dplyr::summarise(
    valence_min = min(Valence, na.rm = TRUE),
    valence_max = max(Valence, na.rm = TRUE),
    valence_outside =
      sum(Valence < 1 | Valence > 9, na.rm = TRUE),

    arousal_min = min(Arousal, na.rm = TRUE),
    arousal_max = max(Arousal, na.rm = TRUE),
    arousal_outside =
      sum(Arousal < 1 | Arousal > 9, na.rm = TRUE),

    likeability_min = min(Likeability, na.rm = TRUE),
    likeability_max = max(Likeability, na.rm = TRUE),
    likeability_outside =
      sum(Likeability < 1 | Likeability > 5, na.rm = TRUE),

    familiarity_min = min(Familiarity, na.rm = TRUE),
    familiarity_max = max(Familiarity, na.rm = TRUE),
    familiarity_outside =
      sum(Familiarity < 1 | Familiarity > 5, na.rm = TRUE)
  )



# ============================================================
# 4. FIND RATINGS WITH ZERO LIKEABILITY OR FAMILIARITY
# ============================================================
#
# The dataset documentation suggests these scales normally start
# at 1. We therefore inspect the rows containing 0.
# ============================================================

ratings |>
  dplyr::filter(
    Likeability == 0 |
      Familiarity == 0
  ) |>
  dplyr::select(
    participant_id,
    song_id,
    Likeability,
    Familiarity
  )



# ============================================================
# 5. CREATE THE CLEAN RATING DATA
# ============================================================
#
# One rating was marked:
# sub-01 + t27
#
# This row is excluded from our analysis because its rating
# information is problematic.
#
# IMPORTANT:
# We are NOT deleting the original data.
# "ratings" stays untouched.
# "ratings_clean" is simply our analysis version.
# ============================================================

ratings_clean <- ratings |>
  dplyr::filter(
    !(participant_id == "sub-01" & song_id == "t27")
  )


# Check the number of rows after cleaning.

dim(ratings_clean)



# ============================================================
# 6. CHECK HOW EACH PERSON USES THE RATING SCALE
# ============================================================
#
# Different people may use a scale differently.
#
# Example:
# Person A may use mostly 4-7.
# Person B may use mostly 1-9.
#
# We calculate:
# - average rating
# - standard deviation
# - number of different values used
# ============================================================

participant_scale <- ratings_clean |>
  dplyr::group_by(participant_id) |>
  dplyr::summarise(
    valence_mean =
      mean(Valence, na.rm = TRUE),

    valence_sd =
      sd(Valence, na.rm = TRUE),

    valence_distinct =
      dplyr::n_distinct(Valence),

    arousal_mean =
      mean(Arousal, na.rm = TRUE),

    arousal_sd =
      sd(Arousal, na.rm = TRUE),

    arousal_distinct =
      dplyr::n_distinct(Arousal)
  )


# Look at all participants.

participant_scale



# ============================================================
# 7. FIND PEOPLE WHO USE VERY FEW RATING VALUES
# ============================================================
#
# This does NOT automatically mean they are bad participants.
# We are only flagging them for inspection.
# ============================================================

participant_scale |>
  dplyr::filter(
    valence_sd < 1 |
      arousal_sd < 1 |
      valence_distinct <= 4 |
      arousal_distinct <= 4
  )



# ============================================================
# 8. LOOK AT VALENCE FOR EVERY PERSON
# ============================================================
#
# Each dot = one song rating.
# Large point = that person's average valence.
# ============================================================

ggplot(
  ratings_clean,
  aes(
    x = participant_id,
    y = Valence
  )
) +
  geom_jitter(
    width = 0.15,
    height = 0.1,
    alpha = 0.6
  ) +
  stat_summary(
    fun = mean,
    geom = "point",
    size = 3
  ) +
  scale_y_continuous(
    breaks = 1:9
  ) +
  labs(
    x = "Participant",
    y = "Valence",
    title = "Valence ratings by participant"
  ) +
  theme_minimal()



# ============================================================
# 9. CHECK FOR MISSING OR INVALID VALENCE VALUES
# ============================================================

ratings_clean |>
  dplyr::summarise(
    missing_valence =
      sum(is.na(Valence)),

    outside_valence =
      sum(
        Valence < 1 |
          Valence > 9,
        na.rm = TRUE
      )
  )



# ============================================================
# 10. QUESTION:
#     ARE VALENCE AND AROUSAL RELATED?
# ============================================================
#
# Spearman correlation asks:
#
# When valence goes up, does arousal generally go up too?
#
# We first calculate this across everyone.
# ============================================================

pooled_cor <- cor(
  ratings_clean$Valence,
  ratings_clean$Arousal,
  method = "spearman"
)

pooled_cor



# ============================================================
# 11. CHECK VALENCE-AROUSAL RELATIONSHIP PERSON BY PERSON
# ============================================================
#
# Instead of treating everyone as one giant person,
# calculate one correlation for each participant.
# ============================================================

participant_cor <- ratings_clean |>
  dplyr::group_by(participant_id) |>
  dplyr::summarise(
    valence_arousal_cor =
      cor(
        Valence,
        Arousal,
        method = "spearman"
      )
  )

participant_cor



# Summarise the participant correlations.

participant_cor |>
  dplyr::summarise(
    mean_cor =
      mean(valence_arousal_cor),

    min_cor =
      min(valence_arousal_cor),

    max_cor =
      max(valence_arousal_cor)
  )



# ============================================================
# 12. FIND THE SONG CATEGORIES
# ============================================================
#
# The dataset contains intended emotional categories.
#
# HVHA = High Valence, High Arousal
# HVLA = High Valence, Low Arousal
# LVHA = Low Valence, High Arousal
# LVLA = Low Valence, Low Arousal
# N    = Neutral
#
# We first ask R what categories actually exist.
# ============================================================

unique(
  ratings_clean$`Song Catergory`
)



# ============================================================
# 13. CHECK WHETHER THE SONG CATEGORIES WORKED
# ============================================================
#
# For every category:
# calculate the average valence and average arousal.
#
# This is called a MANIPULATION CHECK.
#
# We are asking:
# "Did the songs actually make people feel what
#  the experimenters intended?"
# ============================================================

category_summary <- ratings_clean |>
  dplyr::group_by(`Song Catergory`) |>
  dplyr::summarise(
    mean_valence =
      mean(Valence, na.rm = TRUE),

    mean_arousal =
      mean(Arousal, na.rm = TRUE),

    .groups = "drop"
  )


category_summary



# ============================================================
# 14. CALCULATE THE AVERAGE EXPERIENCE OF EACH SONG
# ============================================================
#
# Each song was heard by many people.
#
# Here we calculate:
# "On average, how did people experience THIS song?"
#
# One row = one song.
# ============================================================

song_summary <- ratings_clean |>
  dplyr::group_by(
    song_id,
    `Song Catergory`
  ) |>
  dplyr::summarise(
    mean_valence =
      mean(Valence, na.rm = TRUE),

    mean_arousal =
      mean(Arousal, na.rm = TRUE),

    .groups = "drop"
  )


song_summary



# ============================================================
# 15. DRAW THE EMOTIONAL MAP OF THE SONGS
# ============================================================
#
# X axis = valence
# Y axis = arousal
#
# Each dot = one song.
#
# Colour = the category the experimenters intended.
# ============================================================

ggplot(
  song_summary,
  aes(
    x = mean_valence,
    y = mean_arousal,
    colour = `Song Catergory`
  )
) +
  geom_point(size = 3) +
  scale_x_continuous(
    breaks = 1:9
  ) +
  scale_y_continuous(
    breaks = 1:9
  ) +
  labs(
    x = "Mean valence",
    y = "Mean arousal",
    colour = "Intended category",
    title = "Song-level mean valence and arousal"
  ) +
  theme_minimal()


# Save this figure for the report
ggsave(
  file.path(P1_OUT, "figures", "p1_song_map.png"),
  width = 8, height = 5
)



# ============================================================
# 16. STEP 4:
#     HOW MUCH COMES FROM THE PERSON?
#     HOW MUCH COMES FROM THE SONG?
# ============================================================
#
# The same song can feel different to different people.
#
# We want to separate:
#
# PERSON effect
# SONG effect
# RANDOM / UNEXPLAINED variation
#
# We do this separately for:
# - Valence
# - Arousal
# ============================================================


# ------------------------------------------------------------
# 16A. VALENCE MODEL
# ------------------------------------------------------------

valence_model <- lme4::lmer(
  Valence ~ 1 +
    (1 | participant_id) +
    (1 | song_id),
  data = ratings_clean,
  REML = TRUE
)


# ------------------------------------------------------------
# 16B. AROUSAL MODEL
# ------------------------------------------------------------

arousal_model <- lme4::lmer(
  Arousal ~ 1 +
    (1 | participant_id) +
    (1 | song_id),
  data = ratings_clean,
  REML = TRUE
)



# ============================================================
# 17. LOOK AT THE VARIANCE COMPONENTS
# ============================================================
#
# This tells us how much variation comes from:
#
# - participant
# - song
# - residual / everything else
# ============================================================

VarCorr(valence_model)

VarCorr(arousal_model)



# ============================================================
# 18. TURN THE VARIANCES INTO PERCENTAGES
# ============================================================
#
# We calculate:
#
# participant variance / total variance
# song variance / total variance
# residual variance / total variance
#
# The three percentages together should equal 100%.
# ============================================================

variance_proportions <- function(model) {

  vc <- as.data.frame(
    VarCorr(model)
  )

  participant_var <-
    vc$vcov[
      vc$grp == "participant_id"
    ]

  song_var <-
    vc$vcov[
      vc$grp == "song_id"
    ]

  residual_var <-
    vc$vcov[
      vc$grp == "Residual"
    ]

  total_var <-
    participant_var +
    song_var +
    residual_var

  tibble(
    participant =
      participant_var / total_var,

    song =
      song_var / total_var,

    residual =
      residual_var / total_var
  )
}


# Valence percentages

valence_variance <-
  variance_proportions(
    valence_model
  )

valence_variance


# Arousal percentages

arousal_variance <-
  variance_proportions(
    arousal_model
  )

arousal_variance



# ============================================================
# 19. CALCULATE SONG CONSENSUS
# ============================================================
#
# IMPORTANT:
#
# We do NOT use the person's own rating when calculating
# the average for that song.
#
# Example:
#
# 5 people rate a song:
#
#  Person A = 8
#  Person B = 7
#  Person C = 6
#  Person D = 5
#  Person E = 4
#
# For Person A:
#
# consensus = (7 + 6 + 5 + 4) / 4
#           = 5.5
#
# NOT:
#
# (8 + 7 + 6 + 5 + 4) / 5
#
# ============================================================

ratings_deviation <- ratings_clean |>
  dplyr::group_by(song_id) |>
  dplyr::mutate(

    # -----------------------------
    # VALENCE
    # -----------------------------

    song_sum_valence =
      sum(Valence, na.rm = TRUE),

    song_n_valence =
      sum(!is.na(Valence)),

    consensus_valence =
      (
        song_sum_valence - Valence
      ) /
      (
        song_n_valence - 1
      ),


    # -----------------------------
    # AROUSAL
    # -----------------------------

    song_sum_arousal =
      sum(Arousal, na.rm = TRUE),

    song_n_arousal =
      sum(!is.na(Arousal)),

    consensus_arousal =
      (
        song_sum_arousal - Arousal
      ) /
      (
        song_n_arousal - 1
      ),


    # -----------------------------
    # PERSONAL DIFFERENCE
    # -----------------------------

    deviation_valence =
      Valence - consensus_valence,

    deviation_arousal =
      Arousal - consensus_arousal

  ) |>
  dplyr::ungroup()



# ============================================================
# 20. REMOVE EACH PERSON'S GENERAL RATING HABIT
# ============================================================
#
# Some people generally give high ratings.
# Some people generally give low ratings.
#
# We subtract each person's average deviation.
#
# What remains is:
#
# "How unusually high or low did THIS person rate
#  THIS song compared with other songs?"
# ============================================================

ratings_deviation <- ratings_deviation |>
  dplyr::group_by(participant_id) |>
  dplyr::mutate(

    deviation_valence_centered =
      deviation_valence -
      mean(
        deviation_valence,
        na.rm = TRUE
      ),

    deviation_arousal_centered =
      deviation_arousal -
      mean(
        deviation_arousal,
        na.rm = TRUE
      )

  ) |>
  dplyr::ungroup()



# ============================================================
# 21. MEASURE HOW MUCH PEOPLE DIFFER FROM THE SONG CONSENSUS
# ============================================================
#
# SD = standard deviation.
#
# Larger SD means people differ more from one another.
#
# We calculate this for:
# - song consensus
# - personal deviation
# - centred personal deviation
# ============================================================

ratings_deviation |>
  dplyr::summarise(

    sd_consensus_valence =
      sd(
        consensus_valence,
        na.rm = TRUE
      ),

    sd_deviation_valence =
      sd(
        deviation_valence,
        na.rm = TRUE
      ),

    sd_deviation_valence_centered =
      sd(
        deviation_valence_centered,
        na.rm = TRUE
      ),


    sd_consensus_arousal =
      sd(
        consensus_arousal,
        na.rm = TRUE
      ),

    sd_deviation_arousal =
      sd(
        deviation_arousal,
        na.rm = TRUE
      ),

    sd_deviation_arousal_centered =
      sd(
        deviation_arousal_centered,
        na.rm = TRUE
      )

  )



# ============================================================
# 22. CHECK WHETHER CONSENSUS AND PERSONAL DEVIATION ARE RELATED
# ============================================================
#
# We use Spearman correlation.
#
# We want to know whether:
#
# "Songs that are generally rated high also produce
#  systematically different personal deviations."
#
# ============================================================

cor_valence <- cor(
  ratings_deviation$consensus_valence,
  ratings_deviation$deviation_valence,
  method = "spearman",
  use = "complete.obs"
)


cor_arousal <- cor(
  ratings_deviation$consensus_arousal,
  ratings_deviation$deviation_arousal,
  method = "spearman",
  use = "complete.obs"
)


cor_valence

cor_arousal



# ============================================================
# 23. STEP 5:
#     WHEN WERE THE SONGS PRESENTED?
# ============================================================
#
# We need to know the order in which each participant
# listened to the songs.
#
# Why?
#
# Imagine everyone heard Song A first and Song B last.
#
# If people become tired later in the experiment,
# brain activity could change because of TIME,
# not because of the music.
#
# Therefore we need the real presentation order.
# ============================================================


# Find every scans.tsv file in the dataset.

scan_files <- list.files(
  dataset_path,
  pattern = "_scans\\.tsv$",
  recursive = TRUE,
  full.names = TRUE
)


# How many scans files did we find?

length(scan_files)



# ============================================================
# 24. READ ALL PRESENTATION-TIME FILES
# ============================================================

scans <- purrr::map_dfr(
  scan_files,
  ~ readr::read_tsv(
      .x,
      show_col_types = FALSE
    ) |>
    dplyr::mutate(
      source_file = .x
    )
)


# What columns exist?

names(scans)


# How many rows and columns?

dim(scans)



# ============================================================
# 25. LOOK AT THE ACQUISITION TIMES
# ============================================================
#
# acq_time = when the recording happened.
# ============================================================

scans |>
  dplyr::select(
    source_file,
    dplyr::everything()
  ) |>
  head()



# ============================================================
# 26. FIND THE PARTICIPANT AND SESSION FROM THE FILE NAME
# ============================================================
#
# Example:
#
# sub-01/ses-t05/...
#
# becomes:
#
# participant_id = sub-01
# session_id     = ses-t05
# ============================================================

scans_order <- scans |>
  dplyr::mutate(

    participant_id =
      stringr::str_extract(
        source_file,
        "sub-[0-9]+"
      ),

    session_id =
      stringr::str_extract(
        source_file,
        "ses-t[0-9]+"
      )

  )



# ============================================================
# 27. LOOK AT THE RECORDING TIMES
# ============================================================

scans_order |>
  dplyr::select(
    participant_id,
    session_id,
    acq_time
  ) |>
  dplyr::arrange(
    participant_id,
    acq_time
  )



# ============================================================
# 28. CHECK WHETHER THE TIMES ARE REAL AND UNIQUE
# ============================================================
#
# We want to know:
#
# 1. How many recordings are there?
# 2. How many have missing times?
# 3. How many different times exist?
# ============================================================

scans_order |>
  dplyr::summarise(
    n_rows =
      dplyr::n(),

    n_missing_acq_time =
      sum(is.na(acq_time)),

    n_unique_acq_time =
      dplyr::n_distinct(acq_time)
  )



# ============================================================
# 29. GIVE EACH SONG A PRESENTATION ORDER
# ============================================================
#
# Earliest recording = trial 1
# Next recording     = trial 2
# ...
# ============================================================

scans_order <- scans_order |>
  dplyr::group_by(participant_id) |>
  dplyr::arrange(
    acq_time,
    .by_group = TRUE
  ) |>
  dplyr::mutate(
    trial_order = dplyr::row_number()
  ) |>
  dplyr::ungroup()



# ============================================================
# 30. SEE THE PRESENTATION ORDER FOR EVERY PARTICIPANT
# ============================================================

scans_order |>
  dplyr::select(
    participant_id,
    session_id,
    acq_time,
    trial_order
  ) |>
  dplyr::arrange(
    participant_id,
    trial_order
  )



# ============================================================
# 31. CHECK WHETHER EVERYONE HEARD SONGS IN THE SAME ORDER
# ============================================================
#
# If everyone has the same order:
#     presentation order may be fixed.
#
# If people have different orders:
#     presentation order may have been randomised.
# ============================================================

order_matrix <- scans_order |>
  dplyr::select(
    participant_id,
    session_id,
    trial_order
  ) |>
  tidyr::pivot_wider(
    names_from = participant_id,
    values_from = trial_order
  )


order_matrix



# ============================================================
# 32. CHECK THE ORDER IN ratings.tsv
# ============================================================
#
# This gives us the order in which ratings appear in the file.
#
# We will compare this with the actual EEG acquisition order.
# ============================================================

ratings_order <- ratings_clean |>
  dplyr::group_by(participant_id) |>
  dplyr::mutate(
    rating_row_order =
      dplyr::row_number()
  ) |>
  dplyr::ungroup()


ratings_order |>
  dplyr::select(
    participant_id,
    song_id,
    rating_row_order
  )



# ============================================================
# 33. SAVE OUR CLEANED RATING DATA
# ============================================================
#
# This creates a file containing:
#
# - original ratings
# - song consensus
# - personal deviation
# - centred personal deviation
#
# We will use this later when connecting ratings to EEG.
# ============================================================

readr::write_tsv(
  ratings_deviation,
  file.path(P1_OUT, "tables", "ratings_with_consensus_deviation.tsv")
)



# ============================================================
#                 END OF PHASE 1
# ============================================================
#
# We have now examined:
#
# 1. Whether the rating data are valid.
# 2. How people use the rating scales.
# 3. Whether valence and arousal are related.
# 4. Whether the song categories worked.
# 5. How much variation comes from people vs songs.
# 6. How much each person differs from the song consensus.
# 7. Whether presentation order can be determined.
#
# NEXT PHASE:
# START LOOKING AT THE ACTUAL EEG.
# ============================================================


# ============================================================
