#!/usr/bin/env Rscript
# 02_reconstruct_sample.R — Reconstrução de trajetórias na amostra nomeada
# (Primeira Tarefa, itens 4-5): aplica config/state_mapping.csv aos 80 documentos
# com nomes e complementos (TJSP, TJCE, TJAL, TJMG × classes 7 e 436), grava
# episódios, transições, resumo por processo e auditoria, e carrega tudo no DuckDB.
#
# Uso:  Rscript scripts/02_reconstruct_sample.R

for (f in c("R/01_config.R", "R/02_utils.R", "R/04_parse_documents.R", "R/05_state_mapping.R")) source(f, encoding = "UTF-8")
suppressPackageStartupMessages({ library(DBI); library(duckdb) })
out_dir <- file.path(PATHS$outputs, "probe"); dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

named <- list.files(file.path(PATHS$probe, "named_samples"), full.names = TRUE)
parsed <- lapply(named, dj_parse_file)
proc <- rbindlist(lapply(parsed, `[[`, "processos"), fill = TRUE)
mov  <- rbindlist(lapply(parsed, `[[`, "movimentos"), fill = TRUE)
comp <- rbindlist(lapply(parsed, `[[`, "complementos"), fill = TRUE)
ass  <- rbindlist(lapply(parsed, `[[`, "assuntos"), fill = TRUE)
gjd_log(sprintf("amostra nomeada: %d docs, %d movimentos, %d complementos", nrow(proc), nrow(mov), nrow(comp)))

mapping <- load_state_mapping(); tpu <- load_tpu_movimentos()
mvs  <- assign_states(mov, comp, proc, mapping, tpu)
ep   <- reconstruct_episodes(mvs, proc)
traj <- summarise_trajectory(mvs, proc)
aud  <- audit_trajectories(traj, mvs)

# movimentos não mapeados: quais códigos ficaram de fora (para revisar o dicionário)
nao_mapeados <- mvs[is.na(estado), .N, by = .(mov_codigo, tpu_nome, tpu_caminho)][order(-N)]
transicoes <- ep[, .(de = estado, para = shift(estado, type = "lead"), quando = fim, dias_no_estado = dias), by = doc_id][!is.na(para)]
matriz <- dcast(transicoes[, .N, by = .(de, para)], de ~ para, value.var = "N", fill = 0)

fwrite(mvs,  file.path(out_dir, "movimentos_com_estado.csv"))
fwrite(ep,   file.path(out_dir, "episodios.csv"))
fwrite(traj, file.path(out_dir, "trajetorias_resumo.csv"))
fwrite(aud,  file.path(out_dir, "auditoria_trajetorias.csv"))
fwrite(nao_mapeados, file.path(out_dir, "movimentos_nao_mapeados.csv"))
fwrite(matriz, file.path(out_dir, "matriz_transicoes.csv"))

# ---- DuckDB (protótipo) ---------------------------------------------------------
dir.create(dirname(PATHS$duckdb), showWarnings = FALSE, recursive = TRUE)
con <- dbConnect(duckdb::duckdb(), PATHS$duckdb)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
sql_lines <- sub("--.*$", "", readLines(file.path(PATHS$sql, "01_schema.sql"), encoding = "UTF-8"))
for (stmt in strsplit(paste(sql_lines, collapse = "
"), ";")[[1]]) if (nzchar(trimws(stmt))) dbExecute(con, stmt)
write_replace <- function(name, dt) { dbExecute(con, sprintf("DELETE FROM %s", name)); dbWriteTable(con, name, as.data.frame(dt), append = TRUE) }
write_replace("processos", proc[, names(proc)[names(proc) %in% dbListFields(con, "processos")], with = FALSE])
write_replace("movimentos", mov[, .(doc_id, seq_origem, seq_crono, mov_codigo, mov_nome, mov_datahora_raw, mov_datahora, mov_oj_codigo, n_complementos, complementos_json)])
write_replace("complementos", comp); write_replace("assuntos", ass)
write_replace("tpu_movimentos", tpu[, .(codigo, codigo_pai = as.integer(codigo_pai), nome, situacao, nivel = as.integer(nivel), tem_filhos = as.logical(tem_filhos), caminho)])
dbExecute(con, "DELETE FROM tpu_versao"); dbExecute(con, sprintf("INSERT INTO tpu_versao VALUES ('%s','%s','SGT web service getDataUltimaVersao')", TPU$versao_data, TPU$consultado_em))
write_replace("state_mapping", mapping[, .(estado, mov_codigo, comp_descricao, comp_valor, papel, confianca, observacao)])
write_replace("estados", ep); write_replace("transicoes", transicoes)
gjd_log(sprintf("DuckDB: %s", PATHS$duckdb))

cat("\n== Auditoria por tribunal x classe ==\n"); print(aud, digits = 2)
cat("\n== Movimentos sem estado (top 15) ==\n"); print(head(nao_mapeados, 15))
cat("\n== Matriz de transições ==\n"); print(matriz)
gjd_log("02_reconstruct_sample.R concluído")
