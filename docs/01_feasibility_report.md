# Relatório de viabilidade — Primeira Tarefa (versão preliminar, 2026-09-07)

Estado: **sondagem concluída; relatório em rascunho**. Itens 1–4 da Primeira Tarefa estão
executados e reproduzíveis; itens 5–9 (classes viáveis, três recortes, riscos, critérios
de continuidade, arquitetura/plano) estão esboçados na seção 7 e serão fechados na próxima
sessão. **Nenhuma coleta ampla foi iniciada.**

## 1. Fontes verificadas (acesso em 2026-09-04/05)

| Fonte | Como | Resultado |
|---|---|---|
| DataJud API Pública | `POST https://api-publica.datajud.cnj.jus.br/api_publica_{trib}/_search`, `Authorization: APIKey …` | OK. Query DSL do Elasticsearch; `size` 10–10 000; paginação por `sort [@timestamp asc]` + `search_after` (validada ao vivo: 2 páginas × 20 docs no TJCE, 0 duplicatas); agregações só em campos numéricos e `*.keyword`; `_mapping` proibido (403). Latência 1–80 s por chamada; TJPR/TJSP as mais lentas; 1 HTTP 504 em 24 amostras. |
| TPU (SGT) | Web service SOAP `https://www.cnj.jus.br/sgt/sgt_ws.php` (`getDataUltimaVersao`, `getArrayFilhosItemPublicoWS`, `getComplementoMovimentoWS`) | OK. **Versão 26/05/2026.** Árvores completas: 964 movimentos, 849 classes; complementos de 14 movimentos-chave. Arquivos em `data/reference/tpu/`. As páginas HTML do SGT bloqueiam fetch automatizado (403), o WS não. |
| Justiça em Números | `cnj.jus.br/pesquisas-judiciarias/justica-em-numeros/base-de-dados/` | OK. Bases zip por edição (`23-jun-2026.zip`, `dea-jn2026.zip`, `15-jan-2026.zip`, `basejn-03-jun-2024.zip`…). Granularidade por **tribunal**; por **unidade** só via Módulo de Produtividade Mensal (`/pesquisas-judiciarias/modulo-de-produtividade-mensal/`) — a verificar formato. |
| Painéis CNJ | `paineis-cnj/` | Painel Estatística DataJud (`/datajud/painel-estatistica`), Censo 2023 magistrados/servidores. Qlik sem download direto; usar bases zip. |
| IBGE | SIDRA API (`apisidra.ibge.gov.br`), Malhas API v3 | OK (teste: população municipal AL 2022; malha de municípios de AL). `sidrar` e `geobr` em R. |
| Anatel | dados.gov.br: "Acessos – Banda Larga Fixa" (+ densidade por 100 hab., velocidade média, cobertura móvel) | Conjuntos localizados; download e chave município a testar. |

## 2. Decisão de pilha: R + SQL, sem Python

Evidência: a API é Elasticsearch simples (httr2 basta; cliente resiliente com retry,
cache, checkpoint e log já escrito e testado); todos os métodos pedidos têm implementação
madura em R (`survival`, `mstate`, `cmprsk`, `frailtypack`/`coxme`, `fixest`, `lme4`,
`sf`/`spdep`/`spatialreg`, `ranger`/`randomForestSRC`/`xgboost`, `did`/`gsynth`, `targets`,
Quarto). Python só entraria para conformal survival (há implementação em R via `mlr3proba`
+ código próprio). Um único pesquisador não deve manter duas cadeias de dependências.
Decisão coincide com a de 04/09 (portfólio: artigo 2 = R-only). Python foi usado apenas
como rascunho descartável na sondagem; nada dele entra no repositório.

## 3. Esquema real do documento (confirmado)

Campos de processo: `id, numeroProcesso, tribunal, grau (G1/G2/JE/TR), classe{codigo,nome},
assuntos[{codigo,nome}] (às vezes aninhado), sistema{nome}, formato{nome}, nivelSigilo,
orgaoJulgador{codigo,nome,codigoMunicipioIBGE}, dataAjuizamento, dataHoraUltimaAtualizacao,
@timestamp, movimentos[]`. Movimento: `codigo, nome, dataHora, complementosTabelados[{codigo,
descricao,valor,nome}], orgaoJulgador{codigo,nome}` (este último só em PJe/eproc).

Achados críticos:
- `dataAjuizamento` vem em **três formatos** no mesmo índice: ISO, `yyyyMMddHHmmss` e epoch
  em ms (TJMG). `range`/`date_histogram` no servidor dão resultados errados → o **ano de
  coorte é o do número CNJ** e as datas são normalizadas no cliente (`parse_datajud_datetime`).
- `codigoMunicipioIBGE` ausente em 85 % dos docs do TJSP e 65–80 % do TJAL; 0 em 3–6 % do TJCE.
- Movimentos **sem código** (`codigo: null`, nome vazio): 2,6 % (classe 7) e 13,8 % (classe 436) no TJAL; ≈0 nos demais.
- Movimentos **sem data**: raros (≤0,2 %), exceto um subconjunto do TJMG 2019 (amostra nomeada: 100 % sem data).
- Movimentos **fora de ordem** cronológica na lista enviada (PJe/SAJ): reordenação obrigatória.
- Documentos G1 e G2 do mesmo feito são **documentos distintos** (`TJXX_G1_…` / `TJXX_G2_…`), ligados por `numeroProcesso`.
- Sem PIT: coleta é eventualmente consistente; dedupe por `id` e re-varredura incremental por `dataHoraUltimaAtualizacao`.

