# Preregistration: Subjective emotion and EEG band power during music listening (MET, ds008701)

**Status:** DRAFT. Review every line, edit it, then commit with git *before* running `04_phase4_statistics/04_stats.R`.
**Author:** Aditya Koundinya
**Date committed:** (the git commit timestamp is authoritative)

**Analyses already run at the time of writing (disclosure):**
- Phase 1: ratings only (descriptives, variance decomposition, consensus/deviation).
- Phases 2–3: EEG preprocessing, feature extraction and EEG-only sanity checks.
- No analysis relating EEG to ratings has been run.

---

## 1. Research question
Within individuals, is self-reported emotional experience (valence, arousal) during 2-minute music excerpts associated with EEG band power, and does any association persist for the person-specific part of the experience, beyond what is shared across listeners for the same song?

## 2. Confirmatory hypotheses

| | Hypothesis | Predicted direction |
|---|---|---|
| H1 | Higher within-person arousal is associated with lower posterior alpha power | negative slope |
| H2 | Higher within-person valence is associated with greater relative left-frontal activity (higher FAA) | positive slope |
| H3 | The within-person slopes of H1 and H2 vary between participants | random-slope variance > 0 |

## 3. Data
- 20 participants × 20 songs. EEG: 399 recordings (sub-17/t17 missing).
- Ratings (SAM) are given once, after each 120 s excerpt.

## 4. Inherited preprocessing (not modifiable, documented)
- 0.5–70 Hz band-pass and a 50 Hz notch (visible in the spectra), applied upstream.
- Average reference: the 66 EEG channels sum to ≈ 0.
- Units are µV, although `channels.tsv` says V.
- No ICA weights are stored. Blink activity is not visible in Fp1/Fp2 (r with EOG ≈ 0), so ocular artifacts were probably removed upstream.
- "bad" annotations are provided as 1-s segments.

## 5. Our preprocessing (`00_setup/eeg_functions.R`)
- **Music window:** 5–125 s, assumed from the README, because no onset marker exists.
- **No re-filtering, no re-referencing, no ICA.**
- **Bad channels**, computed on clean music-window samples:
  - flat: SD < 0.5 µV
  - extreme: |robust z of log SD| > 3, using median/MAD across channels
  - Flagged channels are set to missing, not interpolated.
- **Epochs:** 2-s non-overlapping (60 per trial).
  - Drop any epoch that overlaps a "bad" sample.
  - Drop any epoch in which any non-flagged EEG channel exceeds ±100 µV.
- **Spectra:** Hann-tapered FFT for each epoch, averaged across kept epochs (Welch), with 0.5 Hz resolution.

## 6. Outcome measures
- **Band power:** area under the PSD in δ 1–4, θ 4–8, α 8–13, β 13–30, γ 30–45 Hz, using half-open intervals, then log10.
- **H1 outcome:** posterior alpha = mean log10 alpha over O1, O2, Oz, PO3, PO4, POz, Pz (available channels).
- **H2 outcome:** FAA = ln(α F4) − ln(α F3). If F3 or F4 is flagged, FAA for that trial is missing.

## 7. Exclusion rules (fixed now)
1. **sub-01/t27:** liking and familiarity coded 0 ("data missing"), so the whole trial is excluded.
2. **Too little clean data:** exclude trials with fewer than 30 clean epochs (60 s) under the 100 µV rule.
3. **Rating variance:** participants are excluded only if their rating SD for the relevant predictor is 0. No participant is excluded for a restricted rating range.
4. **No outlier removal** based on EEG–rating relationships.

## 8. Predictors
- **Within-person rating:** rating − participant mean (computed on analysed trials).
- **Between-person rating:** participant mean − grand mean.
- **Song consensus:** leave-one-out mean rating of the song by the other participants, grand-mean centred.
- **Personal deviation:** rating − consensus, then participant-mean centred.

## 9. Confirmatory models (lme4 / lmerTest, REML, Satterthwaite df)
- **H1:** `post_alpha ~ arousal_within + arousal_between + (1 + arousal_within | participant_id)`
- **H2:** `faa ~ valence_within + valence_between + (1 + valence_within | participant_id)`
- **Decision rule:** the hypothesis is supported if the within-person slope has the predicted sign and two-sided p < .025 (Bonferroni over H1 and H2).
- **Reporting:** estimate, 95% profile CI (Wald if profiling fails), and a standardized effect (slope × within-person SD of the rating ÷ within-person SD of the outcome).
- **Singular-fit fallback**, applied only when the *participant* random-effects structure is singular (a near-zero song variance is kept and noted), in this order:
  1. remove the random-effect correlation (`||`)
  2. remove the random slope

  The model actually used is reported.
- **Consensus vs. deviation (answers the second half of the RQ):**
  - `outcome ~ consensus_c + deviation_within + (1 + deviation_within | participant_id) + (1 | song_id)`
  - Run for H1 (arousal) and H2 (valence).
  - The deviation slope is the person-specific effect, tested at α = .025.
  - The consensus slope is descriptive only, because it is confounded with acoustics.
- **H3:**
  - Likelihood-ratio test of the random-slope model against the random-intercept model (REML, same fixed effects).
  - The p-value uses a 50:50 mixture of χ²(1) and χ²(2), because a variance can't go below 0.
  - α = .05 for each hypothesis.
  - Report the slope SD with its CI.

## 10. Exploratory analyses (labelled exploratory; BH-FDR q < .05 over the whole grid)
- **Grid:** 5 bands × 7 ROIs × 3 predictors (valence, arousal, liking; within-person centred).
- **ROIs:** posterior, frontal-midline, left-frontal, right-frontal, central, left-temporal, right-temporal.
- **Model:** `y ~ x_within + (1 | participant_id) + (1 | song_id)`
- Gamma results are flagged as muscle-sensitive.

## 11. Sensitivity analyses (reported in full, whatever they show)
1. Both valence and arousal in the same model.
2. Adding within-person liking and familiarity.
3. Adding presentation order, if acq_time gives a valid order.
4. Relative instead of absolute power.
5. A ±75 µV amplitude threshold.
6. Leave-one-subject-out estimates.
7. Residual diagnostics.

The primary conclusions are based on the confirmatory models only.

## 12. Interpreting null results
- A non-significant result is not evidence of no effect.
- We report the 95% CI and state which effect sizes it rules out.
