# ============================================================
# MET MUSIC + EEG PROJECT
# PHASE 4: STATISTICS - TESTING THE PREREGISTERED HYPOTHESES
# ============================================================
#
# BIG QUESTION:
# Is emotional experience related to EEG band power WITHIN
# people, and does it survive when we look only at the
# PERSONAL part of the experience?
#
# We will answer:
# 17. Why pooling ~400 trials gives misleading answers.
# 18. H1 and H2 with mixed-effects models.
# 19. Song consensus vs personal deviation.
# 20. H3: do people differ in their EEG-experience slopes?
# 21. Exploratory analyses (FDR-corrected, clearly labelled).
# 22. Diagnostics and sensitivity analyses.
#
# IMPORTANT:
# This script REFUSES to run unless PREREGISTRATION.md is
# committed in git. That is deliberate.
# ============================================================



# ============================================================
# 0. START + PREREGISTRATION CHECK
# ============================================================

source(here::here("analysis", "setup", "config.R"))
source(here::here("analysis", "setup", "eeg_functions.R"))

library(tidyverse)
library(lme4)
library(lmerTest)

p3_tables <- TAB_FEATURES   # inputs from 03_feature_extraction.R
fig_dir   <- FIG_STATS      # outputs of this script
table_dir <- TAB_STATS

prereg_file <- PREREG_FILE
prereg_rel  <- "preregistration/PREREGISTRATION.md"

if (!file.exists(prereg_file)) {
  stop("PREREGISTRATION.md not found. Write and commit it before Phase 4.")
}

prereg_commit <- suppressWarnings(system2(
  "git",
  # --follow tracks the file through renames (it was moved into
  # preregistration/ when the project was reorganised). The rename
  # itself does not change the text, so --diff-filter=AM skips it and
  # reports the last commit that actually added or edited the content.
  c("-C", shQuote(here::here()), "log", "--follow", "--diff-filter=AM",
    "-1", "--format=%cI", "--", prereg_rel),
  stdout = TRUE, stderr = FALSE
))

if (length(prereg_commit) == 0 || prereg_commit[1] == "") {
  stop("PREREGISTRATION.md is not committed in git. Run:\n",
       "  git init\n  git add ", prereg_rel, "\n  git commit -m 'Preregistration'\n",
       "then re-run this script.")
}

prereg_dirty <- suppressWarnings(system2(
  "git",
  c("-C", shQuote(here::here()), "status", "--porcelain", "--", prereg_rel),
  stdout = TRUE, stderr = FALSE
))

if (length(prereg_dirty) > 0) {
  warning("PREREGISTRATION.md has UNCOMMITTED edits. ",
          "Any change after the commit must be reported as a deviation.")
}

cat("Preregistration committed at:", prereg_commit[1], "\n")



# ============================================================
# 1. BUILD THE TRIAL TABLE (ONE ROW = ONE PERSON x SONG)
# ============================================================

qc          <- read_csv(file.path(p3_tables, "qc_table.csv"), show_col_types = FALSE)
roi         <- read_csv(file.path(p3_tables, "bandpower_roi.csv"), show_col_types = FALSE)
faa         <- read_csv(file.path(p3_tables, "faa.csv"), show_col_types = FALSE)
ratings_dev <- read_tsv(file.path(TAB_RATINGS, "ratings_with_consensus_deviation.tsv"),
                        show_col_types = FALSE)


# ROI power in wide format: one column per ROI x band,
# e.g. "posterior_alpha"
roi_wide <- function(value_col, threshold, suffix = "") {
  roi |>
    filter(amp_thresh_uv == threshold) |>
    select(participant_id, song_id, roi, band, value = all_of(value_col)) |>
    mutate(name = paste0(roi, "_", band, suffix)) |>
    select(-roi, -band) |>
    pivot_wider(names_from = name, values_from = value)
}

eeg_primary <- roi_wide("log10_power", AMP_THRESH_UV)