## 4. Cobertura e completude (12 TJs, classes 7 e 436)

Tabelas: `outputs/probe/cobertura_indice_por_tribunal_classe.csv` (totais do índice, graus,
sistemas, docs sem movimento, IBGE), `completude_por_tribunal_classe.csv` (amostra
aleatória de 500 docs/classe), `coortes_amostra_por_ano_cnj.csv`, `horizonte_observacao.csv`.

Resumo: totais de 60 mil (TJDFT) a 6,5 milhões (TJSP) por classe; coortes 2018–2023 têm
15–80 docs por 500 na amostra (≈3–16 % do índice cada); mediana de 30–70 movimentos por
processo; `dataHoraUltimaAtualizacao` mediana entre 2024-07 (TJMG 436) e 2026-08 (TJDFT) —
a censura administrativa varia por tribunal e deve entrar como covariável de auditoria.

## 5. Dicionário TPU → estados e reconstrução (80 trajetórias reais)

`config/state_mapping.csv` (66 regras; precedência = ordem; `papel` ∈ entrada/evidência/
terminal/reabertura; `confianca` alta/média/baixa). Estados: os 12 do projeto + `suspensao`,
`secretaria` (residual: tempo de cartório) e `transito_julgado` (marco). Regras por subárvore
da TPU (`caminho_prefixo`) tornam o dicionário robusto a códigos novos.

Resultados em `outputs/probe/auditoria_trajetorias.csv` (por tribunal × classe, n = 10 cada):
- **Sentença** identificada (subárvore *Magistrado > Julgamento*, G1/JE): 90–100 % em TJSP e
  TJCE-436; 20 % em TJCE-7 (coorte 2019 ainda aberta); 0 % em TJAL-7 (docs de 2º grau/TR
  registrados com classe 7) e TJMG (sem datas).
- **Citação**: 70–100 % (alta confiança só em PJe/eproc via subárvore *Citação*; em SAJ é
  inferida de *Carta/Mandado + AR*, confiança média).
- **Defesa (contestação)**: 40 % no TJCE (PJe tipa a petição); **0 % em SAJ** (TJSP/TJAL:
  toda petição é "Petição (outras)") → a etapa "defesa" só é mensurável em tribunais PJe/eproc.
- **Conclusão para julgamento** (51/36): 40–80 %; **recurso**: 10–60 %; **cumprimento**: 0–20 %; **baixa**: 10–100 %.
- Não mapeados (por desenho): juntadas genéricas (581, 85 "outras"), remessas do distribuidor (982), cancelamentos (12291).
- Matriz de transições em `matriz_transicoes.csv`; episódios e durações em `episodios.csv`; trajetórias cruas legíveis em `trajetorias_60.txt`.

## 6. Riscos de cobertura e identificação (preliminar)

1. Heterogeneidade de sistema (SAJ × PJe × eproc × Projudi) confunde tribunal com qualidade de registro → estratificar/fixar sistema; medir "defesa" só onde tipada.
2. Ausência de município da unidade (TJSP, TJAL) → precisa de cadastro externo de unidades (foro do número CNJ `cnj_origem` + tabela de comarcas) ou exclusão desses tribunais da análise espacial.
3. Censura administrativa desigual (`dataHoraUltimaAtualizacao`) → risco de viés de coorte; tratar como censura, não como sobrevivência.
4. Docs de 2º grau com classe 7 (TJAL) e "Inválido" em `sistema` → filtros por grau e auditoria de reclassificação.
5. Datas impossíveis/epoch (TJMG) → auditoria específica antes de incluir o TJMG.
6. Sem PIT na API → coleta longa pode perder/duplicar docs; mitigar com dedupe e re-varredura incremental.
7. Causalidade: nenhuma política datada foi ainda escolhida; candidatas: Juízo 100 % Digital (movimento 14736 observado no TJCE), Núcleos de Justiça 4.0, migração SAJ→PJe/eproc por comarca (motivo de remessa 380).

## 7. Próximos passos (a fechar na próxima sessão)

- Propor as classes viáveis (7 e 436 confirmadas como mensuráveis) e os **três recortes**:
  (A) TJCE + TJPE, PJe, classes 7 e 436, coortes 2019–2022; (B) TJGO + TJPR + TJSC, eproc/Projudi;
  (C) TJRS/TJBA como contraste de sistema. Comparar por completude de citação/defesa/sentença, IBGE e horizonte.
- Critérios de continuidade (propostos): ≥90 % docs com IBGE, ≥85 % com sentença ou baixa nas coortes ≤2021, ≤2 % movimentos sem código, defesa tipada ≥30 %, ≤5 % datas impossíveis, e ≥1 política datada com grupo de controle defensável.
- Arquitetura/plano: `targets` + DuckDB (→ PostGIS quando >5 M movimentos), runbook, export Overleaf, renv.lock — conforme diretriz transversal de 05/09 (`docs/AI_POLICY_AND_REPRODUCIBILITY.md`).
- Testar download e chave municipal do Módulo de Produtividade Mensal e da Anatel.
