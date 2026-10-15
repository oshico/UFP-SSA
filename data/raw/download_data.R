# Reproducible acquisition of the raw dataset (SSA - MEINF / UFP).
#
# Not part of the analysis pipeline. This utility downloads the UCI "Online
# Retail" dataset and converts it into the CSV that R/01_...R expects.
#
# Why a script rather than the file itself: the raw export is ~44 MB, so
# committing it bloats the repository without adding information. Versioning
# the acquisition METHOD is the actual reproducibility requirement.
#
# Usage (from the project root):
#   Rscript data/raw/download_data.R
#
# Requires: readxl

suppressPackageStartupMessages({
  library(readxl)
})

# 1. Configuration -------------------------------------------------------------

UCI_ZIP_URL <- "https://archive.ics.uci.edu/static/public/352/online+retail.zip"
UCI_DOI     <- "10.24432/C5BW33"

# Filename expected by R/01_ecommerce_churn_analysis.R.
TARGET_CSV <- file.path("data", "raw", "data.csv")

EXPECTED_ROWS <- 541909
EXPECTED_COLS <- c(
  "InvoiceNo", "StockCode", "Description", "Quantity",
  "InvoiceDate", "UnitPrice", "CustomerID", "Country"
)

# 2. Pre-conditions -----------------------------------------------------------

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("Package 'readxl' is missing. Install it with: install.packages('readxl')")
}

# Both scripts use relative paths, so the working directory must be the root.
if (!dir.exists("data") || !dir.exists("R")) {
  stop(
    "Run this from the project root.\n",
    "Expected 'data/' and 'R/' in the current directory, found: ", normalizePath(".")
  )
}

if (file.exists(TARGET_CSV)) {
  cat("WARNING:", TARGET_CSV, "already exists and will be overwritten.\n")
  answer <- readline("Continue? (y/N): ")
  if (!nzchar(answer) || !grepl("^[sSyY]$", answer)) {
    cat("Cancelled.\n")
    quit(save = "no", status = 0)
  }
}

# 3. Download ------------------------------------------------------------------

cat("=== 1/4. Downloading the dataset from the UCI Machine Learning Repository ===\n")
cat("URL :", UCI_ZIP_URL, "\n")
cat("DOI :", UCI_DOI, "\n\n")

# Scratch files go to the system temp directory, never into the repository.
zip_path <- file.path(tempdir(), "online_retail.zip")

download.file(
  url  = UCI_ZIP_URL,
  dest = zip_path,
  mode = "wb", # binary: mandatory on Windows
  quiet = FALSE
)

if (!file.exists(zip_path) || file.size(zip_path) < 1e6) {
  stop("Download failed: the .zip is missing or implausibly small.")
}

cat("\nDownloaded:", round(file.size(zip_path) / 1024^2, 1), "MB\n")

# 4. Extract -------------------------------------------------------------------

cat("\n=== 2/4. Extracting the workbook ===\n")

unzip_dir <- file.path(tempdir(), "online_retail_xlsx")
dir.create(unzip_dir, showWarnings = FALSE, recursive = TRUE)
unzip(zip_path, exdir = unzip_dir)

# Tolerate variations in the filename UCI ships.
xlsx_candidates <- list.files(
  unzip_dir,
  pattern = "\\.xlsx$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(xlsx_candidates) == 0) {
  stop("No .xlsx file found inside the downloaded .zip.")
}

xlsx_path <- xlsx_candidates[1]
cat("Found:", basename(xlsx_path), "\n")

# 5. Convert to CSV ------------------------------------------------------------

cat("\n=== 3/4. Converting the workbook to CSV ===\n")

# Everything is read as text on purpose. The UCI workbook stores cells in
# native Excel formats, which a naive xlsx -> CSV export writes out raw:
#
#   InvoiceDate -> 40513.351388888892   (Excel date serial)
#   UnitPrice   -> 2.5499999999999998   (binary floating-point noise)
#
# The date would then be unparseable downstream, so each column is converted
# explicitly instead. 25569 is the number of days from 1899-12-30 to the epoch.
df <- readxl::read_excel(
  xlsx_path,
  sheet = 1,
  col_types = "text", # read as text; format explicitly below
  .name_repair = "minimal"
)

cat("Rows read (excluding header):", format(nrow(df), big.mark = ","), "\n")

if (ncol(df) != length(EXPECTED_COLS)) {
  stop("Expected ", length(EXPECTED_COLS), " columns, found ", ncol(df), ".")
}
names(df) <- EXPECTED_COLS

# ISO output date, so the analysis never has to guess between day and month order.
df$InvoiceDate <- format(
  as.POSIXct(
    (suppressWarnings(as.numeric(df$InvoiceDate)) - 25569) * 86400,
    origin = "1970-01-01",
    tz = "UTC"
  ),
  "%Y-%m-%d %H:%M"
)

df$Quantity  <- as.integer(suppressWarnings(as.numeric(df$Quantity)))
df$UnitPrice <- round(suppressWarnings(as.numeric(df$UnitPrice)), 2)

# Blank CustomerID cells become NA and are dropped during data wrangling.
df$CustomerID <- na_if(trimws(df$CustomerID), "")

df$Description[is.na(df$Description) | df$Description == ""] <- "NA"

# 6. Write ---------------------------------------------------------------------

dir.create(dirname(TARGET_CSV), showWarnings = FALSE, recursive = TRUE)

# quote = FALSE keeps the file plain; na = "" writes missing values as empty fields.
utils::write.csv(
  df,
  file = TARGET_CSV,
  row.names = FALSE,
  quote = FALSE,
  na = ""
)

cat("CSV written to:", TARGET_CSV, "\n")

# 7. Validate ------------------------------------------------------------------

cat("\n=== 4/4. Validating the dataset ===\n")

cat("Rows      :", format(nrow(df), big.mark = ","), "\n")
cat("Columns   :", ncol(df), "\n")

if (nrow(df) != EXPECTED_ROWS) {
  warning(sprintf(
    "Expected %d rows but got %d. Check the integrity of the source.",
    EXPECTED_ROWS, nrow(df)
  ))
} else {
  cat("OK  row count matches the expected", format(EXPECTED_ROWS, big.mark = ","), ".\n")
}

cat("\nFirst 3 rows:\n")
print(utils::head(df, 3))

n_customers <- length(unique(na.omit(df$CustomerID)))
cat("\nUnique customers (CustomerID):", format(n_customers, big.mark = ","), "\n")

cat("\nDataset ready:", TARGET_CSV, "\n")
cat("Size        :", round(file.size(TARGET_CSV) / 1024^2, 1), "MB\n")
cat("\nNext step: source(\"R/01_ecommerce_churn_analysis.R\") from the project root.\n")

# Clean up the scratch files.
unlink(c(zip_path, unzip_dir), recursive = TRUE, force = TRUE)