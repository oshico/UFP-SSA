# Churn Prediction & Customer Lifetime Value Optimisation in E-Commerce

> **Course project** — Seminário de Sistemas e Aplicações (SSA) · Mestrado em Engenharia Informática (MEINF) · Universidade Fernando Pessoa

[![R](https://img.shields.io/badge/R-%E2%89%A5%204.4-blue)](https://www.r-project.org/)
[![Quarto](https://img.shields.io/badge/reports-Quarto-75AADB)](https://quarto.org/)
[![License: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey)](https://creativecommons.org/licenses/by/4.0/)

---

## 1. Business problem

Customer acquisition cost in e-commerce keeps rising, which makes **retention**
the more profitable way to protect margins. Online retailers, however, suffer
from **silent churn**: customers simply stop buying, without complaining or
cancelling anything.

This project builds an analytical solution in R, following CRISP-DM, that
explains what separates customers who leave from those who stay and predicts
the **probability that a customer makes no purchase in the next 90 days**.

## 2. Research questions

| ID | Question | Technique |
|----|----------|-----------|
| **P1** | How do revenue and order counts vary across quarters and geographic markets? | Temporal aggregation, heatmap, chi-square, Kruskal-Wallis |
| **P2** | How does the product return ratio relate to RFM customer segments? | RFM quintile segmentation, Kruskal-Wallis, chi-square, Spearman |
| **P3** | Do recurring and occasional customers differ in average order value? | Welch *t*-test on log(AOV), Wilcoxon |
| **P4** | Can 90-day churn be predicted with adequate sensitivity? | Time-split label, logistic regression vs. pruned decision tree, ROC/AUC, threshold chosen on training data, out-of-time validation |

## 3. Data

| Layer | Source | Description |
|-------|--------|-------------|
| **Historical** | [UCI *Online Retail*](https://doi.org/10.24432/C5BW33) | 541,909 invoice lines, 2010-12-01 → 2011-12-09 |
| **Dynamic** | [Frankfurter](https://www.frankfurter.app/) REST API (ECB reference rates) | Daily GBP → EUR rate, consumed with `httr2` |

Each sale is converted at its own day's rate. Historical rates never change,
so the API response is cached locally in `data/external/fx_gbp_eur_daily.csv`
(gitignored, like all data: a fresh clone fetches it again on the first run).
Later runs are deterministic and work offline. Without cache
and network, the pipeline falls back to a fixed rate and the reports state
which source was used.

The full data dictionary is in `reports/m2.qmd`.

## 4. Repository structure

```
.
├── R/
│   └── ecommerce_churn_analysis.R   # whole pipeline: cleaning → P1–P4 → models
├── data/
│   ├── raw/
│   │   ├── download_data.R          # reproducible acquisition from UCI
│   │   └── data.csv                 # ~44 MB, gitignored (re-fetchable)
│   ├── external/
│   │   └── fx_gbp_eur_daily.csv     # FX cache, created on first run (gitignored)
│   └── processed/                   # pipeline outputs (gitignored)
├── docs/figures/                    # ggplot2 figures written by the pipeline
├── reports/
│   ├── m1.qmd                       # M1 · project proposal
│   ├── m2.qmd                       # M2 · problem definition + data dictionary
│   ├── m3.qmd                       # M3 · wrangling + EDA + modelling strategy
│   ├── m4.qmd                       # M4 · final report
│   └── m4-slides.qmd                # M4 · presentation (reveal.js)
├── _quarto.yml                      # shared report configuration
├── UFP-SSA.Rproj
└── README.md
```

The reports read the pipeline with `knitr::read_chunk()`: the
`## ---- name ----` markers in the R script define chunks that the `.qmd`
files execute and display. **No number in any report is typed by hand**;
everything is computed at render time.

## 5. Getting started

### Prerequisites

- R ≥ 4.4, [RStudio](https://posit.co/download/rstudio-desktop/), [Quarto](https://quarto.org/docs/get-started/) and Git

### 1. Clone

```bash
git clone https://github.com/oshico/UFP-SSA.git
cd UFP-SSA
```

### 2. Install dependencies

```r
install.packages(c("tidyverse", "lubridate", "httr2", "readxl", "knitr", "rmarkdown"))
```

`rpart` ships with R.

### 3. Download the dataset

```bash
Rscript data/raw/download_data.R
```

This writes `data/raw/data.csv` with ISO dates. Run it from the repository
root. If the file exists, the script asks before overwriting it in an
interactive session and refuses otherwise; pass `--force` to overwrite.

### 4. Run the analysis and render the reports

```bash
Rscript R/ecommerce_churn_analysis.R   # pipeline only: figures + processed data
quarto render                           # M1–M4 and slides into _output/reports/
```

Rendered HTML files are self-contained (`embed-resources: true`) and can be
submitted or opened offline.

## 6. Reproducibility

- **Relative paths only**; reports run from the project root (`execute-dir: project`)
- **Scripted data acquisition**: the dataset is never hand-copied
- **Deterministic**: `set.seed(123)`, historical FX rates (fixed values, cached locally)
- **Single source of truth**: reports execute the same code as the script

## 7. Defects corrected

### First end-to-end run

| # | Location | Defect | Fix |
|---|----------|--------|-----|
| 1 | analysis script (data loading) | Looked for `Online Retail.csv` behind an untested three-branch fallback chain | Single explicit path, `data/raw/data.csv`, with an actionable error if absent |
| 2 | analysis script (`max_date`) | `max(df_clean, na.rm = TRUE)` was called on a **data frame**, so the reference date never computed | `max(df_clean$InvoiceDate, na.rm = TRUE)` |
| 3 | analysis script (date parsing) | `d/m/Y H:M` was tried **first**, but the UCI file stores `m/d/Y` — every date read as day-first was shifted by months, corrupting `Recency_Days` and therefore the churn label | Formats tried in order ISO → `m/d/Y` → `d/m/Y`; `download_data.R` now emits ISO |
| 4 | analysis script (confusion matrix) | `confusionMatrix()` was passed `test_set` (a data frame) instead of the factor `test_set$Churn_90d`, and pulled in the whole `caret` stack for one calculation | Reference factor corrected; replaced by a local `confusion_metrics()` in base R |
| 5 | analysis script (train/test split) | `createDataPartition(rfm_df, ...)` split without stratifying, so the class balance was not guaranteed in both subsets | `createDataPartition(rfm_df$Churn_90d, ...)` |
| 6 | analysis script (reading) | `CustomerID` was read as `col_double()`, treating an identifier as a measure | Read as `col_character()` |
| 7 | `download_data.R` (conversion) | Called `na_if()` from dplyr without loading it, so the script crashed before writing the CSV | Base R replacement |
| 8 | `download_data.R` (overwrite prompt) | Under `Rscript`, `readline()` returns `""` at once, so the script always cancelled. Under `source()`, `quit()` closed the whole R session | Prompt only when `interactive()`, a `--force` flag, and `stop()` instead of `quit()` |
| 9 | `download_data.R` (dates) | Excel date serials were converted by hand. Floating-point error plus truncation could shift times a minute early | readxl reads the column as `date` and converts it itself |
| 10 | `download_data.R` (prices / CSV) | `round(UnitPrice, 2)` turned sub-penny prices into 0, and `quote = FALSE` let a comma in `Description` split a row | No rounding; fields quoted |
| 11 | analysis script (recency) | `LastPurchaseDate` included return lines, so a lapsed customer with a recent return was labelled Active | Last date over purchases only |
| 12 | analysis script (FX) | `get_gbp_to_eur_rate()` was always called with `api_url = NULL`, so the REST API was never actually queried | Defaults to the Frankfurter API, with the fallback kept |
| 13 | analysis script (`glm`) | Raw `Frequency_Orders` saturated the logit (`fitted probabilities numerically 0 or 1`) | `log1p(Frequency_Orders)` |

### Before M4

| # | Location | Defect | Fix |
|---|----------|--------|-----|
| 14 | Cleaning | 5,268 exact duplicate lines were counted as separate sales | `distinct()` |
| 15 | Cleaning | Postage, fees, bank charges, manual adjustments and gift vouchers were counted as purchases | Explicit list of non-product `StockCode`s removed |
| 16 | Outliers | Orders cancelled in full (e.g. 80,995 and 74,215 units) still counted as spend | One-to-one matching of each purchase line with its cancellation |
| 17 | Churn label | Features and label used the same window (former open issue 3), and recency could not be a predictor | Time split: features before a cutoff, churn in the following 90 days |
| 18 | FX | One present-day rate was applied to 2010–11 sales, and results changed on every run | Daily historical ECB rates, joined by date and cached |
| 19 | Reports | The M3 PDF showed illustrative values not produced by code | M1–M4 rewritten in Quarto with all numbers computed at render time (errata in M3) |

### Open issues

| # | Issue |
|---|-------|
| 1 | Only one year of data, so the out-of-time check uses a single earlier cutoff. A rolling-window validation needs more history. |
| 2 | `CustomerID` is missing far more often in UK lines (~27%) than elsewhere (~3%). Removing them may over-represent registered, loyal customers. |
| 3 | Package versions are not pinned yet; run `renv::init()` and commit `renv.lock`. |

## 8. Generative AI usage declaration

In line with the academic integrity policy of Universidade Fernando Pessoa,
the use of generative AI assistants in this project is declared:

- AI assistants were used for R syntax, code
  debugging, code review.
- The author reviewed, ran and is responsible for all code, analytical
  decisions and conclusions.
- All results are produced by the code in this repository; no data or result
  was generated or edited by an AI tool outside it.

## 9. Data Attribution

This project uses the **Online Retail** dataset from the UCI Machine Learning
Repository:

> Chen, D. (2015). *Online Retail* [Dataset]. UCI Machine Learning Repository.
> https://doi.org/10.24432/C5BW33

Licensed under **CC BY 4.0**. The dataset is redistributed here only after
being downloaded by `data/raw/download_data.R`; no data is stored in version
control.

## 10. Course Information

| Field | Detail |
|-------|--------|
| **Course (UC)** | Seminário de Sistemas e Aplicações (SSA) |
| **Programme** | Mestrado em Engenharia Informática (MEINF) |
| **Institution** | Universidade Fernando Pessoa (UFP) |
| **Lecturer** | Prof. Doutor Luís Borges Gouveia |
| **Student** | Francisco Oliveira |
| **Repository** | [github.com/oshico/UFP-SSA](https://github.com/oshico/UFP-SSA) |
| **Assessment** | Continuous — milestones M1–M4 (`reports/`) and public presentations |