eeg_sensitivity <- roi_wide("log10_rel_power", AMP_THRESH_UV, "_rel") |>
  select(participant_id, song_id, posterior_alpha_rel) |>
  left_join(
    roi_wide("log10_power", AMP_THRESH_STRICT_UV, "_75") |>
      select(participant_id, song_id, posterior_alpha_75),
    by = c("participant_id", "song_id")
  )

faa_wide <- faa |>
  filter(amp_thresh_uv == AMP_THRESH_UV) |>
  select(participant_id, song_id, faa, faa_rel) |>
  left_join(
    faa |>
      filter(amp_thresh_uv == AMP_THRESH_STRICT_UV) |>
      select(participant_id, song_id, faa_75 = faa),
    by = c("participant_id", "song_id")
  )


trials <- qc |>
  filter(included) |>
  select(participant_id, song_id) |>
  inner_join(ratings_dev, by = c("participant_id", "song_id")) |>
  left_join(eeg_primary,     by = c("participant_id", "song_id")) |>
  left_join(eeg_sensitivity, by = c("participant_id", "song_id")) |>
  left_join(faa_wide,        by = c("participant_id", "song_id")) |>
  mutate(                                  # short names for the H1 outcomes
    post_alpha     = posterior_alpha,
    post_alpha_rel = posterior_alpha_rel,
    post_alpha_75  = posterior_alpha_75
  )

nrow(trials)                                  # analysable trials
n_distinct(trials$participant_id)             # 20

trials |> summarise(missing_post_alpha = sum(is.na(post_alpha)),
                    missing_faa        = sum(is.na(faa)))



# ============================================================
# 2. HELPER: PREPARE ONE ANALYSIS DATASET
# ============================================================
#
# For a given outcome (EEG) and predictor (rating):
#
# x_within  = rating - this person's mean rating
#             "Did this person rate THIS song higher than usual?"
#
# x_between = this person's mean - everyone's mean
#             "Is this a person who rates everything high?"
#
# Keeping them separate prevents between-person differences
# from masquerading as within-person effects.
# ============================================================

prepare <- function(data, outcome, predictor) {

  d <- data |>
    filter(!is.na(.data[[outcome]]), !is.na(.data[[predictor]])) |>
    mutate(y = .data[[outcome]], x = .data[[predictor]])

  # Exclusion rule: participant rating SD must be > 0
  zero_sd <- d |>
    group_by(participant_id) |>
    summarise(sd_x = sd(x), .groups = "drop") |>
    filter(is.na(sd_x) | sd_x == 0) |>
    pull(participant_id)

  if (length(zero_sd) > 0) {
    message("Excluded (rating SD = 0 for ", predictor, "): ",
            paste(zero_sd, collapse = ", "))
  }

  d |>
    filter(!participant_id %in% zero_sd) |>
    group_by(participant_id) |>
    mutate(x_pmean = mean(x), x_within = x - x_pmean) |>
    ungroup() |>
    mutate(x_between = x_pmean - mean(x))
}


# Consensus / deviation version
#   consensus_c      = leave-one-out song mean, grand-mean centred
#   deviation_within = (rating - consensus), person-mean centred
prepare_deviation <- function(data, outcome, rating = c("valence", "arousal")) {

  rating <- match.arg(rating)

  data |>
    filter(!is.na(.data[[outcome]])) |>
    mutate(
      y         = .data[[outcome]],
      consensus = .data[[paste0("consensus_", rating)]],
      deviation = .data[[paste0("deviation_", rating)]]
    ) |>
    group_by(participant_id) |>
    mutate(deviation_within = deviation - mean(deviation)) |>
    ungroup() |>
    mutate(consensus_c = consensus - mean(consensus))
}


# Within-person SD of a variable (used for standardized effects)
within_sd <- function(v, person) sd(v - ave(v, person))



