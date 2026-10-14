# ==============================================================================
# UC: Seminario de Sistemas e Aplicacoes (SSA - MEINF / UFP)
# Projeto: Previsao de Churn e Otimizacao do CLV no E-Commerce
# Script: 01_ecommerce_churn_analysis.R
# Descricao: Pipeline completo de carregamento, limpeza, integracao de API REST,
#            engenharia de atributos RFM, analise exploratoria e modelacao preditiva.
# ==============================================================================

# 1. CARREGAMENTO DE PACOTES
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(tidyverse) # dplyr, ggplot2, tidyr, readr, stringr
  library(lubridate) # Manipulacao de datas e carimbos temporais
  library(httr2) # Requisicoes HTTP para API REST
  library(jsonlite) # Parsing de JSON da API
  library(caret) # Matrizes de confusao e metricas de machine learning
})

# 2. DEFINICAO DE CAMINHOS RELATIVOS (REPRODUZIBILIDADE)
# ------------------------------------------------------------------------------
# Evitar caminhos absolutos locais (cumprindo os requisitos do Guiao de Projeto)
data_dir <- file.path("data", "raw")
out_dir <- file.path("data", "processed")
fig_dir <- file.path("docs", "figures")

dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# Definir caminho relativo do dataset
dataset_path <- if (file.exists(file.path(data_dir, "Online Retail.csv"))) {
  file.path(data_dir, "Online Retail.csv")
} else if (file.exists(file.path(data_dir, "OnlineRetail.csv"))) {
  file.path(data_dir, "OnlineRetail.csv")
} else {
  file.path(data_dir, "Online Retail.csv") # Fallback padrao
}

