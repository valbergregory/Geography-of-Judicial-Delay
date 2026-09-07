#!/usr/bin/env Rscript
# 01_probe_datajud.R — Diagnóstico da API Pública do DataJud (Primeira Tarefa, itens 1-3, 6-7)
# Reproduz, a partir dos arquivos em data/raw/datajud_probe/ (baixados em 2026-09-04/05
# e verificados por SHA-256), as tabelas de esquema, cobertura e completude usadas em
# docs/01_feasibility_report.md. Com --live, faz também uma chamada real curta
# (2 páginas de 20 docs no TJCE via search_after) para validar o cliente R.
#
# Uso:  Rscript scripts/01_probe_datajud.R [--live]

args <- commandArgs(trailingOnly = TRUE)
LIVE <- "--live" %in% args
for (f in c("R/01_config.R", "R/02_utils.R", "R/03_datajud_client.R", "R/04_parse_documents.R")) source(f, encoding = "UTF-8")
dir.create(file.path(PATHS$outputs, "probe"), showWarnings = FALSE, recursive = TRUE)

# ---- 0. integridade dos arquivos da sondagem ----------------------------------
sums <- fread(file.path(PATHS$probe, "SHA256SUMS.txt"), header = FALSE, sep = " ", col.names = c("sha256", "path"))
sums[, path := sub("^\\*", "", trimws(path))]
sums[, ok := vapply(file.path(PATHS$root, path), function(p) file.exists(p) && sha256_file(p) == sha256[path == sub(paste0(PATHS$root, "/"), "", p, fixed = TRUE)], logical(1))]
gjd_log(sprintf("integridade da sondagem: %d/%d arquivos com hash conferido", sum(sums$ok), nrow(sums)))
stopifnot(all(sums$ok))

# ---- 1. esquema: campos presentes por tribunal (amostras nomeadas) --------------
named <- list.files(file.path(PATHS$probe, "named_samples"), full.names = TRUE)
schema <- rbindlist(lapply(named, function(f) {
  js <- jsonlite::fromJSON(f, simplifyVector = FALSE); hits <- js$hits$hits
  if (!length(hits)) return(NULL)
  keys <- sort(unique(unlist(lapply(hits, function(h) names(h[["_source"]])))))
  mkeys <- sort(unique(unlist(lapply(hits, function(h) unlist(lapply(h[["_source"]]$movimentos, names))))))
  data.table(arquivo = basename(f), tribunal = hits[[1]][["_source"]]$tribunal, n = length(hits),
             campos_processo = paste(keys, collapse = ","), campos_movimento = paste(mkeys, collapse = ","))
}))
fwrite(schema, file.path(PATHS$outputs, "probe", "schema_por_tribunal.csv"))

# ---- 2. completude e cobertura (amostras aleatórias de 500 docs) ----------------
rs <- list.files(file.path(PATHS$probe, "random_samples"), full.names = TRUE)
parsed <- lapply(rs, function(f) tryCatch(dj_parse_file(f), error = function(e) NULL))
proc <- rbindlist(lapply(parsed, `[[`, "processos"), fill = TRUE)
mov  <- rbindlist(lapply(parsed, `[[`, "movimentos"), fill = TRUE)
gjd_log(sprintf("amostras aleatórias: %d documentos, %d movimentos", nrow(proc), nrow(mov)))

# nota: as amostras aleatórias foram baixadas com _source reduzido (sem nome/complementos)
completude <- merge(
  proc[, .(n_docs = .N,
           p_grau_g1_je = mean(grau %in% c("G1", "JE")),
           fmt_data = paste(names(sort(table(data_ajuizamento_fmt), decreasing = TRUE)), collapse = "/"),
           p_data_ajuiz_ok = mean(!is.na(data_ajuizamento)),
           p_ibge_ok = mean(!is.na(oj_municipio_ibge) & oj_municipio_ibge > 0),
           p_sem_movimentos = mean(n_movimentos == 0),
           mediana_n_mov = median(n_movimentos),
           p_cnj_valido = mean(cnj_valido)), by = .(tribunal, classe_codigo)],
  mov[, .(p_mov_sem_codigo = mean(is.na(mov_codigo)), p_mov_sem_data = mean(is.na(mov_datahora))), by = .(doc_id)][
    proc[, .(doc_id, tribunal, classe_codigo)], on = "doc_id"][
    , .(p_mov_sem_codigo = mean(p_mov_sem_codigo, na.rm = TRUE), p_mov_sem_data = mean(p_mov_sem_data, na.rm = TRUE)), by = .(tribunal, classe_codigo)],
  by = c("tribunal", "classe_codigo"), all.x = TRUE)
