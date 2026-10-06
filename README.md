# Music, Emotion and the Brain: EEG Analysis of Subjective Experience

A preregistered within-person analysis of how self-reported emotional experience during music listening relates to scalp EEG band power, using the **MET Music-Induced EEG Dataset** (OpenNeuro ds008701).

**Status:** ✓ Complete — all phases run, results analysed, preregistration committed

---

## The Research Question

> **Within individuals, is self-reported emotional experience (valence and arousal) during 2-minute music excerpts associated with EEG band power, and does any association persist for the person-specific part of the experience, beyond what is shared across listeners for the same song?**

### Three Preregistered Hypotheses
- **H1:** Higher within-person arousal → lower posterior alpha (8–13 Hz) power
- **H2:** Higher within-person valence → greater frontal alpha asymmetry (relatively more left-frontal activity)
- **H3:** The slopes in H1 and H2 vary between participants

---

## Key Figures

### Phase 1: Song Ratings & Manipulation Check
![Song map: valence vs arousal](01_phase1_ratings/outputs/figures/p1_song_map.png)

Each dot = one song's average rating across 20 listeners. Arousal separates songs clearly; valence is compressed at the low end. Songs intended to be "negative" were mildly unpleasant at most.

**Variance in ratings:**
| Rating | Person's habit | The song | Personal reaction |
|--------|---|---|---|
| Valence | 4% | 49% | **47%** |
| Arousal | 4% | 67% | **29%** |

Songs drive 50–67% of ratings. Personal reactions are substantial, leaving room to detect person-specific EEG effects.

---

### Phase 2: Raw EEG & Preprocessing

![Raw EEG and bad segments](02_phase2_eeg_inspection/outputs/figures/p2_raw_clean.png)

**Top (A):** Clean EEG, ±20 µV. **Bottom (B):** Annotated bad seconds (red), reaching ~9,000 µV—excluded entirely.

![Blink check](02_phase2_eeg_inspection/outputs/figures/p2_blink_check.png)

Correlation between blinks (EOG) and Fp1 is weak (r ≈ −0.09), suggesting blinks were already removed upstream.

---

### Phase 3: Power Spectrum & Topography

![Power spectrum](02_phase2_eeg_inspection/outputs/figures/p2_first_psd.png)

Welch spectrum: 1/f shape typical. Alpha peaks at ~10 Hz over the back (O1, blue) and is weaker at the front (Fz, orange). Dip at 50 Hz reveals an undocumented notch filter.

![Alpha topography](03_phase3_features/outputs/figures/p3_alpha_topography.png)

Alpha (8–13 Hz) is strongest posteriorly, as expected. Validates the pipeline.

![Band power by region](03_phase3_features/outputs/figures/p3_band_by_roi.png)

Power in each band (δ, θ, α, β, γ) across seven regions. Posterior regions have the most alpha.

**Quality control:**
| Stage | Count |
|-------|-------|
| Participant–song pairs | 400 |
| EEG files present | 399 |
| Clean, analysable | **395** |

---

### Phase 4: Statistical Analysis

#### Pseudoreplication problem: why 400 trials ≠ 400 people
![Pooling demo](04_phase4_statistics/outputs/figures/p4_step17_pooling.png)

Pooling all 399 trials inflates the test statistic (red bar, wrong). Proper within-person analysis across 20 people (blue bar, correct) is much more conservative.

#### Individual differences in slopes (H3)
![Forest plot](04_phase4_statistics/outputs/figures/p4_step20_forest.png)

Each person's slope with 95% CI (left) and group mean (right, shrunken). Slopes vary, but with ~20 trials per person, estimates are noisy.

#### Exploratory analysis (35 tests, FDR-corrected)
![Exploratory heatmap](04_phase4_statistics/outputs/figures/p4_step21_exploratory_heatmap.png)

Effect sizes across all band–region pairs. Any bright spots are ideas for future work, not findings.

#### Sensitivity: robustness across preprocessing choices
![Sensitivity analysis](04_phase4_statistics/outputs/figures/p4_step22_sensitivity.png)

Main effects (black line) remain consistent under six analytic choices. No single decision drove the results.

---

## Results Summary

| Hypothesis | Finding | Effect size | 95% CI | p |
|---|---|---|---|---|
| **H1:** Arousal → posterior α↓ | Not significant | −0.08 | [−0.24, 0.08] | 0.33 |
| **H2:** Valence → FAA↑ | Not significant | 0.06 | [−0.10, 0.22] | 0.45 |
| **H3:** Random slopes > 0 | χ²(1)=1.8, not sig. | — | — | 0.18 |

