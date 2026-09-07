# The Geography of Judicial Delay: Spatial Inequality and Procedural Trajectories in Brazil

Reproducible research project (jurimetrics × spatial econometrics × information systems)
on whether comparable civil cases have different durations and procedural trajectories
depending on court, judicial unit and territory in Brazil. Data: CNJ DataJud public API
(case metadata and procedural movements), Justiça em Números, IBGE and Anatel.

**Stack: R + SQL only** (httr2, data.table, DuckDB → PostgreSQL/PostGIS, survival/mstate,
fixest, sf/spdep, ranger/xgboost, targets, Quarto). See `docs/01_feasibility_report.md` §2
for why Python was dropped.

## Status (2026-09-05)
Phase 1 — feasibility probe — completed:
- DataJud schema confirmed against the live API for 12 state courts (`outputs/probe/schema_por_tribunal.csv`);
- coverage, completeness and observation horizon measured on random samples (`outputs/probe/*.csv`);
- TPU (Tabela Processual Unificada) movement/class trees downloaded from the SGT web service, version 26/05/2026;
- transparent movement→state dictionary (`config/state_mapping.csv`) and trajectory reconstruction
  validated on 80 real cases (`outputs/probe/trajetorias_resumo.csv`, `episodios.csv`, `auditoria_trajetorias.csv`).

Large-scale collection has **not** started; it is gated by the continuation criteria in the report (§7). Step-by-step execution: `docs/RUNBOOK.md`.

## Reproduce the probe
```bash
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" R/00_setup.R
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" scripts/01_probe_datajud.R          # add --live for a short real API call
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" scripts/02_reconstruct_sample.R
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" scripts/03_compare_cuts.R          # sample cuts A/B/C
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" scripts/90_export_overleaf.R       # booktabs tables + numbers.tex
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" -e "testthat::test_dir('tests/testthat')"
```
Raw probe files are hash-listed in `data/raw/datajud_probe/SHA256SUMS.txt`.
The DataJud key is **never stored in the repository**: copy the public key from
https://datajud-wiki.cnj.jus.br/api-publica/acesso/ into `~/.Renviron` as
`DATAJUD_API_KEY=...` (or `.Renviron` in the project root, which is git-ignored).

## Layout
`R/` functions · `scripts/` numbered entry points · `sql/` DuckDB schema · `config/` scope and
state dictionary · `data/` raw/reference/processed · `outputs/` tables and figures ·
`docs/` feasibility report, runbook, data catalog, AI/reproducibility policy · `tests/` testthat · `article/` LaTeX skeleton (prose written by the author in Overleaf; tables/numbers generated) · `app/` dashboard (planned).

## Data sources (verified access dates in `docs/data_catalog.md`)
- DataJud public API — https://datajud-wiki.cnj.jus.br/api-publica/
- TPU / SGT web service — https://www.cnj.jus.br/sgt/sgt_ws.php?wsdl
- Justiça em Números data bases — https://www.cnj.jus.br/pesquisas-judiciarias/justica-em-numeros/base-de-dados/
- IBGE SIDRA API, malhas (API v3), geobr — https://apisidra.ibge.gov.br
- Anatel open data (fixed broadband accesses by municipality) — https://dados.gov.br/dados/conjuntos-dados/acessos---banda-larga-fixa

## License and ethics
Public metadata only (DataJud public API respects secrecy levels; no party data is collected).
Code: MIT. Cite the CNJ as data source (Portaria CNJ 160/2020).
