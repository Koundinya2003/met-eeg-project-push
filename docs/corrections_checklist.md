# Correction prompt for the MET EEG project

Copy everything below the line into Claude (or any assistant) together with access to the project folder.

---

You are reviewing my R project "met eeg project", a preregistered within person analysis of the MET Music Induced EEG Dataset (OpenNeuro ds008701, version 1.0.4). Treat the CSV files in each phase's outputs folder as the single source of truth and make every document agree with them. Do not edit the original dataset files and do not edit PREREGISTRATION.md, because it is a committed preregistration (git commit 3f16cb2) and must stay as committed.

Check and correct each of the following:

1. README results table. It reports H1 as standardized effect minus 0.08, CI [minus 0.24, 0.08], p 0.33; H2 as 0.06, CI [minus 0.10, 0.22], p 0.45; H3 as chi square(1) = 1.8, p 0.18. The real values in step18 and step20 are: H1 0.05 [minus 0.05, 0.15], p .355 (sign opposite to the prediction); H2 0.01 [minus 0.10, 0.11], p .903; H3 mixture p .949 (H1, slope SD 0.000) and .424 (H2, slope SD 0.006), both singular. Add the person specific deviation rows from step19 (0.05, p .342 and 0.04, p .386).

2. README never says that the random slope models were singular. Every H1 and H2 model used the preregistered fallback to random intercepts only, and the README must say so. List this, the missing presentation order analysis, and the missing slope SD confidence intervals as deviations from the preregistration.

3. README pooling demo text says pooling "inflates the test statistic". step17 shows the naive pooled r is actually smaller (H1 r = 0.009 vs two stage r = 0.08). Rewrite it to say naive pooling gives a falsely narrow confidence interval.

4. README exploratory heading says 35 tests; the grid has 105 tests (5 bands × 7 regions × 3 ratings). State that 3 had uncorrected p < .05 and the smallest q is 0.996.

5. README sensitivity text says "six analytic choices". There are four alternative specifications plus leave one subject out; the presentation order check could not run because acq_time values repeat.

6. README forest plot text says "slopes vary"; the random slope SD is near zero, so the spread is noise.

7. README QC table: add the 396 recordings that passed EEG QC, the four exclusions (subject 12 t05 truncated in the published dataset, subject 14 t06 26 clean epochs, subject 18 t17 0 clean epochs, subject 17 t17 missing) and the extra rating exclusion (subject 01 t27) that gives 395 analysed trials.

8. qc_summary.csv says excluded = 0; qc_table.csv shows 4 excluded. Fix the file and make 05_final_tables.R also write analysed_trials.

9. README dataset citation wrongly says Koelsch et al. (2019). The correct citation is Cheang, W. L. (2026), MET: Music Induced EEG Dataset, version 1.0.4, OpenNeuro, doi:10.18112/openneuro.ds008701.v1.0.4. Complete the Coan and Allen (2004) reference with pages 7 to 49.

10. README should note that PREREGISTRATION.md still shows "Status: DRAFT" but the committed version is authoritative.

11. README limitations: add the truncated and missing recordings, the dataset metadata errors (files are EEGLAB .set not BrainVision, channels.tsv says V but values are µV, flat channels labelled good, undocumented 50 Hz notch) and the unrecoverable presentation order.

12. Label project_overview.pdf as written before results were seen (it says results have not been seen).

13. interpretation_worksheet.csv is empty. Fill all four columns for all 12 findings, using confidence intervals to say which effect sizes are ruled out, never "no effect", and no reverse inference.

14. report.qmd has 12 unfilled writing blocks (Introduction, ratings methods, statistical methods, ratings results, EEG sanity checks, deviation vs consensus, H3, robustness, Discussion, Limitations, Conclusion, References). Fill each with prose that uses only numbers from the outputs, and give fully formatted APA references.

15. Add .RDataTmp (75 MB, untracked) to .gitignore.

After editing, list every change, and flag anything you could not verify. Then rerun run_all.R and render report.qmd to confirm everything still builds.
