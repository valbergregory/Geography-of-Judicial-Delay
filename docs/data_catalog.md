# Catálogo de fontes (data card resumido)

| Fonte | URL | Acesso verificado | Granularidade | Chave de junção | Licença/uso | Observações |
|---|---|---|---|---|---|---|
| DataJud — API Pública | https://api-publica.datajud.cnj.jus.br/api_publica_{trib}/_search | 2026-09-04/05/07 (12 TJs; live test 07/09) | processo × grau; movimentos | `numeroProcesso` (liga graus), `orgaoJulgador.codigo`, `codigoMunicipioIBGE` | Portaria CNJ 160/2020; metadados públicos, sem partes | 3 formatos de data; sem PIT; `_mapping` proibido; latência 1–80 s |
| TPU (SGT) — movimentos, classes, complementos | https://www.cnj.jus.br/sgt/sgt_ws.php (SOAP) | 2026-09-04 (versão 26/05/2026) | item da tabela | `codigo` | pública | HTML do SGT bloqueia bots (403); usar WS |
| Justiça em Números — bases | https://www.cnj.jus.br/pesquisas-judiciarias/justica-em-numeros/base-de-dados/ | 2026-09-04 (links de zip localizados) | tribunal × ano | sigla do tribunal | pública | por unidade só no Módulo de Produtividade Mensal (a testar) |
| Módulo de Produtividade Mensal | https://www.cnj.jus.br/pesquisas-judiciarias/modulo-de-produtividade-mensal/ | a testar | unidade × mês | código da serventia (conferir = `orgaoJulgador.codigo`) | pública | — |
| IBGE SIDRA | https://apisidra.ibge.gov.br | 2026-09-04 (t/4714 pop. 2022) | município × ano | código IBGE 7 dígitos | pública | tabelas: 4714 (Censo 2022), 6579 (estimativas), 5938 (PIB municipal) |
| IBGE malhas | https://servicodados.ibge.gov.br/api/v3/malhas/ | 2026-09-04 (UF 27) | município | código IBGE | pública | alternativa: `geobr` |
| Anatel dados abertos | https://dados.gov.br/dados/conjuntos-dados/acessos---banda-larga-fixa | localizado 2026-09-04 | município × mês | código IBGE | pública | densidade por 100 hab. em conjunto separado |

Integridade: `data/raw/datajud_probe/SHA256SUMS.txt` (55 arquivos) e `logs/datajud_requests.csv`.