# ============================================================
# 17. WHY POOLING IS WRONG - SHOWN WITH OUR OWN DATA
# ============================================================
#
# (a) NAIVE: treat every trial as independent.   (INVALID)
# (b) TWO-STAGE: one correlation per person, then test the
#     20 correlations across people.             (VALID, simple)
# (c) BETWEEN-PERSON: person means vs person means (n = 20).
#     This answers a DIFFERENT question.
# ============================================================

fisher_ci <- function(r, n) {
  se <- 1 / sqrt(n - 3)
  c(tanh(atanh(r) - 1.96 * se), tanh(atanh(r) + 1.96 * se))
}

pooling_demo <- function(data, outcome, predictor, label) {

  d <- data |> filter(!is.na(.data[[outcome]]), !is.na(.data[[predictor]]))

  # (a) naive
  naive <- suppressWarnings(cor.test(d[[outcome]], d[[predictor]],
                                     method = "spearman", exact = FALSE))
  naive_ci <- fisher_ci(naive$estimate, nrow(d))

  # (b) two-stage
  per_person <- d |>
    group_by(participant_id) |>
    summarise(r = suppressWarnings(cor(.data[[outcome]], .data[[predictor]],
                                       method = "spearman")),
              .groups = "drop") |>
    filter(is.finite(atanh(r)))

  z  <- atanh(per_person$r)
  tt <- t.test(z)

  # (c) between-person
  means <- d |>
    group_by(participant_id) |>
    summarise(mean_y = mean(.data[[outcome]]), mean_x = mean(.data[[predictor]]),
              .groups = "drop")

  between <- suppressWarnings(cor.test(means$mean_y, means$mean_x,
                                       method = "spearman", exact = FALSE))
  between_ci <- fisher_ci(between$estimate, nrow(means))

  tibble(
    analysis = label,
    method   = c("(a) naive pooled - INVALID", "(b) two-stage within-person",
                 "(c) between-person means"),
    n        = c(nrow(d), length(z), nrow(means)),
    unit     = c("trials", "participants", "participants"),
    r        = c(naive$estimate, tanh(mean(z)), between$estimate),
    ci_low   = c(naive_ci[1], tanh(tt$conf.int[1]), between_ci[1]),
    ci_high  = c(naive_ci[2], tanh(tt$conf.int[2]), between_ci[2]),
    p        = c(naive$p.value, tt$p.value, between$p.value)
  )
}

step17 <- bind_rows(
  pooling_demo(trials, "post_alpha", "Arousal", "H1: posterior alpha ~ arousal"),
  pooling_demo(trials, "faa",        "Valence", "H2: FAA ~ valence")
)

step17

write_csv(step17, file.path(table_dir, "step17_pooling_demo.csv"))


p17 <- ggplot(step17, aes(r, method)) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y") +
  geom_point(size = 2) +
  facet_wrap(~ analysis, ncol = 1) +
  labs(x = "Spearman r (95% CI)", y = NULL,
       title = "Same data, three analyses: the naive CI is far too narrow") +
  theme_minimal()

p17

ggsave(file.path(fig_dir, "p4_step17_pooling.png"), p17, width = 8, height = 5)



# ============================================================
# 18. H1 AND H2: MIXED-EFFECTS MODELS
# ============================================================
#
# A mixed model uses ALL trials but knows they come from 20
# people:
#
#   (1 | participant_id)            each person has their own
#                                   baseline EEG level
#   (1 + x_within | participant_id) ...and their own slope
#
# Singular fit = the model estimated a variance of ~0 or a
# correlation of +/-1; it cannot support that complexity.
# Preregistered fallback: drop the correlation, then the slope.
# ============================================================

# Is the PARTICIPANT part of the random effects singular?
# (A near-zero SONG variance is harmless and is not a reason to
#  simplify the participant structure.)
participant_singular <- function(m, tol = 1e-4) {
  theta <- lme4::getME(m, "theta")
  lower <- lme4::getME(m, "lower")
  part  <- startsWith(names(theta), "participant_id")
  any(lower[part] == 0 & theta[part] < tol)
}

