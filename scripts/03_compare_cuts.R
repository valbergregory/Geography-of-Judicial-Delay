#!/usr/bin/env Rscript
# 03_compare_cuts.R — compara os três recortes amostrais (A: PJe; B: eproc/Projudi; C: misto)
# a partir das tabelas da sondagem (Primeira Tarefa, item 6). Uso: Rscript scripts/03_compare_cuts.R
for (f in c("R/01_config.R", "R/02_utils.R")) source(f, encoding = "UTF-8")
pb <- file.path(PATHS$outputs, "probe")
cp <- fread(file.path(pb, "completude_por_tribunal_classe.csv")); hz <- fread(file.path(pb, "horizonte_observacao.csv"))
cv <- fread(file.path(pb, "cobertura_indice_por_tribunal_classe.csv"))
co <- fread(file.path(pb, "coortes_amostra_por_ano_cnj.csv"))[cnj_ano %in% 2018:2022, .(p_coortes_2018_22 = sum(N) / 500), by = .(tribunal, classe_codigo)]
x <- Reduce(function(a, b) merge(a, b, by = c("tribunal", "classe_codigo"), all = TRUE),
            list(cp[, .(tribunal, classe_codigo, p_ibge_ok, p_mov_sem_codigo, mediana_n_mov)],
                 hz[, .(tribunal, classe_codigo, mediana_ult_atual)],
                 cv[, .(tribunal, classe_codigo, total_indice, sistemas)], co))
x[, recorte := fcase(tribunal %in% c("TJCE", "TJPE"), "A (PJe)",
                     tribunal %in% c("TJGO", "TJPR", "TJSC"), "B (eproc/Projudi)",
                     tribunal %in% c("TJRS", "TJBA"), "C (misto)", default = "fora")]
x[, est_docs_2018_22 := round(total_indice * p_coortes_2018_22)]
setorder(x, recorte, tribunal, classe_codigo)
fwrite(x, file.path(pb, "recortes_ABC_comparacao.csv"))
print(x[, .(recorte, tribunal, classe_codigo, total_indice, est_docs_2018_22, p_ibge_ok, p_mov_sem_codigo, mediana_ult_atual, sistemas = substr(sistemas, 1, 36))])
res <- x[recorte != "fora", .(tribunais = uniqueN(tribunal), docs_2018_22 = sum(est_docs_2018_22, na.rm = TRUE), ibge_min = min(p_ibge_ok, na.rm = TRUE),
                              sem_cod_max = max(p_mov_sem_codigo, na.rm = TRUE), ult_atual_min = min(mediana_ult_atual, na.rm = TRUE)), by = recorte]
print(res); fwrite(res, file.path(pb, "recortes_ABC_resumo.csv"))