**Exploratory tests (105 tests):** None survive FDR correction.

**Consensus vs. deviation:** Effects remain null whether testing song-consensus or personal-deviation ratings.

**Interpretation:** No EEG–emotion association detected in this sample. Either the effect is small relative to within-person EEG noise, or it does not exist for these conditions.

---

## How to Run This

### Prerequisites
R ≥ 4.0 with: tidyverse, lme4, here, readr, ggplot2, patchwork, quarto

### Quick start
```r
# Open the project in RStudio
File > Open Project > met-eeg-project.Rproj

# Restart R
Session > Restart R

# Run everything (~15 min)
source("run_all.R")
```

### Or run phases individually
```r
# Phase 1: Ratings exploration
source(here::here("01_phase1_ratings", "01_ratings.R"))

# Phase 2: EEG inspection (one recording)
source(here::here("02_phase2_eeg_inspection", "02_eeg_inspect.R"))

# Phase 3: All 399 recordings (~10 min)
source(here::here("03_phase3_features", "03_features.R"))

# Phase 4: Statistics (requires preregistration committed)
source(here::here("04_phase4_statistics", "04_stats.R"))

# Phase 5: Final tables
source(here::here("05_phase5_report", "05_final_outputs.R"))

# Render report
quarto::quarto_render(here::here("05_phase5_report", "report.qmd"))
```

---

## Project Structure

```
met-eeg-project/
├── 00_setup/                      Dataset path & utility functions
│   ├── config.R                   Configuration
│   └── eeg_functions.R            EEG reading, preprocessing, feature extraction
├── 01_phase1_ratings/             Rating exploration & variance decomposition
│   ├── 01_ratings.R
│   └── outputs/ → figures/, tables/
├── 02_phase2_eeg_inspection/      Understand one EEG recording
│   ├── 02_eeg_inspect.R
│   ├── PREREGISTRATION.md         (Committed in git ✓)
│   └── outputs/ → figures/, tables/
├── 03_phase3_features/            Extract features from all 399 recordings
│   ├── 03_features.R
│   └── outputs/ → band power CSVs, QC table
├── 04_phase4_statistics/          Confirmatory & exploratory analyses
│   ├── 04_stats.R
│   └── outputs/ → results tables & figures
├── 05_phase5_report/              Final results & interpretation
│   ├── 05_final_outputs.R
│   ├── report.qmd                 Quarto template
│   └── outputs/ → final_results_table.csv, interpretation_worksheet.csv
├── run_all.R                      Rebuild everything
├── README.md                      This file
├── MET_project_overview.pdf       7-page plain-language overview
└── met-eeg-project.Rproj
```

---

## Key Methods

### Within-person analysis (avoiding pseudoreplication)
- Rating = song-consensus + personal-deviation
- Tests personal-deviation against EEG to isolate subjective experience from stimulus acoustics
- Mixed-effects models with random intercepts per person and per song

### Preregistration
All hypotheses and analysis choices are in `02_phase2_eeg_inspection/PREREGISTRATION.md`, committed to git before results were seen.

### Multiple comparisons
- Confirmatory (H1, H2): Bonferroni α = .025
- Exploratory (105 tests): Benjamini–Hochberg FDR α = .05

---

## Limitations

1. Small sample (N=20) with noisy individual estimates
2. Assumed music onset (5 s + 120 s; no onset marker in data)
3. Post-hoc single ratings per excerpt (moment-to-moment emotion invisible)
4. Song set skewed toward mild valence
5. Inherited upstream preprocessing (filtering, notch, possible ICA)
6. Scalp-level EEG is spatially blurry
7. Correlation ≠ causation

---

## Reproducibility

Rebuild from scratch:
```r
Session > Restart R
source("run_all.R")
```

The preregistration is committed. All code and data are versioned. Results are final.

---

## References

- **Data:** Koelsch, S., et al. (2019). OpenNeuro ds008701. https://openneuro.org/datasets/ds008701
- **Mixed-effects models:** Bates et al. (2015). *Journal of Statistical Software*, 67(1).
- **Frontal alpha asymmetry:** Coan & Allen (2004). *Biological Psychology*, 67(1-2).
- **Pseudoreplication:** Barr et al. (2013). *Journal of Memory and Language*, 68(3).

---

**Author:** Aditya Koundinya  
**Contact:** aditya003koundinya@gmail.com  
**License:** Creative Commons Attribution 4.0 International  
**Last updated:** October 2026