fit_with_fallback <- function(fixed, slope_var, data, extra_random = "") {

  structures <- c(
    full           = paste0("(1 + ", slope_var, " | participant_id)"),
    no_correlation = paste0("(1 + ", slope_var, " || participant_id)"),
    intercept_only = "(1 | participant_id)"
  )

  for (s in names(structures)) {

    f <- as.formula(paste(fixed, "+", structures[[s]], extra_random))

    m <- suppressMessages(lmerTest::lmer(f, data = data, REML = TRUE))

    if (!participant_singular(m)) {
      note <- if (lme4::isSingular(m)) " (song variance ~0)" else ""
      return(list(model = m, structure = paste0(s, note), formula = f))
    }
  }

  list(model = m, structure = paste(s, "(participant variance ~0)"), formula = f)
}


extract_effect <- function(fit, term, data, hypothesis, predicted_sign = NA,
                           alpha = 0.025) {

  m  <- fit$model
  co <- summary(m)$coefficients

  est <- co[term, "Estimate"]
  se  <- co[term, "Std. Error"]
  dfv <- co[term, "df"]
  p   <- co[term, "Pr(>|t|)"]

  ci <- tryCatch({
    pr <- suppressWarnings(suppressMessages(
      confint(m, parm = term, method = "profile", quiet = TRUE)
    ))
    list(low = pr[1, 1], high = pr[1, 2], method = "profile")
  }, error = function(e) {
    list(low  = est - qt(0.975, dfv) * se,
         high = est + qt(0.975, dfv) * se,
         method = "Wald")
  })

  # Standardized effect: change in outcome (in within-person SDs)
  # for a 1 within-person-SD change in the predictor
  std_factor <- sd(data[[term]]) / within_sd(data$y, data$participant_id)

  tibble(
    hypothesis,
    term,
    random_structure = fit$structure,
    n_trials         = nrow(data),
    n_participants   = n_distinct(data$participant_id),
    estimate         = est,
    ci_low           = ci$low,
    ci_high          = ci$high,
    ci_method        = ci$method,
    std_estimate     = est * std_factor,
    std_ci_low       = ci$low * std_factor,
    std_ci_high      = ci$high * std_factor,
    df               = dfv,
    p                = p,
    predicted_sign   = predicted_sign,
    supported        = if (is.na(predicted_sign)) NA else
                         (sign(est) == predicted_sign & p < alpha)
  )
}


# ------------------------------------------------------------
# 18A. H1: posterior alpha ~ arousal (predicted NEGATIVE)
# ------------------------------------------------------------

d_h1 <- prepare(trials, "post_alpha", "Arousal")

fit_h1 <- fit_with_fallback("y ~ x_within + x_between", "x_within", d_h1)

fit_h1$structure
summary(fit_h1$model)

res_h1 <- extract_effect(fit_h1, "x_within", d_h1,
                         "H1: posterior alpha ~ within-person arousal",
                         predicted_sign = -1)


# ------------------------------------------------------------
# 18B. H2: FAA ~ valence (predicted POSITIVE)
# ------------------------------------------------------------

d_h2 <- prepare(trials, "faa", "Valence")

fit_h2 <- fit_with_fallback("y ~ x_within + x_between", "x_within", d_h2)

fit_h2$structure
summary(fit_h2$model)

res_h2 <- extract_effect(fit_h2, "x_within", d_h2,
                         "H2: FAA ~ within-person valence",
                         predicted_sign = +1)


# Between-person terms (descriptive, not confirmatory)
res_between <- bind_rows(
  extract_effect(fit_h1, "x_between", d_h1, "H1 between-person (descriptive)"),
  extract_effect(fit_h2, "x_between", d_h2, "H2 between-person (descriptive)")
)


