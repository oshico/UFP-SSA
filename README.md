# Churn Prediction & Customer Lifetime Value Optimisation in E-Commerce

> **Course project** — Sistemas e Aplicações (SSA) · Mestrado em Engenharia Informática (MEINF) · Universidade Fernando Pessoa

[![Status: scaffolding](https://img.shields.io/badge/status-scaffolding%20%28WIP%29-orange)](https://github.com/oshico/UFP_SSA)
[![R](https://img.shields.io/badge/R-4.6.1-blue)](https://www.r-project.org/)
[![License: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey)](https://creativecommons.org/licenses/by/4.0/)

---

> ### ⚠️ Project status: early scaffolding
>
> This repository is currently in the **exploratory scaffolding** stage. The
> analysis pipeline exists as a draft and has **not yet been executed
> end-to-end or validated**. Model results are not final and no findings
> should be drawn from this repository yet.
>
> What exists today:
> - ✅ Repository structure and version control
> - ✅ Raw dataset acquisition (reproducible download)
> - 🚧 Draft analysis pipeline (`R/01_ecommerce_churn_analysis.R`)
> - ⬜ Exploratory analysis and validation
> - ⬜ Predictive modelling and evaluation
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

**Derived in R** — `Amount_EUR`, `Recency_Days`, `Frequency_Orders`,
`Monetary_Total`, `Return_Ratio`

**Target variable** — `Churn_90d`: binary, `1` if `Recency_Days > 90` (Churn),
`0` otherwise (Active)

Dataset dimensions: **541,909 rows × 8 source columns**, aggregating to
**4,372 unique customers**.

## 4. Repository Structure

```
.
├── data/
│   ├── raw/
│   │   ├── Online Retail.csv      # 44 MB — gitignored (re-fetchable)
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
install.packages(c("tidyverse", "lubridate", "httr2", "jsonlite", "caret", "readxl"))
```

> `caret` is a large package and may take a while to compile. It is only needed
> for the confusion matrix and ML metrics in the modelling stage.

### 3. Acquire the dataset

The raw dataset (~44 MB) is **not** committed to the repository. It is
downloaded from the UCI Machine Learning Repository:

```r
source("data/raw/download_data.R")
```

This writes `data/raw/Online Retail.csv` — the exact filename and column
format the analysis script expects. It fetches the UCI `.xlsx`, converts it to
CSV, and reformats `InvoiceDate` into the `d/m/Y H:M` string format that
`lubridate` parses.

Run this **from the repository root**, since all scripts use relative paths.

### 4. Run the analysis

```r
source("R/01_ecommerce_churn_analysis.R")
```

Outputs:

- `data/processed/customer_rfm_churn_processed.csv` — customer-level RFM matrix
- `docs/figures/eda_boxplot_churn_monetary.png`
- `docs/figures/eda_scatter_frequency_recency.png`

### Note on the REST API

The currency conversion step calls the Open Exchange Rates API. If the call
fails (no network, rate limit), the script falls back to a hardcoded rate of
`1 GBP = 1.17 EUR` and prints a warning. For deterministic results, pass an
explicit API URL as the `api_url` argument of `get_gbp_to_eur_rate()`.

## 6. Reproducibility

This project is built around the course requirement that all analysis is
reproducible from a clean checkout:

- **Relative paths only** — no absolute local paths anywhere in the code
- **Version control** — Git history maintained throughout the project lifecycle
- **Deterministic splits** — `set.seed(123)` before the train/test partition
- **Scripted data acquisition** — the dataset is never hand-copied; it is
  downloaded by a committed script
- **Documentation** — findings recorded in a Quarto / R Markdown report

## 7. Known Issues

These are known defects in the current draft pipeline, recorded here so they
are not mistaken for finished work:

| # | Location | Issue |
|---|----------|-------|
| 1 | `R/01_ecommerce_churn_analysis.R:31-37` | The script looks for `Online Retail.csv`. The dataset has been renamed to match, but the filename fallback chain is untested. |
| 2 | `R/01_ecommerce_churn_analysis.R:136` | `max(df_clean, na.rm = TRUE)` is called on a **data frame**. This must be `max(df_clean$InvoiceDate, na.rm = TRUE)` or the reference date will not compute. |
| 3 | `R/01_ecommerce_churn_analysis.R:258` | `confusionMatrix()` is passed `test_set` (a data frame) as the reference instead of the factor `test_set$Churn_90d`. |
| 4 | Pipeline | **Never executed end-to-end.** Packages are not yet installed in the development environment; behaviour is unverified. |

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
