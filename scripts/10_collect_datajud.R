#!/usr/bin/env Rscript
# 10_collect_datajud.R — coleta retomável do DataJud por (tribunal × classe) com dj_collect_class()
# (search_after, 1 req/s, páginas de 1 000, cache por página em data/raw/datajud/<trib>/, checkpoint por
# tribunal × classe, toda requisição em logs/datajud_requests.csv).
#
# ESTE SCRIPT NÃO RODA SEM AUTORIZAÇÃO REGISTRADA (docs/RUNBOOK.md, "Regras"): ele exige o argumento
# --authorized=<AAAA-MM-DD> com a data em que o pesquisador aprovou o recorte e o modo (piloto ou completo);
# sem isso, apenas imprime o plano (tribunais, classes, páginas estimadas) e sai.
#
# Uso:
#   Rscript scripts/10_collect_datajud.R --cut=A --pilot                     # só o plano
#   Rscript scripts/10_collect_datajud.R --cut=A --pilot --authorized=2026-09-15   # piloto: 5 páginas (≈5 000 docs) por tribunal × classe
#   Rscript scripts/10_collect_datajud.R --cut=A --authorized=2026-09-15           # coleta completa do recorte
#   Rscript scripts/10_collect_datajud.R --tribunais=tjce,tjpe --classes=7 --pilot --authorized=...
# Recortes (docs/01_feasibility_report.md §7): A = TJCE+TJPE; B = TJGO+TJPR+TJSC; C = TJRS+TJBA. Classes: 7 e 436.
# Interromper (Ctrl+C / fechar o job) e relançar é seguro: cada (tribunal, classe) retoma do checkpoint.
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default = NULL) { v <- args[startsWith(args, paste0("--", name, "="))]; if (length(v)) sub("^--[^=]+=", "", v[1]) else default }
for (f in c("R/01_config.R", "R/02_utils.R", "R/03_datajud_client.R")) source(f, encoding = "UTF-8")

CUTS <- list(A = c("tjce", "tjpe"), B = c("tjgo", "tjpr", "tjsc"), C = c("tjrs", "tjba"))
cut <- opt("cut", "A"); pilot <- "--pilot" %in% args; authorized <- opt("authorized", NA)
tribunais <- if (!is.null(opt("tribunais"))) strsplit(opt("tribunais"), ",")[[1]] else CUTS[[cut]]
classes <- as.integer(strsplit(opt("classes", "7,436"), ",")[[1]])
pilot_pages <- as.integer(opt("pilot-pages", "5"))   # 5 páginas × 1 000 = 5 000 docs por tribunal × classe (critérios §7)
stopifnot(length(tribunais) > 0, all(classes > 0))

gjd_log(sprintf("recorte %s | tribunais: %s | classes: %s | modo: %s", cut, paste(tribunais, collapse = ","), paste(classes, collapse = ","),
                if (pilot) sprintf("PILOTO (%d páginas de %d)", pilot_pages, DATAJUD$page_size) else "COMPLETO"))
# ---- plano (sem coleta): totais por tribunal × classe via agregação size=0 (1 requisição cada) -------------------
plan <- data.table::rbindlist(lapply(tribunais, function(tb) data.table::rbindlist(lapply(classes, function(cl) {
  js <- tryCatch(dj_aggregate(tb, dj_query_classe(cl), aggs = list(cls = list(terms = list(field = "classe.codigo", size = 1)))),
                 error = function(e) NULL)
  total <- if (is.null(js)) NA_integer_ else js$hits$total$value
  ck <- file.path(PATHS$raw_datajud, tb, sprintf("checkpoint_%s.json", cl))
  done <- if (file.exists(ck)) jsonlite::fromJSON(ck)$collected else 0L
  data.table::data.table(tribunal = tb, classe = cl, total_api = total, paginas = ceiling(total / DATAJUD$page_size),
                         paginas_alvo = if (pilot) pmin(pilot_pages, ceiling(total / DATAJUD$page_size)) else ceiling(total / DATAJUD$page_size),
                         ja_coletados = done)
}))))
print(plan)
dir.create(file.path(PATHS$outputs, "collect"), showWarnings = FALSE, recursive = TRUE)
data.table::fwrite(plan, file.path(PATHS$outputs, "collect", sprintf("plano_recorte_%s_%s.csv", cut, if (pilot) "piloto" else "completo")))
gjd_log(sprintf("plano: %d páginas-alvo (~%.1f h a 30 s/página, 1 req/s)", sum(plan$paginas_alvo, na.rm = TRUE), sum(plan$paginas_alvo, na.rm = TRUE) * 30 / 3600))

if (is.na(authorized)) {
  gjd_log("SEM --authorized=<data>: nada foi coletado. Registre a autorização do pesquisador (docs/RUNBOOK.md) e relance.")
  quit(status = 0)
}
gjd_log(sprintf("coleta autorizada em %s — iniciando", authorized))
writeLines(sprintf("%s | autorizado em %s | recorte %s | %s | tribunais %s | classes %s", format(Sys.time()), authorized, cut,
                   if (pilot) "piloto" else "completo", paste(tribunais, collapse = ","), paste(classes, collapse = ",")),
           file.path(PATHS$logs, "collect_authorizations.log"))
# ---- coleta ---------------------------------------------------------------------------------------------------------
res <- lapply(seq_len(nrow(plan)), function(i) {
  tb <- plan$tribunal[i]; cl <- plan$classe[i]
  r <- tryCatch(dj_collect_class(tb, cl, max_pages = if (pilot) pilot_pages else Inf),
                error = function(e) { gjd_log("ERRO em ", tb, " classe ", cl, ": ", conditionMessage(e)); NULL })
  data.table::data.table(tribunal = tb, classe = cl, paginas = r$pages %||% NA, coletados = r$collected %||% NA)
})
res <- data.table::rbindlist(res); print(res)
data.table::fwrite(res, file.path(PATHS$outputs, "collect", sprintf("resultado_recorte_%s_%s_%s.csv", cut, if (pilot) "piloto" else "completo", format(Sys.Date()))))
gjd_log("fim; próximo passo: scripts/11_load_duckdb.R (parse das páginas em cache → DuckDB) e auditorias dos critérios §7")
