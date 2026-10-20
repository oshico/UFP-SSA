# Churn Prediction & Customer Lifetime Value Optimisation in E-Commerce

> **Course project** — Sistemas e Aplicações (SSA) · Mestrado em Engenharia Informática (MEINF) · Universidade Fernando Pessoa

[![Status: baseline validated](https://img.shields.io/badge/status-baseline%20validated-brightgreen)](https://github.com/oshico/UFP_SSA)
[![R](https://img.shields.io/badge/R-4.6.1-blue)](https://www.r-project.org/)
[![License: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey)](https://creativecommons.org/licenses/by/4.0/)

---

> ### Project status: pipeline validated
>
> The analysis pipeline has now been **executed end-to-end on the full dataset**
> and its outputs regenerated. The model below is a *baseline* fit used to prove
> the pipeline works; the findings are not yet written up.
>
> What exists today:
> - ✅ Repository structure and version control
> - ✅ Raw dataset acquisition (reproducible download)
> - ✅ Analysis pipeline (`R/01_ecommerce_churn_analysis.R`), running clean
> - ✅ Exploratory analysis and figures
> - 🚧 Baseline logistic regression; not yet tuned or compared
> - ⬜ Reproducible report (Quarto / R Markdown)

---

## 1. Business Problem

Customer Acquisition Cost (CAC) in e-commerce rises steadily, which makes
**retention** the more profitable strategy for protecting long-term margins.
Digital platforms, however, suffer from **silent churn**: customers simply
stop purchasing without ever filing a complaint or cancelling a subscription.

This project builds an analytical solution in R — following the **CRISP-DM**
methodology — to identify behavioural abandonment patterns and predict the
**probability of churn within 90 days**, supporting targeted retention
campaigns and Customer Lifetime Value (CLV) optimisation.

## 2. Research Questions

| ID | Research question | Planned technique |
|----|-------------------|-------------------|
| **P1** | How do billing volumes and order frequencies vary across quarters and geographic markets? | Temporal aggregation (`dplyr`), heatmaps (`ggplot2`) |
| **P2** | What is the statistical relationship between product return ratio and RFM customer segments? | Variable cross-tabulation, comparative boxplots |
| **P3** | Is there a statistically significant difference in average order value between recurring and occasional customers? | Hypothesis testing (`t.test` / ANOVA) |
| **P4** | Can a classifier be trained to predict 90-day churn with adequate sensitivity? | Logistic regression / decision trees, confusion matrix, ROC curves |

## 3. Data Architecture

The project uses a **hybrid data architecture** combining historical
transactional records with a REST API for currency normalisation.

| Layer | Source | Description |
|-------|--------|-------------|
| **Historical** | [UCI *Online Retail*](https://doi.org/10.24432/C5BW33) | 541,909 real transactional records, 2010-12-01 → 2011-12-09 |
| **Dynamic** | [Open Exchange Rates](https://www.exchangerate-api.com/) REST API | GBP → EUR conversion, consumed in R via `httr2` + `jsonlite` |

### Source Data Dictionary

**From the CSV** (UCI) — `InvoiceNo`, `StockCode`, `Description`, `Quantity`,
`InvoiceDate`, `UnitPrice`, `CustomerID`, `Country`

**From the REST API** — `ExchangeRate` (GBP → EUR conversion rate)

**Derived in R** — `LineTotal_GBP`, `LineTotal_EUR`, `Is_Return`,
`Recency_Days`, `Frequency_Orders`, `Monetary_Total`, `Return_Ratio`,
`Log_Monetary`

**Target variable** — `Churn_90d`: binary, `1` if `Recency_Days > 90` (Churn),
`0` otherwise (Active)

Dataset dimensions: **541,909 rows × 8 source columns**, aggregating to
**4,372 unique customers**.

## 4. Repository Structure

```
.
├── data/
│   ├── raw/
│   │   ├── data.csv               # 44 MB — gitignored (re-fetchable)
│   │   └── download_data.R        # Reproducible acquisition from UCI
│   └── processed/                 # RFM matrix + churn flag (gitignored)
├── docs/
│   ├── m1.pdf                     # Project proposal (M1)
│   ├── m2.pdf                     # Problem definition (M2)
│   └── figures/                   # Rendered ggplot2 figures
├── R/
│   └── 01_ecommerce_churn_analysis.R
├── .gitignore
└── README.md
```

## 5. Getting Started

### Prerequisites

- **R** ≥ 4.6.1 — [download](https://www.r-project.org/)
- **RStudio** — [download](https://posit.co/download/rstudio-desktop/)
- **Git** — [download](https://git-scm.com/downloads)

### 1. Clone the repository

```bash
git clone https://github.com/oshico/UFP_SSA.git
cd UFP_SSA
```

### 2. Install dependencies

```r
install.packages(c("tidyverse", "lubridate", "httr2", "jsonlite", "readxl"))
```

> `caret` was dropped: the pipeline only needed a confusion matrix, which
> `confusion_metrics()` now computes in base R.

### 3. Acquire the dataset

The raw dataset (~44 MB) is **not** committed to the repository. It is
downloaded from the UCI Machine Learning Repository:

```r
source("data/raw/download_data.R")
```

This writes `data/raw/data.csv` — the exact filename and column
format the analysis script expects. It fetches the UCI `.xlsx`, converts it to
CSV, and rewrites `InvoiceDate` as `YYYY-MM-DD HH:MM` so the date is
unambiguous.

Run this **from the repository root**, since all scripts use relative paths.
If `data/raw/data.csv` already exists, the script asks before overwriting it in
an interactive session. Otherwise it refuses. Pass `--force` to overwrite
non-interactively (`Rscript data/raw/download_data.R --force`).

### 4. Run the analysis

```r
source("R/01_ecommerce_churn_analysis.R")
```

Outputs:

- `data/processed/customer_rfm_churn_processed.csv` — customer-level RFM matrix
- `docs/figures/eda_boxplot_churn_monetary.png`
- `docs/figures/eda_scatter_frequency_recency.png`

### Verified baseline run

The pipeline has been run end-to-end from a fresh `download_data.R` download
(R 4.6.1). It reproduces the dimensions expected of this dataset:
541,909 raw rows → 406,789 after cleaning → 4,338 customers with a purchase,
reference date `2011-12-10` (the day after the last transaction). Class balance
is 2,880 Active / 1,458 Churn. Measuring recency from purchases only moved 25
customers from Active to Churn compared with the first run (2,905 / 1,433).

Baseline logistic regression on the 70/30 stratified split (1,303 test rows):

| Metric | Value |
|--------|-------|
| Accuracy | 0.716 |
| Sensitivity (recall) | 0.562 |
| Specificity | 0.794 |
| Precision | 0.580 |
| F1 | 0.571 |

All three predictors are significant. Order frequency carries the most signal
(`Log_Frequency` estimate −1.572, z = −12.0): customers who order more often
are less likely to churn. Spend is also protective (`Log_Monetary` −0.278,
z = −4.8). A higher return ratio raises churn risk (1.909, p = 0.006). The fit
no longer emits the `fitted probabilities numerically 0 or 1` warning. The
model still misses about 44% of churners at a 0.5 threshold, so the next
iteration should tune the cut-off or compare a tree ensemble. These numbers
also carry the feature-window caveat in open issue 3.

### Note on the REST API

The currency conversion step calls the
[Frankfurter API](https://www.frankfurter.app/) (ECB reference rates, no API
key needed) for the latest GBP → EUR rate. If the call fails (no network, rate
limit), the script falls back to a hardcoded rate of `1 GBP = 1.17 EUR` and
prints a warning. For deterministic results, call
`get_gbp_to_eur_rate(api_url = NULL)` to always use the fallback.

## 6. Reproducibility

This project is built around the course requirement that all analysis is
reproducible from a clean checkout:

- **Relative paths only** — no absolute local paths anywhere in the code
- **Version control** — Git history maintained throughout the project lifecycle
- **Deterministic splits** — `set.seed(123)` before the train/test partition
- **Scripted data acquisition** — the dataset is never hand-copied; it is
  downloaded by a committed script
- **Documentation** — findings recorded in a Quarto / R Markdown report

## 7. Defects Corrected

The first draft of the pipeline had never been executed. These defects were
found and fixed before the first end-to-end run:

| # | Location | Defect | Fix |
|---|----------|--------|-----|
| 1 | `01_ecommerce_churn_analysis.R` (data loading) | Looked for `Online Retail.csv` behind an untested three-branch fallback chain | Single explicit path, `data/raw/data.csv`, with an actionable error if absent |
| 2 | `01_ecommerce_churn_analysis.R` (`max_date`) | `max(df_clean, na.rm = TRUE)` was called on a **data frame**, so the reference date never computed | `max(df_clean$InvoiceDate, na.rm = TRUE)` |
| 3 | `01_ecommerce_churn_analysis.R` (date parsing) | `d/m/Y H:M` was tried **first**, but the UCI file stores `m/d/Y` — every date read as day-first was shifted by months, corrupting `Recency_Days` and therefore the churn label | Formats tried in order ISO → `m/d/Y` → `d/m/Y`; `download_data.R` now emits ISO |
| 4 | `01_ecommerce_churn_analysis.R` (confusion matrix) | `confusionMatrix()` was passed `test_set` (a data frame) instead of the factor `test_set$Churn_90d`, and pulled in the whole `caret` stack for one calculation | Reference factor corrected; replaced by a local `confusion_metrics()` in base R |
| 5 | `01_ecommerce_churn_analysis.R` (train/test split) | `createDataPartition(rfm_df, ...)` split without stratifying, so the class balance was not guaranteed in both subsets | `createDataPartition(rfm_df$Churn_90d, ...)` |
| 6 | `01_ecommerce_churn_analysis.R` (reading) | `CustomerID` was read as `col_double()`, treating an identifier as a measure | Read as `col_character()` |
| 7 | `download_data.R` (conversion) | Called `na_if()` from dplyr without loading it, so the script crashed before writing the CSV | Base R replacement |
| 8 | `download_data.R` (overwrite prompt) | Under `Rscript`, `readline()` returns `""` at once, so the script always cancelled. Under `source()`, `quit()` closed the whole R session | Prompt only when `interactive()`, a `--force` flag, and `stop()` instead of `quit()` |
| 9 | `download_data.R` (dates) | Excel date serials were converted by hand. Floating-point error plus truncation could shift times a minute early | readxl reads the column as `date` and converts it itself |
| 10 | `download_data.R` (prices / CSV) | `round(UnitPrice, 2)` turned sub-penny prices into 0, and `quote = FALSE` let a comma in `Description` split a row | No rounding; fields quoted |
| 11 | `01_ecommerce_churn_analysis.R` (recency) | `LastPurchaseDate` included return lines, so a lapsed customer with a recent return was labelled Active | Last date over purchases only |
| 12 | `01_ecommerce_churn_analysis.R` (FX) | `get_gbp_to_eur_rate()` was always called with `api_url = NULL`, so the REST API was never actually queried | Defaults to the Frankfurter API, with the fallback kept |
| 13 | `01_ecommerce_churn_analysis.R` (`glm`) | Raw `Frequency_Orders` saturated the logit (`fitted probabilities numerically 0 or 1`) | `log1p(Frequency_Orders)` |

### Open issues

| # | Location | Issue |
|---|----------|-------|
| 1 | Model specification | The target is defined purely as `Recency_Days > 90`, so recency is excluded from the predictors by necessity. The model is a genuine test of whether **frequency, value and return behaviour** carry churn signal — worth stating explicitly in the report so it does not read as an oversight. |
| 2 | `data/raw/data.csv` | Older copies made outside `download_data.R` (e.g. the Kaggle export) use `m/d/Y H:M` dates; files from the script use ISO. The reader accepts both, but regenerating with `download_data.R --force` is preferred. |
| 3 | Feature window | Frequency and Monetary are computed over the same period the label is read from. A churner has had less active time, so has fewer orders by construction, and the model partly learns that. The standard fix is a time split: compute features up to a cutoff date (e.g. 2011-09-10) and label churn from activity in the 90 days after it. |

## 8. Generative AI Usage Declaration

In line with the academic integrity policy of Universidade Fernando Pessoa and
the course regulations for **Sistemas e Aplicações**, the use of generative AI
assistants in this project is declared transparently:

- AI assistants were used **exclusively for support with R syntax, code
  debugging and repository documentation**.
- **No AI-generated content has been submitted as original work.** All
  analytical decisions, research questions, data interpretation and written
  conclusions are the author's own.
- The AI tools were **not** used to generate results, fabricate data, or
  automate the assessment deliverables.

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
| **Course (UC)** | Sistemas e Aplicações (SSA) |
| **Programme** | Mestrado em Engenharia Informática (MEINF) |
| **Institution** | Universidade Fernando Pessoa (UFP) |
| **Lecturer** | Prof. Doutor Luís Borges Gouveia |
| **Student** | Francisco Oliveira |
| **Repository** | [github.com/oshico/UFP_SSA](https://github.com/oshico/UFP_SSA) |
| **Assessment** | Continuous — project milestones (M1, M2, …) and public presentations |