confirmatory <- bind_rows(res_h1, res_h2)

confirmatory

write_csv(bind_rows(confirmatory, res_between),
          file.path(table_dir, "step18_confirmatory_H1_H2.csv"))

# HOW TO READ:
# estimate     = change in log10 alpha (H1) / FAA (H2) per 1 rating point
#                above the person's own average
# std_estimate = same, in standardized (within-person SD) units
# supported    = predicted sign AND p < .025



# ============================================================
# 19. SONG CONSENSUS vs PERSONAL DEVIATION
# ============================================================
#
# consensus_c      : how the OTHER listeners rated this song
#                    (mostly the music itself, incl. acoustics)
# deviation_within : how much THIS person departed from them
#                    (the person-specific experience)
#
# (1 | song_id) gives every song its own EEG baseline, which
# absorbs song-level acoustic effects on the EEG.
# ============================================================

d_dev_h1 <- prepare_deviation(trials, "post_alpha", "arousal")

fit_dev_h1 <- fit_with_fallback("y ~ consensus_c + deviation_within",
                                "deviation_within", d_dev_h1,
                                extra_random = "+ (1 | song_id)")

summary(fit_dev_h1$model)


d_dev_h2 <- prepare_deviation(trials, "faa", "valence")

fit_dev_h2 <- fit_with_fallback("y ~ consensus_c + deviation_within",
                                "deviation_within", d_dev_h2,
                                extra_random = "+ (1 | song_id)")

summary(fit_dev_h2$model)


step19 <- bind_rows(
  extract_effect(fit_dev_h1, "deviation_within", d_dev_h1,
                 "H1 person-specific: alpha ~ arousal deviation", predicted_sign = -1),
  extract_effect(fit_dev_h1, "consensus_c", d_dev_h1,
                 "H1 song consensus (descriptive, confounded with acoustics)"),
  extract_effect(fit_dev_h2, "deviation_within", d_dev_h2,
                 "H2 person-specific: FAA ~ valence deviation", predicted_sign = +1),
  extract_effect(fit_dev_h2, "consensus_c", d_dev_h2,
                 "H2 song consensus (descriptive, confounded with acoustics)")
)

step19

write_csv(step19, file.path(table_dir, "step19_consensus_deviation.csv"))



# ============================================================
# 20. H3: DO PEOPLE DIFFER IN THEIR SLOPES?
# ============================================================
#
# Compare two models:
#   m0: everyone shares ONE slope
#   m1: every person has their OWN slope
#
# Likelihood-ratio test. Because a variance cannot be negative,
# the usual chi-square p is too conservative; we use a 50:50
# mixture of chi2(1) and chi2(2) (preregistered).
# ============================================================

h3_test <- function(d, label) {

  m1 <- suppressMessages(lmerTest::lmer(
    y ~ x_within + x_between + (1 + x_within | participant_id), data = d, REML = TRUE))

  m0 <- suppressMessages(lmerTest::lmer(
    y ~ x_within + x_between + (1 | participant_id), data = d, REML = TRUE))

  lr <- max(0, as.numeric(2 * (logLik(m1) - logLik(m0))))

  vc <- as.data.frame(VarCorr(m1))
  slope_sd <- vc$sdcor[vc$grp == "participant_id" & vc$var1 == "x_within" & is.na(vc$var2)]

  sd_ci <- tryCatch({
    ci <- suppressWarnings(suppressMessages(
      confint(m1, parm = "theta_", method = "profile", oldNames = FALSE, quiet = TRUE)))
    ci["sd_x_within|participant_id", ]
  }, error = function(e) c(NA_real_, NA_real_))

  list(
    m1 = m1,
    table = tibble(
      hypothesis   = label,
      lr_statistic = lr,
      p_naive_chi2_df2 = pchisq(lr, 2, lower.tail = FALSE),
      p_mixture        = 0.5 * pchisq(lr, 1, lower.tail = FALSE) +
                         0.5 * pchisq(lr, 2, lower.tail = FALSE),
      slope_sd     = slope_sd,
      slope_sd_ci_low  = sd_ci[1],
      slope_sd_ci_high = sd_ci[2],
      m1_singular  = lme4::isSingular(m1),
      supported_at_.05 = (0.5 * pchisq(lr, 1, lower.tail = FALSE) +
                          0.5 * pchisq(lr, 2, lower.tail = FALSE)) < 0.05
    )
  )
}

