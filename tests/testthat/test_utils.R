library(testthat)
root <- rprojroot::find_root(rprojroot::has_file("CLAUDE.md"))
source(file.path(root, "R/01_config.R"), encoding = "UTF-8"); source(file.path(root, "R/02_utils.R"), encoding = "UTF-8")

test_that("parse_datajud_datetime lida com os três formatos observados", {
  x <- parse_datajud_datetime(c("2019-03-26T13:58:58.000Z", "20190326135858", "1547038920000", "1547038920", NA, "lixo"))
  expect_equal(format(x[1:4], "%Y-%m-%d"), c("2019-03-26", "2019-03-26", "2019-01-09", "2019-01-09"))
  expect_true(all(is.na(x[5:6])))
  expect_equal(datajud_date_format(c("2019-03-26T13:58:58.000Z", "20190326135858", "1547038920000")), c("iso", "compact14", "epoch"))
})

test_that("datas impossíveis viram NA", {
  expect_true(is.na(parse_datajud_datetime("25450101000000")))
})

test_that("parse_cnj extrai ano, segmento, tribunal e origem", {
  p <- parse_cnj("1009901-21.2019.8.26.0224")
  expect_true(p$cnj_valido); expect_equal(p$cnj_ano, 2019L); expect_equal(p$cnj_segmento, 8L)
  expect_equal(p$cnj_tribunal, "26"); expect_equal(p$cnj_origem, "0224")
  expect_false(parse_cnj("123")$cnj_valido)
})

test_that("dígito verificador CNJ confere em número real do TJSP", {
  expect_true(cnj_check_digit_ok("10099012120198260224"))
  expect_false(cnj_check_digit_ok("10099012220198260224"))
})
