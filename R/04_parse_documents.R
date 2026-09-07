# 04_parse_documents.R — achata os documentos do DataJud em tabelas normalizadas
# processos (1 linha por documento = processo × grau), movimentos (1 linha por
# movimento, complementos serializados e também expandidos), assuntos.

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.nz <- function(x, def = NA) if (is.null(x) || length(x) == 0) def else x

# recebe a lista `hits` (js$hits$hits) e devolve list(processos, movimentos, assuntos, complementos)
dj_parse_hits <- function(hits, fonte = NA_character_) {
  if (length(hits) == 0) return(NULL)
  proc <- rbindlist(lapply(hits, function(h) {
    s <- h[["_source"]]
    oj <- s$orgaoJulgador
    data.table(
      doc_id            = .nz(h[["_id"]], .nz(s$id)),
      indice            = .nz(h[["_index"]], NA_character_),
      numero_processo   = .nz(s$numeroProcesso, NA_character_),
      tribunal          = .nz(s$tribunal, NA_character_),
      grau              = .nz(s$grau, NA_character_),
      classe_codigo     = as.integer(.nz(s$classe$codigo)),
      classe_nome       = .nz(s$classe$nome, NA_character_),
      sistema_nome      = .nz(s$sistema$nome, NA_character_),
      formato_nome      = .nz(s$formato$nome, NA_character_),
      nivel_sigilo      = as.integer(.nz(s$nivelSigilo)),
      oj_codigo         = as.integer(.nz(oj$codigo)),
      oj_nome           = .nz(oj$nome, NA_character_),
      oj_municipio_ibge = as.integer(.nz(oj$codigoMunicipioIBGE)),
      data_ajuizamento_raw = as.character(.nz(s$dataAjuizamento)),
      data_ultima_atualizacao = parse_datajud_datetime(.nz(s$dataHoraUltimaAtualizacao)),
      timestamp_indice  = parse_datajud_datetime(.nz(s[["@timestamp"]])),
      n_movimentos      = length(s$movimentos),
      n_assuntos        = length(unlist(lapply(s$assuntos, function(a) if (is.list(a) && is.null(a$codigo)) a else list(a)), recursive = FALSE)),
      fonte             = fonte
    )
  }), fill = TRUE)
  proc[is.na(tribunal) & !is.na(indice), tribunal := toupper(sub("^api_publica_", "", indice))]
  proc[, data_ajuizamento_fmt := datajud_date_format(data_ajuizamento_raw)]
  proc[, data_ajuizamento := parse_datajud_datetime(data_ajuizamento_raw)]
  proc <- cbind(proc, parse_cnj(proc$numero_processo)[, .(cnj_valido, cnj_ano, cnj_segmento, cnj_tribunal, cnj_origem)])

  mov <- rbindlist(lapply(hits, function(h) {
    s <- h[["_source"]]; mv <- s$movimentos
    if (length(mv) == 0) return(NULL)
    rbindlist(lapply(seq_along(mv), function(i) {
      m <- mv[[i]]; comps <- m$complementosTabelados
      data.table(
        doc_id     = .nz(h[["_id"]], .nz(s$id)),
        seq_origem = i,                                  # ordem em que o tribunal enviou (nem sempre cronológica)
        mov_codigo = as.integer(.nz(m$codigo)),
        mov_nome   = .nz(m$nome, NA_character_),
        mov_datahora_raw = as.character(.nz(m$dataHora)),
        mov_oj_codigo = as.integer(.nz(m$orgaoJulgador$codigo)),
        n_complementos = length(comps),
        complementos_json = if (length(comps)) as.character(jsonlite::toJSON(comps, auto_unbox = TRUE)) else NA_character_
      )
    }))
  }), fill = TRUE)
  if (nrow(mov)) {
    mov[, mov_datahora := parse_datajud_datetime(mov_datahora_raw)]
    setorder(mov, doc_id, mov_datahora, seq_origem, na.last = TRUE)
    mov[, seq_crono := seq_len(.N), by = doc_id]
  }

  comp <- rbindlist(lapply(hits, function(h) {
    s <- h[["_source"]]; mv <- s$movimentos
    if (length(mv) == 0) return(NULL)
    rbindlist(lapply(seq_along(mv), function(i) {
      cs <- mv[[i]]$complementosTabelados; if (length(cs) == 0) return(NULL)
      rbindlist(lapply(cs, function(cc) data.table(
        doc_id = .nz(h[["_id"]], .nz(s$id)), seq_origem = i,
        comp_codigo = as.integer(.nz(cc$codigo)), comp_descricao = .nz(cc$descricao, NA_character_),
        comp_valor = as.integer(.nz(cc$valor)), comp_nome = .nz(cc$nome, NA_character_))))
    }))
  }), fill = TRUE)

  ass <- rbindlist(lapply(hits, function(h) {
    s <- h[["_source"]]; a <- s$assuntos; if (length(a) == 0) return(NULL)
    flat <- list(); walk <- function(x) { if (is.list(x) && !is.null(x$codigo)) flat[[length(flat) + 1]] <<- x else if (is.list(x)) lapply(x, walk) }
    walk(a)
    if (!length(flat)) return(NULL)
    data.table(doc_id = .nz(h[["_id"]], .nz(s$id)), assunto_codigo = vapply(flat, function(z) as.integer(.nz(z$codigo)), 1L),
               assunto_nome = vapply(flat, function(z) as.character(.nz(z$nome)), ""), ordem = seq_along(flat))
  }), fill = TRUE)

  list(processos = proc, movimentos = mov, complementos = comp, assuntos = ass)
}

# lê um arquivo JSON de resposta (_search) do cache e parseia
dj_parse_file <- function(path) {
  js <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  dj_parse_hits(js$hits$hits, fonte = basename(path))
}
