# ==============================================================================
# UC:  Seminario de Sistemas e Aplicacoes (SSA - MEINF / UFP)
# Tarefa: Aquisição reprodutível do dataset bruto
# ------------------------------------------------------------------------------
# Este script NAO faz parte do pipeline de analise. É um utilitário de
# preparação que descarrega o dataset "Online Retail" da UCI Machine Learning
# Repository e converte-o para o formato CSV esperado pelo projeto.
#
# Porque existe?
#   O ficheiro bruto tem ~44 MB. Versionar ficheiros tão grandes incha o
#   repositorio sem acrescentar informação. Em vez disso, versionamos o
#   METODO de obtenção dos dados, que é o requisito real de reprodutibilidade.
#
# Como usar:
#   Rscript data/raw/download_data.R
#
# Dependências: readxl (conversão de .xlsx), httr2 ou utils::download.file
# ==============================================================================

suppressPackageStartupMessages({
  library(readxl)
})

# ------------------------------------------------------------------------------
# 1. CONSTANTES E CONFIGURACAO
# ------------------------------------------------------------------------------

UCI_ZIP_URL <- "https://archive.ics.uci.edu/static/public/352/online+retail.zip"
UCI_DOI     <- "10.24432/C5BW33"

# Nome EXATO esperado por R/01_ecommerce_churn_analysis.R (linha 31).
TARGET_CSV <- file.path("data", "raw", "Online Retail.csv")

# Nº de linhas de dados esperado (exclui o cabeçalho).
EXPECTED_ROWS <- 541909

EXPECTED_COLS <- c(
  "InvoiceNo", "StockCode", "Description", "Quantity",
  "InvoiceDate", "UnitPrice", "CustomerID", "Country"
)

# ------------------------------------------------------------------------------
# 2. VERIFICACOES DE PRE-CONDICAO
# ------------------------------------------------------------------------------

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("Pacote 'readxl' em falta. Instale com: install.packages('readxl')")
}

# Garante que estamos na raiz do projeto (mesma pasta que contem 'data/' e 'R/').
# Os scripts usam caminhos relativos; executar a partir da raiz é obrigatório.
if (!dir.exists("data") || !dir.exists("R")) {
  stop(
    "Execute a partir da raiz do projeto.\n",
    "O script espera encontrar as pastas 'data/' e 'R/' no diretorio atual.\n",
    "Diretorio atual: ", normalizePath(".")
  )
}

if (file.exists(TARGET_CSV)) {
  cat("AVISO: ja existe", TARGET_CSV, "\n")
  cat("O ficheiro sera sobreescrito. Apague-o manualmente se nao quiser\n",
      "continuar.\n\n", sep = "")
  answer <- readline("Continuar? (s/N): ")
  if (!nzchar(answer) || !grepl("^[sSyY]$", answer)) {
    cat("Operacao cancelada.\n")
    quit(save = "no", status = 0)
  }
}

# ------------------------------------------------------------------------------
# 3. DESCARGA DO FICHEIRO .zip DA UCI
# ------------------------------------------------------------------------------

cat("=== 1/4. A descarregar o dataset da UCI Machine Learning Repository ===\n")
cat("URL :", UCI_ZIP_URL, "\n")
cat("DOI :", UCI_DOI, "\n\n")

# Ficheiros temporarios vão para o diretorio temporario do sistema,
# nunca para a raiz do repositorio.
zip_path <- file.path(tempdir(), "online_retail.zip")

download.file(
  url  = UCI_ZIP_URL,
  dest = zip_path,
  mode = "wb",          # binário: obrigatório no Windows
  quiet = FALSE
)

if (!file.exists(zip_path) || file.size(zip_path) < 1e6) {
  stop("Falha na descarga: ficheiro .zip ausente ou demasiado pequeno.")
}

cat("\nDescarregado:", round(file.size(zip_path) / 1024^2, 1), "MB\n")

# ------------------------------------------------------------------------------
# 4. EXTRACAO DO .xlsx
# ------------------------------------------------------------------------------

cat("\n=== 2/4. A extrair 'Online Retail.xlsx' ===\n")

unzip_dir <- file.path(tempdir(), "online_retail_xlsx")
dir.create(unzip_dir, showWarnings = FALSE, recursive = TRUE)
unzip(zip_path, exdir = unzip_dir)

# Localiza o .xlsx de forma tolerante a variations de nome/caminho.
xlsx_candidates <- list.files(
  unzip_dir,
  pattern = "\\.xlsx$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(xlsx_candidates) == 0) {
  stop("Nenhum ficheiro .xlsx encontrado dentro do .zip descarregado.")
}

xlsx_path <- xlsx_candidates[1]
cat("Encontrado:", basename(xlsx_path), "\n")

