library(testthat)
root <- rprojroot::find_root(rprojroot::has_file("CLAUDE.md"))
for (f in c("R/01_config.R", "R/02_utils.R", "R/04_parse_documents.R", "R/05_state_mapping.R")) source(file.path(root, f), encoding = "UTF-8")

test_that("mapeamento carrega e cobre os 12 estados + suspensao", {
  m <- load_state_mapping()
  expect_true(all(c(STATE_ORDER, "suspensao") %in% m$estado))
  expect_true(all(m$papel %in% c("entrada", "evidencia", "terminal", "reabertura")))
  expect_true(all(m$confianca %in% c("alta", "media", "baixa")))
})

test_that("reconstrução em trajetória sintética: distribuição -> citação -> sentença -> baixa", {
  proc <- data.table(doc_id = "X", numero_processo = "10099012120198260224", tribunal = "TJX", grau = "G1", classe_codigo = 7L,
                     oj_codigo = 1L, oj_municipio_ibge = 1L, cnj_ano = 2019L, n_movimentos = 4L,
                     data_ajuizamento = as.POSIXct("2019-01-01", tz = "UTC"), data_ultima_atualizacao = as.POSIXct("2021-01-01", tz = "UTC"))
  mov <- data.table(doc_id = "X", seq_origem = 1:4, seq_crono = 1:4, mov_codigo = c(26L, 12288L, 219L, 22L),
                    mov_datahora = as.POSIXct(c("2019-01-01", "2019-02-01", "2019-12-01", "2020-06-01"), tz = "UTC"))
  comp <- data.table(doc_id = character(), seq_origem = integer(), comp_descricao = character(), comp_valor = integer())
  mvs <- assign_states(mov, comp, proc)
  expect_equal(mvs$estado, c("distribuicao", "citacao", "sentenca", "baixa"))
  tr <- summarise_trajectory(mvs, proc)
  expect_true(tr$evento_sentenca); expect_equal(round(tr$dias_ate_sentenca), 334)
  expect_equal(tr$t0_fonte, "mov_26")
  ep <- reconstruct_episodes(mvs, proc)
  expect_equal(ep$estado, c("distribuicao", "citacao", "sentenca", "baixa")); expect_true(ep$censurado[4])
})

test_that("movimento ambíguo não é forçado (Petição (outras) fica sem estado)", {
  proc <- data.table(doc_id = "Y", numero_processo = "10099012120198260224", tribunal = "TJX", grau = "G1", classe_codigo = 7L,
                     oj_codigo = 1L, oj_municipio_ibge = 1L, cnj_ano = 2019L, n_movimentos = 1L,
                     data_ajuizamento = as.POSIXct("2019-01-01", tz = "UTC"), data_ultima_atualizacao = as.POSIXct("2021-01-01", tz = "UTC"))
  mov <- data.table(doc_id = "Y", seq_origem = 1L, seq_crono = 1L, mov_codigo = 85L, mov_datahora = as.POSIXct("2019-03-01", tz = "UTC"))
  comp <- data.table(doc_id = "Y", seq_origem = 1L, comp_descricao = "tipo_de_peticao", comp_valor = 57L)
  expect_true(is.na(assign_states(mov, comp, proc)$estado))
})
