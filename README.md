<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/01_masthead_dark.svg">
  <img src="docs/readme/01_masthead_light.svg" width="100%" alt="The Song or the Self? A preregistered search for personal musical emotion in scalp EEG. Verdict: 0 of 3 hypotheses supported. Twenty people heard the same twenty songs; when a song moved one listener more than usual, or more than everyone else, their alpha rhythm showed no detectable change.">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/02_setup_dark.svg">
  <img src="docs/readme/02_setup_light.svg" width="100%" alt="The setup: 20 listeners, 20 songs of 2 minutes, 66 EEG channels, 395 trials after quality control. The key move: every rating is split into a song consensus (what the other 19 listeners gave the same song) and a personal deviation (how far this listener landed from them).">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/03_bets_dark.svg">
  <img src="docs/readme/03_bets_light.svg" width="100%" alt="Three preregistered bets. H1, more aroused than usual leads to lower posterior alpha: not supported, slope 0.05, p = .355, opposite to the prediction. H2, more pleasant than usual leads to more left frontal activity: not supported, slope 0.01, p = .903. H3, people differ in these links: not supported, between person SD about 0.000 and 0.006. Every confidence interval crosses zero.">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/04_variance_dark.svg">
  <img src="docs/readme/04_variance_light.svg" width="100%" alt="Ratings are mostly the song (49% of valence, 67% of arousal) with a large personal part (47% and 29%). Posterior alpha is 94% differences between people, leaving a 6% within person slice. Of 105 exploratory tests, 3 had uncorrected p below .05, about 5 were expected by chance, and none survived correction (best q = 0.996).">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/05_robustness_dark.svg">
  <img src="docs/readme/05_robustness_light.svg" width="100%" alt="The intervals are narrow: a one SD rise in felt arousal is unlikely to lower posterior alpha by more than about 0.05 SD. Pooling 395 trials as if independent gives falsely tight intervals. The null held under four alternative analyses and when each listener was left out in turn.">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/06_why_dark.svg">
  <img src="docs/readme/06_why_light.svg" width="100%" alt="Why the textbook effects may have vanished: the comparison changed, the timescale is coarse, and the signal is small next to the noise. What this does not show: that EEG is blind to musical emotion.">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/readme/07_next_dark.svg">
  <img src="docs/readme/07_next_light.svg" width="100%" alt="The next experiment: rate while listening, zoom in on emotional peaks, more songs per person, and truly unpleasant music.">
</picture>

## Read the full story

* **The paper:** [The Song or the Self?](paper/paper.pdf) (PDF, about 10 pages plus references). LaTeX source and the figure script are in `paper/`.
* **The one sheet as a web page:** [`paper/one_sheeter.html`](paper/one_sheeter.html). Download it and open it in a browser for the full interactive version.
* **The preregistration:** [`preregistration/PREREGISTRATION.md`](preregistration/PREREGISTRATION.md), committed on 6 October 2026 at 15:27 IST (commit 3f16cb2), before any EEG to rating analysis ran.
* **All figures:** [`results/figures/`](results/figures), grouped by the step that produced them.

## Run it yourself

You need R 4.0 or newer with tidyverse, lme4, lmerTest, here, readr, ggplot2, patchwork and quarto.

**1. Get the data.** The raw EEG (about 14 GB) is public on OpenNeuro, so it is downloaded rather than stored in git:

```bash
bash analysis/setup/download_data.sh
```

This puts OpenNeuro ds008701 version 1.0.4 (the exact version analysed) in `data/ds008701`. If you already have it elsewhere, point the `MET_DATA` environment variable at that folder.

**2. Run everything** (about 15 minutes). Open `met_eeg_project.Rproj` in RStudio, restart R, then:

```r
source("run_all.R")
```

Or run the numbered scripts one at a time. Each one reads the tables written by the scripts before it.

```r
source(here::here("analysis", "01_ratings.R"))             # song ratings, song and self split
source(here::here("analysis", "02_eeg_inspection.R"))      # one recording in detail
source(here::here("analysis", "03_feature_extraction.R"))  # band power for all 399 recordings
source(here::here("analysis", "04_statistics.R"))          # hypothesis tests
source(here::here("analysis", "05_final_tables.R"))        # final tables and summary figure

quarto::quarto_render(here::here("report", "report.qmd"))  # the written report
```

`04_statistics.R` refuses to run unless the preregistration is committed in git. All outputs go to `results/`.

## What is in here

```
met_eeg_project/
├── README.md                  This page
├── run_all.R                  Runs every script in order, then renders the report
├── met_eeg_project.Rproj      Open this in RStudio
├── preregistration/           Hypotheses and analysis plan, committed before testing
├── analysis/                  Numbered analysis scripts, plus setup/ (config, EEG functions, data download)
├── results/                   figures/ and tables/, one subfolder per step
├── paper/                     paper.pdf, its LaTeX source, figures, and the one sheet web page
├── report/                    Quarto report built from results/
├── docs/
│   ├── readme/                The animated panels on this page and the script that builds them
│   ├── project_overview.pdf   Plain language overview, written before the results were seen
│   ├── learning_guide/        Beginner guide to the methods
│   └── corrections_checklist.md
└── data/                      Raw dataset, filled by download_data.sh (ignored by git)
```

## Rebuilding the panels on this page

GitHub does not run CSS or scripts in a README, so each panel above is the one sheet web page frozen into an SVG image with its fonts embedded and its motion written as CSS animations. After editing `paper/one_sheeter.html`, rebuild them with:

```bash
node docs/readme/build_readme_svgs.js
```

This needs Node with Playwright (Chromium), curl, and network access to Google Fonts.

## Deviations from the preregistration

1. All H1 and H2 models used the preregistered fallback to random intercepts only, because the random slope structure was singular.
2. The presentation order check could not be run, because the recording timestamps repeat and play order is not recoverable.
3. Confidence intervals for the H3 slope SDs could not be computed, because the random slope models were singular.

## Data and credits

* **Data:** Cheang, W. L. (2026). *MET: Music Induced EEG Dataset* (version 1.0.4). OpenNeuro. doi:10.18112/openneuro.ds008701.v1.0.4
* **Author:** Aditya Koundinya, independent researcher, Bengaluru (aditya003koundinya@gmail.com)
* **License:** Creative Commons Attribution 4.0 International
