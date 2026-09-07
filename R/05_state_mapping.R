# 05_state_mapping.R — dicionário transparente TPU -> estados substantivos e
# reconstrução de trajetórias (episódios e transições) com auditoria.
#
# Princípios (ver docs/01_feasibility_report.md, seção 5):
#  * O mapeamento é DADO (config/state_mapping.csv), não código: cada linha diz
#    qual código (ou subárvore da TPU, via prefixo de caminho) e qual complemento
#    entram em qual estado, com que papel e com que confiança.
#  * Movimentos ambíguos NÃO são forçados: recebem estado NA e são contados.
#  * A ordem cronológica é reconstruída por dataHora (o tribunal nem sempre envia em ordem).
#  * Censura à direita = dataHoraUltimaAtualizacao do documento (não "hoje").

suppressPackageStartupMessages({ library(data.table) })

STATE_ORDER <- c("distribuicao","analise_inicial","citacao","defesa","instrucao","audiencia",
                 "conclusao_julgamento","sentenca","recurso","julgamento_recursal","cumprimento","baixa")

load_tpu_movimentos <- function(path = file.path(PATHS$reference, "tpu", sprintf("tpu_movimentos_%s.csv", TPU$versao_data))) {
  tpu <- fread(path, encoding = "UTF-8")
  tpu[, codigo := as.integer(codigo)]
  tpu
}

load_state_mapping <- function(path = file.path(PATHS$config, "state_mapping.csv")) {
  m <- fread(path, encoding = "UTF-8", colClasses = "character")
  m[, mov_codigo := suppressWarnings(as.integer(mov_codigo))]
  m[, comp_valor := suppressWarnings(as.integer(comp_valor))]
  m[comp_descricao == "", comp_descricao := NA_character_]
  m[caminho_prefixo == "", caminho_prefixo := NA_character_]
  m[grau == "", grau := NA_character_]
  m
}

# Atribui a cada movimento (com seus complementos) o estado/papel/confiança.
# Regra de precedência: (1) código + complemento específico; (2) código sem complemento;
# (3) prefixo de caminho na TPU (subárvore). O primeiro match na ordem do CSV vence.
assign_states <- function(mov, comp, proc, mapping = load_state_mapping(), tpu = load_tpu_movimentos()) {
  mv <- copy(mov)
  mv <- merge(mv, tpu[, .(mov_codigo = codigo, tpu_caminho = caminho, tpu_nome = nome)], by = "mov_codigo", all.x = TRUE, sort = FALSE)
  mv <- merge(mv, proc[, .(doc_id, grau)], by = "doc_id", all.x = TRUE, sort = FALSE)
  # complementos como lista compacta "descricao=valor" por movimento
  cp <- if (nrow(comp)) comp[, .(comp_key = paste0("|", paste(sprintf("%s=%s", tolower(comp_descricao), comp_valor), collapse = "|"), "|")), by = .(doc_id, seq_origem)] else data.table(doc_id = character(), seq_origem = integer(), comp_key = character())
  mv <- merge(mv, cp, by = c("doc_id", "seq_origem"), all.x = TRUE, sort = FALSE)
  mv[, `:=`(estado = NA_character_, papel = NA_character_, confianca = NA_character_, regra_id = NA_integer_)]
  for (i in seq_len(nrow(mapping))) {
    r <- mapping[i]
    cand <- is.na(mv$estado)
    if (!is.na(r$grau)) cand <- cand & !is.na(mv$grau) & mv$grau %in% strsplit(r$grau, ";")[[1]]
    if (!is.na(r$mov_codigo)) cand <- cand & !is.na(mv$mov_codigo) & mv$mov_codigo == r$mov_codigo
    if (!is.na(r$caminho_prefixo)) cand <- cand & !is.na(mv$tpu_caminho) & startsWith(mv$tpu_caminho, r$caminho_prefixo)
    if (!is.na(r$comp_descricao)) {
      key <- if (!is.na(r$comp_valor)) sprintf("|%s=%s|", tolower(r$comp_descricao), r$comp_valor) else sprintf("|%s=", tolower(r$comp_descricao))
      cand <- cand & !is.na(mv$comp_key) & grepl(key, mv$comp_key, fixed = TRUE)
    }
    if (any(cand)) mv[cand, `:=`(estado = r$estado, papel = r$papel, confianca = r$confianca, regra_id = i)]
  }
  setorder(mv, doc_id, seq_crono)
  mv[]
}

