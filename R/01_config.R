# 01_config.R — constantes, caminhos e parâmetros do projeto
# Fonte única de verdade para caminhos e parâmetros. Nada aqui faz I/O de rede.

PROJECT_ROOT <- normalizePath(
  if (nzchar(Sys.getenv("GJD_ROOT"))) Sys.getenv("GJD_ROOT") else
    tryCatch(rprojroot::find_root(rprojroot::has_file("CLAUDE.md")), error = function(e) getwd()),
  winslash = "/", mustWork = TRUE
)

PATHS <- list(
  root        = PROJECT_ROOT,
  raw         = file.path(PROJECT_ROOT, "data", "raw"),
  raw_datajud = file.path(PROJECT_ROOT, "data", "raw", "datajud"),
  probe       = file.path(PROJECT_ROOT, "data", "raw", "datajud_probe"),
  reference   = file.path(PROJECT_ROOT, "data", "reference"),
  processed   = file.path(PROJECT_ROOT, "data", "processed"),
  duckdb      = file.path(PROJECT_ROOT, "data", "processed", "gjd.duckdb"),
  outputs     = file.path(PROJECT_ROOT, "outputs"),
  logs        = file.path(PROJECT_ROOT, "logs"),
  config      = file.path(PROJECT_ROOT, "config"),
  sql         = file.path(PROJECT_ROOT, "sql")
)

# ---- DataJud (API Pública) --------------------------------------------------
# A chave pública é publicada pelo CNJ em https://datajud-wiki.cnj.jus.br/api-publica/acesso/
# e pode ser trocada a qualquer momento. Por política do repositório (CLAUDE.md, item 6),
# ela NÃO fica no código: defina DATAJUD_API_KEY no .Renviron (ver README).
DATAJUD <- list(
  base_url   = "https://api-publica.datajud.cnj.jus.br",
  api_key    = { k <- Sys.getenv("DATAJUD_API_KEY"); if (!nzchar(k)) stop("Defina DATAJUD_API_KEY no .Renviron (chave pública: https://datajud-wiki.cnj.jus.br/api-publica/acesso/)"); k },
  page_size  = 1000L,          # documentado: 10..10000; 1000 equilibra latência e payload
  min_sleep  = 1.0,            # segundos entre requisições (não sobrecarregar a API)
  max_tries  = 6L,             # retentativas com backoff exponencial em 429/5xx/timeout
  timeout    = 180,            # segundos por requisição (TJSP/TJPR chegam a 60-80 s)
  sort_field = "@timestamp",   # único campo de ordenação documentado para search_after
  user_agent = "GJD-research-client/0.1 (R httr2; academic use; contact: see README)"
)

# ---- Escopo da fase inicial ---------------------------------------------------
SCOPE <- list(
  classes = c(
    `7`   = "Procedimento Comum Cível",
    `436` = "Procedimento do Juizado Especial Cível"
  ),
  # candidatos avaliados na sondagem (ver docs/01_feasibility_report.md)
  tribunais_sondagem = c("tjsp","tjmg","tjrs","tjpr","tjba","tjdft","tjgo","tjpe","tjsc","tjrj","tjal","tjce"),
  coortes = 2018:2023,
  data_corte_observacao = as.Date("2026-08-31")   # censura administrativa (ver utils)
)

# ---- TPU ----------------------------------------------------------------------
TPU <- list(
  sgt_ws       = "https://www.cnj.jus.br/sgt/sgt_ws.php",
  versao_data  = "2026-05-26",   # getDataUltimaVersao() em 2026-09-04 devolveu 26/05/2026
  consultado_em = "2026-09-04"
)