h3_h1 <- h3_test(d_h1, "H3 for H1 (alpha ~ arousal)")
h3_h2 <- h3_test(d_h2, "H3 for H2 (FAA ~ valence)")

step20 <- bind_rows(h3_h1$table, h3_h2$table)

step20

write_csv(step20, file.path(table_dir, "step20_H3_random_slopes.csv"))


# ------------------------------------------------------------
# 20B. FOREST PLOT: SEPARATE vs SHRUNK PERSONAL SLOPES
# ------------------------------------------------------------
# Separate = one regression per person (only ~20 trials each;
#            noisy).
# Shrunk   = mixed-model estimates; noisy people are pulled
#            toward the group average ("partial pooling").

forest_data <- function(d, m1, label) {

  separate <- d |>
    group_by(participant_id) |>
    group_modify(~ {
      fit <- lm(y ~ x_within, data = .x)
      ci  <- confint(fit)["x_within", ]
      tibble(estimate = coef(fit)["x_within"], ci_low = ci[1], ci_high = ci[2])
    }) |>
    ungroup() |>
    mutate(type = "separate regression")

  shrunk <- tibble(
    participant_id = rownames(coef(m1)$participant_id),
    estimate = coef(m1)$participant_id[, "x_within"],
    ci_low = NA_real_, ci_high = NA_real_,
    type = "mixed model (shrunk)"
  )

  bind_rows(separate, shrunk) |> mutate(analysis = label)
}

forest <- bind_rows(
  forest_data(d_h1, h3_h1$m1, "H1: alpha ~ arousal"),
  forest_data(d_h2, h3_h2$m1, "H2: FAA ~ valence")
)

p20 <- ggplot(forest, aes(estimate, participant_id, colour = type)) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y",
                position = position_dodge(width = 0.5), na.rm = TRUE) +
  geom_point(position = position_dodge(width = 0.5)) +
  facet_wrap(~ analysis, scales = "free_x") +
  labs(x = "Personal slope", y = NULL, colour = NULL,
       title = "Individual slopes: separate estimates vs shrunk estimates") +
  theme_minimal() +
  theme(legend.position = "bottom")

p20

ggsave(file.path(fig_dir, "p4_step20_forest.png"), p20, width = 10, height = 6)



# ============================================================
# 21. EXPLORATORY GRID  (*** EXPLORATORY - NOT CONFIRMATORY ***)
# ============================================================
#
# 5 bands x 7 ROIs x 3 predictors = 105 tests.
# With 105 tests, ~5 would be "significant" at p < .05 by
# chance alone. Benjamini-Hochberg FDR controls the expected
# proportion of false discoveries among the "hits".
# ============================================================

grid <- expand_grid(
  roi       = names(ROIS),
  band      = EEG_BANDS$band,
  predictor = c("Valence", "Arousal", "Likeability")
)

exploratory <- pmap_dfr(grid, function(roi, band, predictor) {

  outcome <- paste0(roi, "_", band)

  d <- prepare(trials, outcome, predictor)

  m <- suppressMessages(lmerTest::lmer(
    y ~ x_within + (1 | participant_id) + (1 | song_id), data = d, REML = TRUE))

  co <- summary(m)$coefficients

  tibble(
    roi, band, predictor,
    n_trials = nrow(d),
    estimate = co["x_within", "Estimate"],
    se       = co["x_within", "Std. Error"],
    t        = co["x_within", "t value"],
    p        = co["x_within", "Pr(>|t|)"],
    singular = lme4::isSingular(m)
  )
}) |>
  mutate(
    q_fdr        = p.adjust(p, method = "BH"),
    fdr_hit      = q_fdr < 0.05,
    muscle_flag  = band == "gamma"
  )

