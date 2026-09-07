# 03_datajud_client.R — cliente resiliente da API Pública do DataJud (httr2)
#
# Esquema confirmado em 2026-09-04 (ver docs/01_feasibility_report.md):
#   POST {base}/api_publica_{tribunal}/_search  com  Authorization: APIKey <chave>
#   corpo = Elasticsearch Query DSL; paginação por sort [@timestamp asc] + search_after;
#   `size` 10..10000; agregações funcionam em campos numéricos e em *.keyword.
# Não há PIT (point-in-time): a coleta é "eventualmente consistente" — documentos
# reindexados durante a varredura mudam de @timestamp e podem aparecer duas vezes
# ou escapar. Por isso: dedupe por `id` e re-varredura incremental por
# dataHoraUltimaAtualizacao >= último checkpoint.

suppressPackageStartupMessages({ library(httr2); library(jsonlite); library(data.table); library(digest) })

dj_endpoint <- function(tribunal) sprintf("%s/api_publica_%s/_search", DATAJUD$base_url, tolower(tribunal))

# registro de toda requisição (auditoria de erros, repetições e cobertura)
dj_request_log <- function(rec, file = file.path(PATHS$logs, "datajud_requests.csv")) {
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
  data.table::fwrite(as.data.table(rec), file, append = file.exists(file))
}

# Uma requisição com retentativas/backoff. Devolve lista (json parseado) ou erro.
dj_search <- function(tribunal, body, cache_dir = NULL, tag = "search") {
  body_json <- jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA)
  key <- substr(sha256_str(paste0(tribunal, body_json)), 1, 16)
  cache_file <- if (!is.null(cache_dir)) file.path(cache_dir, sprintf("%s_%s_%s.json", tolower(tribunal), tag, key)) else NULL
  if (!is.null(cache_file) && file.exists(cache_file)) {
    return(jsonlite::fromJSON(cache_file, simplifyVector = FALSE))
  }
  req <- httr2::request(dj_endpoint(tribunal)) |>
    httr2::req_method("POST") |>
    httr2::req_headers(Authorization = paste("APIKey", DATAJUD$api_key), `Content-Type` = "application/json") |>
    httr2::req_user_agent(DATAJUD$user_agent) |>
    httr2::req_body_raw(body_json, type = "application/json") |>
    httr2::req_timeout(DATAJUD$timeout) |>
    httr2::req_retry(max_tries = DATAJUD$max_tries, backoff = ~ min(60, 2 ^ .x),
                     is_transient = function(resp) httr2::resp_status(resp) %in% c(408, 429, 500, 502, 503, 504)) |>
    httr2::req_error(is_error = function(resp) FALSE)
  t0 <- Sys.time()
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  Sys.sleep(DATAJUD$min_sleep)
  if (inherits(resp, "error")) {
    dj_request_log(list(ts = format(t0), tribunal = tribunal, tag = tag, key = key, status = NA, took_ms = NA, hits = NA, secs = elapsed, error = conditionMessage(resp)))
    stop("DataJud: falha após retentativas em ", tribunal, ": ", conditionMessage(resp))
  }
  status <- httr2::resp_status(resp)
  txt <- httr2::resp_body_string(resp)
  js <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  nh <- if (!is.null(js$hits$hits)) length(js$hits$hits) else NA
  dj_request_log(list(ts = format(t0), tribunal = tribunal, tag = tag, key = key, status = status, took_ms = js$took %||% NA, hits = nh, secs = elapsed,
                      error = if (status >= 400) substr(txt, 1, 200) else ""))
  if (status >= 400 || is.null(js)) stop("DataJud HTTP ", status, " em ", tribunal, ": ", substr(txt, 1, 300))
  if (!is.null(cache_file)) { dir.create(dirname(cache_file), showWarnings = FALSE, recursive = TRUE); writeLines(txt, cache_file, useBytes = TRUE) }
  js
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Filtro padrão por classe(s) e, opcionalmente, por intervalo de dataAjuizamento.
# ATENÇÃO: o formato de data aceito pelo range varia por índice (ISO no TJSP,
# "yyyyMMddHHmmss" em TJAL/TJCE/…). Prefira filtrar por classe e derivar o ano
# do número CNJ no cliente (parse_cnj), como faz dj_collect_class().
dj_query_classe <- function(classes, extra_filters = list()) {
  list(bool = list(filter = c(list(list(terms = list(`classe.codigo` = as.list(as.integer(classes))))), extra_filters)))
}

# Varredura completa e retomável de (tribunal, classes) com search_after.
# Salva cada página no cache e um checkpoint com o último `sort` devolvido.
dj_collect_class <- function(tribunal, classes, size = DATAJUD$page_size, max_pages = Inf,
                             source_fields = NULL, out_dir = file.path(PATHS$raw_datajud, tolower(tribunal)),
                             checkpoint = file.path(out_dir, sprintf("checkpoint_%s.json", paste(classes, collapse = "-")))) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  after <- if (file.exists(checkpoint)) jsonlite::fromJSON(checkpoint)$search_after else NULL
  page <- if (file.exists(checkpoint)) jsonlite::fromJSON(checkpoint)$page else 0L
  n_total <- 0L
  repeat {
    if (page >= max_pages) break
    body <- list(size = size, query = dj_query_classe(classes), sort = list(setNames(list(list(order = "asc")), DATAJUD$sort_field)),
                 track_total_hits = TRUE)
    if (!is.null(source_fields)) body[["_source"]] <- source_fields
    if (!is.null(after)) body$search_after <- as.list(after)
    js <- dj_search(tribunal, body, cache_dir = out_dir, tag = sprintf("p%05d", page))
    hits <- js$hits$hits
    if (length(hits) == 0) { gjd_log("dj_collect_class: fim em ", tribunal, " após ", page, " páginas"); break }
    page <- page + 1L; n_total <- n_total + length(hits)
    after <- hits[[length(hits)]]$sort
    jsonlite::write_json(list(tribunal = tribunal, classes = classes, page = page, search_after = after,
                              total_reported = js$hits$total$value, collected = n_total, ts = format(Sys.time())),
                         checkpoint, auto_unbox = TRUE)
    gjd_log(sprintf("%s classes=%s página %d: %d docs (acum. %d de ~%s)", tribunal, paste(classes, collapse = ","), page, length(hits), n_total, js$hits$total$value))
    if (length(hits) < size) break
  }
  invisible(list(pages = page, collected = n_total))
}

# Agregação leve (size 0) — usada nas auditorias de cobertura.
dj_aggregate <- function(tribunal, query, aggs, cache_dir = file.path(PATHS$probe, "coverage")) {
  dj_search(tribunal, list(size = 0, track_total_hits = TRUE, query = query, aggs = aggs), cache_dir = cache_dir, tag = "agg")
}
