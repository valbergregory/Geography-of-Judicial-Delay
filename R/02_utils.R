# 02_utils.R — utilidades: log, hash, datas heterogêneas do DataJud, número CNJ

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(digest); library(cli)
})

# ---- log em arquivo + console --------------------------------------------------
gjd_log <- function(..., level = "INFO", file = file.path(PATHS$logs, "gjd.log")) {
  msg <- sprintf("%s [%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, paste0(..., collapse = ""))
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
  cat(msg, "\n", file = file, append = TRUE)
  if (level %in% c("WARN", "ERROR")) cli::cli_alert_warning(msg) else cli::cli_alert_info(msg)
  invisible(msg)
}

sha256_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE)
sha256_str  <- function(x)    digest::digest(x,    algo = "sha256", serialize = FALSE)

# ---- datas do DataJud -----------------------------------------------------------
# A sondagem (2026-09-04) encontrou três formatos em `dataAjuizamento`, às vezes
# no MESMO índice: ISO-8601 ("2019-03-26T13:58:58.000Z"), compacto
# "yyyyMMddHHmmss" ("20190326135858") e epoch em milissegundos (numérico, TJMG).
# `movimentos.dataHora` veio sempre ISO (ou NULL). Nunca confie no parse do
# Elasticsearch para agregações por ano: use esta função no cliente.
parse_datajud_datetime <- function(x) {
  x <- as.character(x)
  out <- rep(as.POSIXct(NA, tz = "UTC"), length(x))
  iso  <- !is.na(x) & grepl("^\\d{4}-\\d{2}-\\d{2}", x)
  cmp  <- !is.na(x) & grepl("^\\d{14}$", x)
  epo  <- !is.na(x) & grepl("^\\d{10,13}$", x)
  if (any(iso)) out[iso] <- as.POSIXct(sub("Z$", "", sub("\\.\\d+", "", x[iso])), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  if (any(cmp)) out[cmp] <- as.POSIXct(x[cmp], format = "%Y%m%d%H%M%S", tz = "UTC")
  if (any(epo)) { v <- as.numeric(x[epo]); v <- ifelse(v > 1e11, v / 1000, v); out[epo] <- as.POSIXct(v, origin = "1970-01-01", tz = "UTC") }
  # datas impossíveis viram NA (auditoria conta quantas)
  out[!is.na(out) & (out < as.POSIXct("1988-01-01", tz = "UTC") | out > as.POSIXct("2030-01-01", tz = "UTC"))] <- NA
  out
}
datajud_date_format <- function(x) {
  x <- as.character(x)
  fifelse(is.na(x), NA_character_,
    fifelse(grepl("^\\d{4}-", x), "iso", fifelse(grepl("^\\d{14}$", x), "compact14", fifelse(grepl("^\\d{10,13}$", x), "epoch", "other"))))
}

# ---- número CNJ (Res. CNJ 65/2008): NNNNNNN-DD.AAAA.J.TR.OOOO ----------------
parse_cnj <- function(numero) {
  n <- gsub("\\D", "", as.character(numero))
  ok <- nchar(n) == 20
  data.table(
    numero_cnj   = n,
    cnj_valido   = ok,
    cnj_seq      = ifelse(ok, substr(n, 1, 7), NA),
    cnj_dv       = ifelse(ok, substr(n, 8, 9), NA),
    cnj_ano      = ifelse(ok, as.integer(substr(n, 10, 13)), NA_integer_),
    cnj_segmento = ifelse(ok, as.integer(substr(n, 14, 14)), NA_integer_),   # 8 = Justiça Estadual
    cnj_tribunal = ifelse(ok, substr(n, 15, 16), NA),
    cnj_origem   = ifelse(ok, substr(n, 17, 20), NA)                          # unidade de origem (foro)
  )
}
# dígito verificador (módulo 97, base 10) — usado na auditoria de duplicidade/erro de digitação
cnj_check_digit_ok <- function(numero) {
  n <- gsub("\\D", "", as.character(numero)); if (any(nchar(n) != 20)) return(rep(NA, length(n)))
  seq <- substr(n, 1, 7); dv <- as.integer(substr(n, 8, 9)); rest <- substr(n, 10, 20)
  # cálculo em blocos para evitar overflow: (seq || rest || "00") mod 97
  mod97 <- function(s) { r <- 0; for (ch in strsplit(s, "")[[1]]) r <- (r * 10 + as.integer(ch)) %% 97; r }
  vapply(seq_along(n), function(i) (98 - mod97(paste0(seq[i], rest[i], "00"))) == dv[i], logical(1))
}
