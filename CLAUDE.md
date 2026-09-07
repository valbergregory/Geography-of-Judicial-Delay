# The Geography of Judicial Delay — instruções para o Claude Code

Artigo científico (jurimetria + econometria espacial + SI), escrito em inglês, sobre
desigualdade espacial e trajetórias processuais no Brasil, com dados reais do DataJud.
Pesquisador único: Valber (doutor em Economia, formação em Direito, professor de SI).

## Decisões fixas
- **Pilha: R + SQL (DuckDB → PostgreSQL/PostGIS), sem Python.** Decisão de 2026-09-04/05,
  justificada em `docs/01_feasibility_report.md` §2. Não criar `pyproject.toml`, `python/`
  nem depender de scikit-survival. Se um método exigir Python, discutir antes.
- Só dados reais. Nunca simular processos nem inventar campos. Campos aceitos são os
  confirmados na sondagem (`outputs/probe/schema_por_tribunal.csv`).
- Versão da TPU registrada: **26/05/2026** (SGT `getDataUltimaVersao`, consultado em 2026-09-04),
  arquivos em `data/reference/tpu/`. Toda mudança de dicionário passa por `config/state_mapping.csv`.
- Movimento ambíguo não é forçado a um estado: fica `NA` e entra na auditoria.
- Censura à direita = `dataHoraUltimaAtualizacao` do documento, nunca "hoje".
- Ano de coorte = ano do número CNJ (`cnj_ano`), não `dataAjuizamento` (formatos heterogêneos).
- Não sobrecarregar a API: 1 requisição por vez, `min_sleep` ≥ 1 s, páginas ≤ 1000, cache em
  disco, checkpoint por (tribunal, classe), log em `logs/datajud_requests.csv`.
- Idioma: código e documentos internos em português; artigo (`article/`) em inglês.

## Layout
```
R/            00_setup, 01_config, 02_utils, 03_datajud_client, 04_parse_documents, 05_state_mapping, ...
scripts/      01_probe_datajud.R, 02_reconstruct_sample.R, ... (numerados; Rscript scripts/NN_*.R)
sql/          01_schema.sql (DuckDB; portável para PostGIS)
config/       tribunais.yml, state_mapping.csv
data/raw/     datajud_probe/ (amostras da sondagem + SHA256SUMS.txt); datajud/ (coleta, ignorado no git)
data/reference/tpu/   árvores de movimentos, classes e complementos (SGT, versão 26/05/2026)
data/processed/gjd.duckdb
outputs/probe/        tabelas da sondagem e da reconstrução
docs/         01_feasibility_report.md, data_catalog.md
tests/testthat/       testthat (Rscript -e 'testthat::test_dir("tests/testthat")')
article/      Quarto (inglês)   app/  painel Shiny
```

## Como rodar
```bash
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" R/00_setup.R
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" scripts/01_probe_datajud.R --live
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" scripts/02_reconstruct_sample.R
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" -e "testthat::test_dir('tests/testthat')"
```
Rscript não está no PATH; usar o caminho completo acima. Coletas longas rodam como
Background Job no RStudio (`rstudioapi::jobRunScript`) ou `Rscript ... &` no terminal.

## Diretriz transversal de reprodutibilidade e IA (Valber, 05/09/2026)
Fonte: `docs/AI_POLICY_AND_REPRODUCIBILITY.md` e `docs/latex_snippets/` (copiados de `_shared-jurimetrics/`; não sobrescrever).
1. Claude Code escreve código, testes, SQL, config, docs técnicos e runbook; **nunca prosa do artigo**.
   `article/` terá só o esqueleto LaTeX (`main.tex` com `\input`, cabeçalhos, marcações `% AUTHOR WRITES`,
   os snippets `ai_disclosure.tex` e `data_code_availability.tex`, `references.bib`). O texto é escrito no Overleaf.
2. `docs/RUNBOOK.md` numerado na ordem de execução (o que cada passo lê, grava e quanto demora), executável no RStudio.
3. Script de exportação `scripts/90_export_overleaf.R` → `outputs/overleaf/{tables/*.tex (booktabs), figures/*.pdf+png, numbers.tex}`
   com `\newcommand` para cada número citado.
4. `renv.lock` + `sessionInfo` em `logs/`; manifesto de downloads do DataJud (URL, corpo da consulta, data, SHA-256 —
   `data/raw/**/SHA256SUMS.txt` + `logs/datajud_requests.csv`); seeds fixas; testes com fixtures pequenas; `CITATION.cff`;
   `LICENSE` (MIT código / CC-BY texto); `.gitignore` sem dados nem segredos; release + Zenodo antes da submissão.
5. R-only (decisão de 04/09).
6. **Chave do DataJud só por variável de ambiente** `DATAJUD_API_KEY` (`.Renviron`, fora do git). O README diz onde obtê-la
   (wiki pública do CNJ). Nenhuma credencial no repositório.
7. Nenhum dado pessoal (partes, advogados, juízes) em outputs, logs ou commits; magistrados só em nível de órgão.
Divergência registrada: o CLAUDE.md já existia quando a diretriz chegou (07/09); foi incorporado, não recriado.

## Estado do projeto
Ver `docs/01_feasibility_report.md` (fase 1: sondagem concluída; coleta ampla ainda NÃO
autorizada — depende dos critérios de continuidade da seção 8).