cat("=== 1. Carregando os Dados Transacionais ===
")
cat("Caminho do ficheiro:", dataset_path, "
")

# 3. LEITURA E INSPECAO INICIAL DOS DADOS
# ------------------------------------------------------------------------------
df_raw <- read_csv(
  dataset_path,
  col_types = cols(
    InvoiceNo   = col_character(),
    StockCode   = col_character(),
    Description = col_character(),
    Quantity    = col_integer(),
    InvoiceDate = col_character(), # Convertido de seguida com lubridate
    UnitPrice   = col_double(),
    CustomerID  = col_double(),
    Country     = col_character()
  )
)

cat("Dimensao original dos dados brutos:", nrow(df_raw), "linhas e", ncol(df_raw), "colunas.

")

# 4. TRATAMENTO E DATA WRANGLING (LIMPEZA DE DADOS)
# ------------------------------------------------------------------------------
cat("=== 2. Realizando Limpeza e Formatacao dos Dados ===
")

df_clean <- df_raw %>%
  # A. Converter InvoiceDate para formato POSIXct (Data/Hora)
  mutate(
    InvoiceDate = parse_date_time(InvoiceDate, orders = c("d/m/Y H:M", "m/d/Y H:M", "Y-m-d H:M:S"))
  ) %>%
  # B. Identificar e isolar devolucoes (Faturas iniciadas por 'C' ou Quantidade < 0)
  mutate(
    Is_Return = str_detect(InvoiceNo, "^C") | Quantity < 0
  ) %>%
  # C. Filtrar registos validos sem CustomerID em falta e precos unitarios positivos
  filter(
    !is.na(CustomerID),
    UnitPrice > 0
  ) %>%
  # D. Criar variavel de valor total por linha em GBP (Moeda base original)
  mutate(
    LineTotal_GBP = Quantity * UnitPrice
  )

cat("Dimensao apos remocao de NAs e precos invalidos:", nrow(df_clean), "linhas.

")

# 5. INTEGRACAO DA API REST CAMBIAL (OPEN EXCHANGE RATES)
# ------------------------------------------------------------------------------
cat("=== 3. Consumindo API REST Cambial para Padronizacao de Moedas ===
")

# Funcao de obtencao da taxa cambial via API REST com suporte a fallback
get_gbp_to_eur_rate <- function(base_curr = "GBP", target_curr = "EUR", api_url = NULL) {
  rate <- 1.17 # Taxa de fallback padrao (1 GBP = 1.17 EUR)
  if (!is.null(api_url)) {
    tryCatch(
      {
        resp <- request(api_url) %>% req_perform()
        json_data <- resp_body_json(resp)
        rate <- json_data[[target_curr]]
        cat("Taxa obtida via API REST (", base_curr, " -> ", target_curr, "):", rate, "
")
      },
      error = function(e) {
        cat("Aviso: Conexao API indisponivel. Utilizando taxa cambial padrao:", rate, "
")
      }
    )
  } else {
    cat("Modo offline: Utilizando taxa cambial padrao de conversao (1 GBP =", rate, "EUR)
")
  }
  return(rate)
}

gbp_to_eur <- get_gbp_to_eur_rate("GBP", "EUR")

# Converter valores transacionais para EUR
df_clean <- df_clean %>%
  mutate(
    LineTotal_EUR = LineTotal_GBP * gbp_to_eur
  )

# 6. ENGENHARIA DE ATRIBUTOS RFM E VARIAVEL DE CHURN
# ------------------------------------------------------------------------------
cat("
=== 4. Engenharia de Atributos: Construcao da Matriz RFM ===
")

# Definir a data de referencia da analise (ultimo dia registado no dataset + 1 dia)
max_date <- max(df_clean, na.rm = TRUE) + days(1)
cat("Data de Referencia da Analise:", format(max_date, "%Y-%m-%d"), "
")

# Agregacao ao nivel do Cliente (CustomerID)
rfm_df <- df_clean %>%
  group_by(CustomerID) %>%
  summarise(
    # Recencia: Dias desde a ultima compra
    LastPurchaseDate = max(InvoiceDate, na.rm = TRUE),
    Recency_Days = as.numeric(difftime(max_date, LastPurchaseDate, units = "days")),

    # Frequencia: Numero total de encomendas unicas (excluindo devolucoes)
    Frequency_Orders = n_distinct(InvoiceNo[!Is_Return]),

    # Valor Monetario: Soma de todas as linhas de compra em EUR
    Monetary_Total = sum(LineTotal_EUR[!Is_Return], na.rm = TRUE),

    # Racio de Devolucoes: Proporcao de linhas de devolucao sobre o total
    Total_Transactions = n(),
    Return_Transactions = sum(Is_Return),
    Return_Ratio = Return_Transactions / Total_Transactions,

    # Pais principal do cliente
    Country = first(Country),
    .groups = "drop"
  ) %>%
  # Filtrar clientes sem compras validas
  filter(Monetary_Total > 0) %>%
  # Criar Variavel Resposta (Target): Churn_90d
  # Churn = 1 se o cliente nao compra ha mais de 90 dias; 0 caso contrario
  mutate(
    Churn_90d = factor(if_else(Recency_Days > 90, 1, 0), levels = c(0, 1), labels = c("Ativo", "Churn")),
    # Log-transform do valor monetario para estabilizar variancia
    Log_Monetary = log1p(Monetary_Total)
  )

cat("Total de Clientes Unicos Analisados:", nrow(rfm_df), "
")
cat("Distribuicao da Variavel de Churn:
")
print(table(rfm_df))

# Guardar dataset limpo e processado
write_csv(rfm_df, file.path(out_dir, "customer_rfm_churn_processed.csv"))
cat("
Dataset processado guardado em:", file.path(out_dir, "customer_rfm_churn_processed.csv"), "

")

# 7. ANALISE EXPLORATORIA DE DADOS (EDA) COM GGPLOT2
# ------------------------------------------------------------------------------
cat("=== 5. Gerando Visualizacoes Exploratorias com ggplot2 ===
")

# Grafico 1: Distribuicao de Churn por Segmento de Despesa (Boxplot)
p1 <- ggplot(rfm_df, aes(x = Churn_90d, y = Log_Monetary, fill = Churn_90d)) +
  geom_boxplot(alpha = 0.7, outlier.color = "red", outlier.shape = 1) +
  scale_fill_manual(values = c("Ativo" = "#1B9E77", "Churn" = "#D95F02")) +
  theme_minimal() +
  labs(
    title = "Distribuicao do Valor Monetario (Log) por Estado de Churn",
    subtitle = "Comparacao entre clientes ativos e clientes em inatividade (>90 dias)",
    x = "Estado do Cliente (Churn a 90 Dias)",
    y = "Log(1 + Valor Monetario em EUR)",
    fill = "Estado"
  ) +
  theme(plot.title = element_text(face = "bold", size = 12))

ggsave(file.path(fig_dir, "eda_boxplot_churn_monetary.png"), plot = p1, width = 7, height = 5)

# Grafico 2: Relacao Dispersao entre Frequencia e Recencia
p2 <- ggplot(rfm_df, aes(x = Recency_Days, y = Frequency_Orders, color = Churn_90d)) +
  geom_point(alpha = 0.6, size = 2) +
  scale_color_manual(values = c("Ativo" = "#1B9E77", "Churn" = "#D95F02")) +
  scale_y_log10() +
  theme_minimal() +
  labs(
    title = "Frequencia de Encomendas vs. Recencia em Dias",
    subtitle = "Escala logaritmica na frequencia de encomendas",
    x = "Recencia (Dias sem Comprar)",
    y = "Frequencia (N. de Encomendas)",
    color = "Estado"
  ) +
  theme(plot.title = element_text(face = "bold", size = 12))

ggsave(file.path(fig_dir, "eda_scatter_frequency_recency.png"), plot = p2, width = 7, height = 5)

cat("Visualizacoes guardadas com sucesso na pasta 'docs/figures/'.

")

# 8. MODELACAO PREDITIVA (REGRESSAO LOGISTICA)
# ------------------------------------------------------------------------------
cat("=== 6. Treinando Modelo de Regressao Logistica para Previsao de Churn ===
")

# Divisao dos dados em Treino (70%) e Teste (30%)
set.seed(123)
train_index <- createDataPartition(rfm_df, p = 0.70, list = FALSE)
train_set <- rfm_df[train_index, ]
test_set <- rfm_df[-train_index, ]

# Ajustar Regressao Logistica (Prever Churn a partir da Frequencia, Valor Monetario e Racio de Devolucoes)
model_logit <- glm(
  Churn_90d ~ Frequency_Orders + Log_Monetary + Return_Ratio,
  data = train_set,
  family = binomial(link = "logit")
)

cat("
--- Sumario Estatistico do Modelo de Regressao Logistica ---
")
print(summary(model_logit))

# Avaliacao no Conjunto de Teste
test_preds_prob <- predict(model_logit, newdata = test_set, type = "response")
test_preds_class <- factor(if_else(test_preds_prob > 0.5, "Churn", "Ativo"), levels = c("Ativo", "Churn"))

cat("
--- Matriz de Confusao no Conjunto de Teste ---
")
conf_matrix <- confusionMatrix(test_preds_class, test_set, positive = "Churn")
print(conf_matrix)

cat("
=== Execucao do Script R Concluida com Sucesso! ===
")