# ------------------------------------------------------------------------------
# 5. LEITURA E CONVERSAO PARA CSV
# ------------------------------------------------------------------------------
#
# NOTA TECNICA IMPORTANTE (porquê e que lê col_types = "text"):
#
#   O ficheiro original da UCI e um Excel cujas celulas estao gravadas em
#   formato NUMERICO NATIVO do Excel, não como texto:
#
#       InvoiceDate -> 40513.351388888892   (serial date do Excel)
#       UnitPrice   -> 2.5499999999999998   (ponto flutuante binário)
#
#   Uma conversao ingenua xlsx -> CSV produciria esses valores crus, e a
#   analise em R falharia ao tentar interpretar a data.
#
#   Por isso lemos TUDO como texto e formatamos explicitamente:
#     - InvoiceDate: serial do Excel -> POSIXct -> "%d/%m/%Y %H:%M"
#       (25569 = dias entre 1899-12-30 e 1970-01-01)
#     - UnitPrice  : round(..., 2)
#
#   Isto reproduz exactamente o formato de data esperado por
#   lubridate::parse_date_time(orders = "d/m/Y H:M") em R/01_...R (linha 72).
# ------------------------------------------------------------------------------

cat("\n=== 3/4. A ler e converter o .xlsx para CSV ===\n")

df <- readxl::read_excel(
  xlsx_path,
  sheet       = 1,
  col_types   = "text",     # <- le como texto; formatamos manualmente a seguir
  .name_repair = "minimal"
)

cat("Linhas lidas (sem cabecalho):", nrow(df), "\n")

# Normaliza nomes das colunas para os nomes canonicos esperados.
names(df) <- trimws(names(df))
names(df) <- EXPECTED_COLS

# --- InvoiceDate: serial numerico do Excel -> data/hora legivel -------------
serial <- suppressWarnings(as.numeric(df$InvoiceDate))
df$InvoiceDate <- as.POSIXct(
  (serial - 25569) * 86400,
  origin = "1970-01-01",
  tz     = "UTC"
)
df$InvoiceDate <- format(df$InvoiceDate, "%d/%m/%Y %H:%M", tz = "UTC")

# --- Quantity: inteiro --------------------------------------------------------
df$Quantity <- as.integer(suppressWarnings(as.numeric(df$Quantity)))

# --- UnitPrice: numerico arredondado a 2 casas -------------------------------
df$UnitPrice <- round(as.numeric(suppressWarnings(as.numeric(df$UnitPrice))), 2)

# --- CustomerID: mantem como texto; celulas vazias -> NA ---------------------
# (o script de analise converte para col_double(); celulas vazias tornam-se NA
#  e sao filtradas na etapa de data wrangling)
df$CustomerID <- na_if(trimws(df$CustomerID), "")

# --- Descricao ausente -> "NA" ----------------------------------------------
df$Description[is.na(df$Description) | df$Description == ""] <- "NA"

# ------------------------------------------------------------------------------
# 6. GRAVACAO DO CSV
# ------------------------------------------------------------------------------

dir.create(dirname(TARGET_CSV), showWarnings = FALSE, recursive = TRUE)

# write.csv com quote=FALSE e row.names=FALSE produz um CSV limpo, com
# separador decimal ponto (igual ao ficheiro original).
utils::write.csv(
  df,
  file    = TARGET_CSV,
  row.names = FALSE,
  quote     = FALSE,
  na        = ""            # CustomerID em falta -> campo vazio (célula vazia)
)

cat("CSV gravado em:", TARGET_CSV, "\n")

# ------------------------------------------------------------------------------
# 7. VALIDACAO DO RESULTADO
# ------------------------------------------------------------------------------

cat("\n=== 4/4. A validar o dataset obtido ===\n")

n_rows <- nrow(df)
n_cols <- ncol(df)

cat("Nº de linhas :", n_rows, "\n")
cat("Nº de colunas:", n_cols, "\n")

if (n_rows != EXPECTED_ROWS) {
  warning(
    sprintf("Esperava %d linhas mas obtive %d. Verifique a integridade da fonte.",
            EXPECTED_ROWS, n_rows)
  )
} else {
  cat("OK  numero de linhas conforme o esperado (", EXPECTED_ROWS, ").\n", sep = "")
}

if (n_cols != length(EXPECTED_COLS)) {
  stop("Numero inesperado de colunas.")
}

# Amostra das primeiras linhas, para inspeccao visual rapida.
cat("\nPrimeiras 3 linhas:\n")
print(utils::head(df, 3))

# Resumo de clientes unicos (deve ser ~4.372).
n_customers <- length(unique(na.omit(df$CustomerID)))
cat("\nClientes unicos (CustomerID):", format(n_customers, big.mark = ","), "\n")

cat("\n", strrep("=", 60), "\n", sep = "")
cat("DATASET PRONTO.\n")
cat("Ficheiro:", TARGET_CSV, "\n")
cat("Tamanho:", round(file.size(TARGET_CSV) / 1024^2, 1), "MB\n")
cat("\nProximo passo: executar a analise com\n")
cat("  source(\"R/01_ecommerce_churn_analysis.R\")\n")
cat("a partir da raiz do projeto.\n")
cat(strrep("=", 60), "\n", sep = "")

# Limpeza dos ficheiros temporarios
unlink(c(zip_path, unzip_dir), recursive = TRUE, force = TRUE)
