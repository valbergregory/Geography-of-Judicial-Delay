# 00_setup.R — ambiente reproduzível (R 4.4.3, Windows). Execute uma vez:
#   Rscript R/00_setup.R            # instala o que falta (fase 1: coleta + reconstrução)
#   Rscript R/00_setup.R --full     # inclui sobrevivência, espacial e ML (fases 2+)
# Depois: renv::init(bare = TRUE); renv::snapshot() para congelar versões (renv.lock).
args <- commandArgs(trailingOnly = TRUE)
fase1 <- c("httr2", "jsonlite", "data.table", "digest", "cli", "rprojroot", "yaml", "DBI", "duckdb",
           "testthat", "dplyr", "tidyr", "purrr", "stringr", "lubridate", "ggplot2", "targets", "tarchetypes", "quarto")
full  <- c(fase1,
           # sobrevivência / multiestado / competing risks / frailty
           "survival", "survminer", "flexsurv", "mstate", "cmprsk", "coxme", "frailtypack", "riskRegression", "pec", "timeROC",
           # hierárquico / efeitos fixos / causal
           "lme4", "fixest", "did", "gsynth", "synthdid", "marginaleffects",
           # espacial
           "sf", "spdep", "spatialreg", "geobr", "sidrar", "terra",
           # ML de sobrevivência e calibração
           "ranger", "randomForestSRC", "xgboost", "aorsf", "mlr3", "mlr3proba", "tidymodels", "censored",
           # tabelas / figuras / painel
           "modelsummary", "gt", "kableExtra", "patchwork", "shiny", "leaflet")
want <- if ("--full" %in% args) full else fase1
miss <- want[!vapply(want, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  message("Instalando: ", paste(miss, collapse = ", "))
  # synthdid não está no CRAN; mlr3proba está no r-universe
  cran <- setdiff(miss, c("synthdid", "mlr3proba"))
  if (length(cran)) install.packages(cran, repos = "https://cloud.r-project.org")
  if ("mlr3proba" %in% miss) install.packages("mlr3proba", repos = c("https://mlr-org.r-universe.dev", "https://cloud.r-project.org"))
  if ("synthdid" %in% miss) { if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes"); remotes::install_github("synth-inference/synthdid") }
} else message("Todos os pacotes da fase já instalados.")
writeLines(capture.output(sessionInfo()), "logs/sessionInfo_setup.txt")