# Reconstrói episódios de estado por documento.
# Estado "corrente" muda quando aparece um movimento com papel == "entrada".
# Movimentos com papel "evidencia" só registram que o estado ocorreu (para
# auditoria de proporção de eventos inferidos) sem mover o processo.
# Terminais: "sentenca" (primeira ocorrência = evento principal), "baixa".
reconstruct_episodes <- function(mv_states, proc) {
  ms <- mv_states[!is.na(mov_datahora)]
  ep <- ms[papel %in% c("entrada", "terminal", "reabertura"),
           .(doc_id, quando = mov_datahora, estado, papel, confianca, mov_codigo)]
  setorder(ep, doc_id, quando)
  # colapsa repetições consecutivas do mesmo estado (ex.: várias conclusões seguidas)
  ep[, novo := estado != shift(estado, fill = "__inicio__"), by = doc_id]
  ep <- ep[novo == TRUE][, novo := NULL]
  ep[, episodio := seq_len(.N), by = doc_id]
  ep <- merge(ep, proc[, .(doc_id, data_ajuizamento, data_ultima_atualizacao)], by = "doc_id", all.x = TRUE)
  ep[, fim := shift(quando, type = "lead"), by = doc_id]
  ep[, censurado := is.na(fim)]
  ep[is.na(fim), fim := data_ultima_atualizacao]
  ep[, dias := as.numeric(difftime(fim, quando, units = "days"))]
  ep[, .(doc_id, episodio, estado, inicio = quando, fim, dias, censurado, mov_codigo_entrada = mov_codigo, confianca)]
}

# Resumo por documento: marcos temporais, duração até sentença/baixa, censura.
summarise_trajectory <- function(mv_states, proc) {
  ms <- mv_states[!is.na(mov_datahora)]
  first_of <- function(st) { z <- ms[!is.na(estado) & estado == st]; if (!nrow(z)) return(data.table(doc_id = character(), q = as.POSIXct(character(), tz = "UTC"))); z[, .(q = min(mov_datahora)), by = doc_id] }
  out <- proc[, .(doc_id, numero_processo, tribunal, grau, classe_codigo, oj_codigo, oj_municipio_ibge, cnj_ano,
                  data_ajuizamento, data_ultima_atualizacao, n_movimentos)]
  for (st in c(STATE_ORDER, "suspensao", "transito_julgado")) {
    f <- first_of(st); setnames(f, "q", paste0("t_", st))
    out <- merge(out, f, by = "doc_id", all.x = TRUE)
  }
  out[, t0 := fifelse(!is.na(t_distribuicao), t_distribuicao, data_ajuizamento)]
  out[, t0_fonte := fifelse(!is.na(t_distribuicao), "mov_26", "dataAjuizamento")]
  out[, evento_sentenca := !is.na(t_sentenca)]
  out[, dias_ate_sentenca := as.numeric(difftime(fifelse(evento_sentenca, t_sentenca, data_ultima_atualizacao), t0, units = "days"))]
  out[, evento_baixa := !is.na(t_baixa)]
  out[, dias_ate_baixa := as.numeric(difftime(fifelse(evento_baixa, t_baixa, data_ultima_atualizacao), t0, units = "days"))]
  out[, n_mov_sem_estado := ms[is.na(estado), .N, by = doc_id][match(out$doc_id, doc_id), N]]
  out[is.na(n_mov_sem_estado), n_mov_sem_estado := 0L]
  out[, prop_mov_sem_estado := n_mov_sem_estado / pmax(n_movimentos, 1)]
  out[, n_sentencas := ms[estado == "sentenca" & papel == "terminal", .N, by = doc_id][match(out$doc_id, doc_id), N]]
  out[is.na(n_sentencas), n_sentencas := 0L]
  out[, reaberto := doc_id %in% ms[papel == "reabertura", doc_id]]
  out[, suspenso := doc_id %in% ms[estado == "suspensao", doc_id]]
  out[, redistribuido := doc_id %in% ms[mov_codigo %in% c(36L, 12646L), doc_id]]
  msx <- merge(ms[, .(doc_id, mov_datahora)], out[, .(doc_id, t0, data_ultima_atualizacao)], by = "doc_id")
  out[, datas_impossiveis := msx[mov_datahora < t0 - 86400 | mov_datahora > data_ultima_atualizacao + 86400, .N, by = doc_id][match(out$doc_id, doc_id), N]]
  out[is.na(datas_impossiveis), datas_impossiveis := 0L]
  out[]
}

# Auditoria agregada da reconstrução (por tribunal × classe)
audit_trajectories <- function(traj, mv_states) {
  a <- traj[, .(
    n_docs = .N,
    p_com_distribuicao = mean(!is.na(t_distribuicao)),
    p_com_citacao      = mean(!is.na(t_citacao)),
    p_com_defesa       = mean(!is.na(t_defesa)),
    p_com_audiencia    = mean(!is.na(t_audiencia)),
    p_com_conclusao_j  = mean(!is.na(t_conclusao_julgamento)),
    p_com_sentenca     = mean(evento_sentenca),
    p_com_recurso      = mean(!is.na(t_recurso)),
    p_com_cumprimento  = mean(!is.na(t_cumprimento)),
    p_com_baixa        = mean(evento_baixa),
    p_multiplas_sentencas = mean(n_sentencas > 1),
    p_reaberto = mean(reaberto), p_suspenso = mean(suspenso), p_redistribuido = mean(redistribuido),
    p_docs_datas_impossiveis = mean(datas_impossiveis > 0),
    mediana_prop_mov_sem_estado = median(prop_mov_sem_estado),
    mediana_dias_sentenca_obs = median(dias_ate_sentenca[evento_sentenca]),
    mediana_dias_baixa_obs = median(dias_ate_baixa[evento_baixa])
  ), by = .(tribunal, classe_codigo)]
  a[]
}
