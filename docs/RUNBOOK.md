# RUNBOOK — ordem de execução (RStudio ou terminal)

Pré-requisitos: R 4.4.3; `DATAJUD_API_KEY` no `.Renviron` (chave pública do CNJ, ver README);
Rscript em `C:\Program Files\R\R-4.4.3\bin\Rscript.exe`. No RStudio, abra a pasta como projeto
e use *Background Jobs* para os passos marcados com ⏳.

| # | Comando | Lê | Grava | Duração |
|---|---|---|---|---|
| 0 | `Rscript R/00_setup.R` (`--full` para fases 2+) | — | pacotes; `logs/sessionInfo_setup.txt` | 2–20 min |
| 1 | `Rscript scripts/01_probe_datajud.R [--live]` | `data/raw/datajud_probe/**` (hash conferido) | `outputs/probe/schema_por_tribunal.csv`, `completude_*.csv`, `cobertura_*.csv`, `coortes_*.csv`, `horizonte_observacao.csv`; com `--live`, 2 páginas reais em `data/raw/datajud_probe/live_test/` e `logs/datajud_requests.csv` | 1,5 min (+10 s live) |
| 2 | `Rscript scripts/02_reconstruct_sample.R` | amostras nomeadas; `config/state_mapping.csv`; `data/reference/tpu/*.csv` | `outputs/probe/movimentos_com_estado.csv`, `episodios.csv`, `trajetorias_resumo.csv`, `auditoria_trajetorias.csv`, `movimentos_nao_mapeados.csv`, `matriz_transicoes.csv`; `data/processed/gjd.duckdb` | 20 s |
| T | `Rscript -e "testthat::test_dir('tests/testthat')"` | — | — | 10 s |
| 90 | `Rscript scripts/90_export_overleaf.R` | `outputs/probe/*.csv` | `outputs/overleaf/tables/*.tex`, `numbers.tex` | 5 s |

Passos futuros (fase 2, após aprovação dos critérios de continuidade — ver relatório §7):

| # | Script (a criar) | Função |
|---|---|---|
| 10 ⏳ | `scripts/10_collect_datajud.R` | varredura completa por (tribunal, classe) com `dj_collect_class()`: retomável por checkpoint, 1 req/s, páginas de 1000, cache em `data/raw/datajud/<trib>/` |
| 11 | `scripts/11_load_duckdb.R` | parse de todas as páginas → tabelas `processos/movimentos/complementos/assuntos` |
| 12 | `scripts/12_reference_tables.R` | unidades (CNJ/tribunais), municípios (IBGE), indicadores (SIDRA, Anatel, JN) |
| 20 ⏳ | `scripts/20_reconstruct_all.R` | estados/transições para toda a base + auditorias obrigatórias |
| 30–39 | sobrevivência, multiestado, competing risks, frailty, hierárquico | RQ1–RQ2 |
| 40–49 | Moran/LISA, modelos espaciais, mapas | RQ3–RQ5 |
| 50–59 | RSF/GBM, calibração temporal, conformal | RQ6 |
| 60–69 | estudo de evento / DiD / synthetic control | RQ7 |
| 90 | export Overleaf | tabelas, figuras e `numbers.tex` |

Regras: nunca rodar o passo 10 sem autorização registrada; interromper e retomar é seguro
(checkpoint por tribunal × classe); toda requisição fica em `logs/datajud_requests.csv`.