fwrite(completude, file.path(PATHS$outputs, "probe", "completude_por_tribunal_classe.csv"))

coortes <- proc[, .N, by = .(tribunal, classe_codigo, cnj_ano)][order(tribunal, classe_codigo, cnj_ano)]
fwrite(coortes, file.path(PATHS$outputs, "probe", "coortes_amostra_por_ano_cnj.csv"))

# totais reportados pelo índice (agregações salvas em coverage/*_A.json)
cov <- rbindlist(lapply(list.files(file.path(PATHS$probe, "coverage"), pattern = "_A\\.json$", full.names = TRUE), function(f) {
  js <- jsonlite::fromJSON(f, simplifyVector = FALSE); if (!is.null(js$error)) return(NULL)
  rbindlist(lapply(js$aggregations$por_classe$buckets, function(b) data.table(
    tribunal = toupper(sub("_A\\.json$", "", basename(f))), classe_codigo = b$key, total_indice = b$doc_count,
    sem_movimentos = b$sem_mov$doc_count, ibge_zero = b$ibge_zero$doc_count, ibge_missing = b$ibge_missing$doc_count,
    graus = paste(sapply(b$por_grau$buckets, function(x) sprintf("%s:%d", x$key, x$doc_count)), collapse = " "),
    sistemas = paste(sapply(b$por_sistema$buckets, function(x) sprintf("%s:%d", x$key, x$doc_count)), collapse = " "))))
}))
fwrite(cov, file.path(PATHS$outputs, "probe", "cobertura_indice_por_tribunal_classe.csv"))

# ---- 3. horizonte de observação: ano do último movimento por coorte --------------
horiz <- mov[!is.na(mov_datahora), .(ultimo_mov = max(mov_datahora)), by = doc_id][proc, on = "doc_id"][
  , .(n = .N, p_ultimo_mov_2025_26 = mean(format(ultimo_mov, "%Y") >= "2025", na.rm = TRUE),
      mediana_ult_atual = as.Date(median(data_ultima_atualizacao, na.rm = TRUE))), by = .(tribunal, classe_codigo)]
fwrite(horiz, file.path(PATHS$outputs, "probe", "horizonte_observacao.csv"))

print(completude[order(-p_ibge_ok)]); print(cov[order(tribunal)]); print(horiz)

# ---- 4. (opcional) chamada real curta: valida cliente, search_after e tiebreaker ----
if (LIVE) {
  gjd_log("LIVE: 2 páginas de 20 docs no TJCE, classe 436, search_after por @timestamp")
  res <- dj_collect_class("tjce", classes = 436, size = 20, max_pages = 2,
                          out_dir = file.path(PATHS$probe, "live_test"), checkpoint = tempfile(fileext = ".json"))
  files <- list.files(file.path(PATHS$probe, "live_test"), pattern = "^tjce_p", full.names = TRUE)
  ids <- unlist(lapply(files, function(f) vapply(jsonlite::fromJSON(f, simplifyVector = FALSE)$hits$hits, `[[`, "", "_id")))
  gjd_log(sprintf("LIVE: %d páginas, %d docs, %d ids únicos (duplicados por empate de @timestamp: %d)", res$pages, length(ids), uniqueN(ids), length(ids) - uniqueN(ids)))
}
gjd_log("01_probe_datajud.R concluído; saídas em outputs/probe/")