exploratory |> arrange(p) |> head(15)

sum(exploratory$fdr_hit)

write_csv(exploratory, file.path(table_dir, "step21_exploratory_grid.csv"))


p21 <- exploratory |>
  mutate(band = factor(band, levels = EEG_BANDS$band),
         label = if_else(fdr_hit, "*", "")) |>
  ggplot(aes(band, roi, fill = t)) +
  geom_tile() +
  geom_text(aes(label = label), size = 6) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 0) +
  facet_wrap(~ predictor) +
  labs(x = NULL, y = NULL, fill = "t",
       title = "EXPLORATORY: within-person rating effects on band power",
       subtitle = "* = FDR q < .05; gamma is muscle-sensitive") +
  theme_minimal()

p21

ggsave(file.path(fig_dir, "p4_step21_exploratory_heatmap.png"), p21, width = 11, height = 5)



# ============================================================
# 22. DIAGNOSTICS AND SENSITIVITY ANALYSES
# ============================================================


# ------------------------------------------------------------
# 22A. RESIDUAL DIAGNOSTICS (H1, H2)
# ------------------------------------------------------------
# Good signs: residuals scattered evenly around 0 (left);
# points close to the line in the QQ plot (right).

diag_plot <- function(fit, label) {

  dd <- tibble(fitted = fitted(fit$model), resid = resid(fit$model))

  p_a <- ggplot(dd, aes(fitted, resid)) +
    geom_point(alpha = 0.4) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    labs(title = paste(label, "- residuals vs fitted")) +
    theme_minimal()

  p_b <- ggplot(dd, aes(sample = resid)) +
    stat_qq(alpha = 0.4) + stat_qq_line() +
    labs(title = paste(label, "- QQ plot")) +
    theme_minimal()

  patchwork::wrap_plots(p_a, p_b)
}

p22a <- patchwork::wrap_plots(diag_plot(fit_h1, "H1"), diag_plot(fit_h2, "H2"), ncol = 1)

p22a

ggsave(file.path(fig_dir, "p4_step22_diagnostics.png"), p22a, width = 10, height = 8)


# ------------------------------------------------------------
# 22B. LEAVE-ONE-SUBJECT-OUT (LOSO)
# ------------------------------------------------------------
# Does any single person drive the result?

loso <- function(d, fit, label) {

  map_dfr(unique(d$participant_id), function(pid) {

    m <- suppressMessages(lmerTest::lmer(fit$formula,
                                         data = filter(d, participant_id != pid),
                                         REML = TRUE))
    co <- summary(m)$coefficients

    tibble(analysis = label, left_out = pid,
           estimate = co["x_within", "Estimate"],
           se = co["x_within", "Std. Error"])
  })
}

loso_res <- bind_rows(loso(d_h1, fit_h1, "H1"), loso(d_h2, fit_h2, "H2"))

write_csv(loso_res, file.path(table_dir, "step22_loso.csv"))

p22b <- ggplot(loso_res, aes(estimate, left_out)) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(xmin = estimate - 1.96 * se, xmax = estimate + 1.96 * se),
                width = 0.2, orientation = "y") +
  geom_point() +
  facet_wrap(~ analysis, scales = "free_x") +
  labs(x = "Within-person slope with one participant left out", y = "Left out") +
  theme_minimal()

p22b

ggsave(file.path(fig_dir, "p4_step22_loso.png"), p22b, width = 9, height = 6)


# ------------------------------------------------------------
# 22C. PRESENTATION ORDER (if recoverable)
# ------------------------------------------------------------

scan_files <- list.files(dataset_path, pattern = "_scans\\.tsv$",
                         recursive = TRUE, full.names = TRUE)

scans <- map_dfr(scan_files, function(f) {
  read_tsv(f, show_col_types = FALSE, col_types = cols(.default = "c")) |>
    mutate(participant_id = parse_ids(f)$participant_id,
           song_id        = parse_ids(f)$song_id)
}) |>
  mutate(acq = lubridate::ymd_hms(acq_time, quiet = TRUE))

order_check <- scans |>
  group_by(participant_id) |>
  summarise(n = n(), n_distinct_times = n_distinct(acq),
            any_missing = any(is.na(acq)), .groups = "drop")

order_valid <- all(order_check$n == order_check$n_distinct_times) &&
               !any(order_check$any_missing)

order_check
order_valid

trial_order_tbl <- scans |>
  group_by(participant_id) |>
  mutate(trial_order = rank(acq, ties.method = "first")) |>
  ungroup() |>
  select(participant_id, song_id, trial_order)

trials <- trials |> left_join(trial_order_tbl, by = c("participant_id", "song_id"))


# ------------------------------------------------------------
# 22D. SENSITIVITY MODELS
# ------------------------------------------------------------
# For each, report the target within-person slope.
# We DO NOT pick the "best" one. All are reported.

add_within <- function(d, var) {
  d |>
    group_by(participant_id) |>
    mutate("{var}_w" := .data[[var]] - mean(.data[[var]])) |>
    ungroup()
}

sensitivity_one <- function(outcome, predictor, other, label, sign) {

  base <- trials |>
    add_within(other) |> add_within("Likeability") |> add_within("Familiarity")

  specs <- list(
    "primary"                   = list(outcome = outcome, extra = ""),
    "both ratings"              = list(outcome = outcome, extra = paste0(" + ", other, "_w")),
    "+ liking & familiarity"    = list(outcome = outcome, extra = " + Likeability_w + Familiarity_w"),
    "relative power"            = list(outcome = paste0(outcome, "_rel"), extra = ""),
    "75 uV amplitude threshold" = list(outcome = paste0(outcome, "_75"), extra = "")
  )

  if (order_valid) {
    specs[["+ presentation order"]] <- list(outcome = outcome, extra = " + trial_order")
  }

  imap_dfr(specs, function(s, name) {

    d <- prepare(base, s$outcome, predictor)

    fit <- fit_with_fallback(paste0("y ~ x_within + x_between", s$extra), "x_within", d)

    extract_effect(fit, "x_within", d, label, predicted_sign = sign) |>
      mutate(model = name, .before = 1)
  })
}

sensitivity <- bind_rows(
  sensitivity_one("post_alpha", "Arousal", "Valence", "H1", -1),
  sensitivity_one("faa",        "Valence", "Arousal", "H2", +1)
)

sensitivity |>
  select(model, hypothesis, estimate, ci_low, ci_high, p, random_structure)

write_csv(sensitivity, file.path(table_dir, "step22_sensitivity.csv"))


p22d <- ggplot(sensitivity, aes(estimate, model)) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y") +
  geom_point() +
  facet_wrap(~ hypothesis, scales = "free_x") +
  labs(x = "Within-person slope (95% CI)", y = NULL,
       title = "Sensitivity analyses: does the conclusion depend on choices?") +
  theme_minimal()

p22d

ggsave(file.path(fig_dir, "p4_step22_sensitivity.png"), p22d, width = 10, height = 5)


# Save the analysis dataset for the report
write_csv(trials, file.path(table_dir, "analysis_trials.csv"))



# ============================================================
#                 END OF PHASE 4
# ============================================================
#
# Tables and figures: results/tables/statistics/ and results/figures/statistics/
#
# BEFORE INTERPRETING, ask for every result:
#   - Was it confirmatory or exploratory?
#   - What does the CI rule out?
#   - Could song acoustics, drowsiness or artifacts explain it?
# ============================================================
