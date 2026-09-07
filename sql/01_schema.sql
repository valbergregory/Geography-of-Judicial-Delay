-- 01_schema.sql — esquema DuckDB (protótipo). Portável para PostgreSQL/PostGIS
-- com pequenas trocas de tipo (JSON -> jsonb; geometria em tabela separada).
-- Chaves: doc_id (processo × grau no índice do DataJud) e numero_processo
-- (liga G1, G2, JE e TR do mesmo feito).

CREATE TABLE IF NOT EXISTS processos (
  doc_id                   VARCHAR PRIMARY KEY,
  indice                   VARCHAR,
  numero_processo          VARCHAR NOT NULL,
  tribunal                 VARCHAR NOT NULL,
  grau                     VARCHAR,
  classe_codigo            INTEGER,
  classe_nome              VARCHAR,
  sistema_nome             VARCHAR,
  formato_nome             VARCHAR,
  nivel_sigilo             INTEGER,
  oj_codigo                INTEGER,
  oj_nome                  VARCHAR,
  oj_municipio_ibge        INTEGER,
  data_ajuizamento_raw     VARCHAR,
  data_ajuizamento_fmt     VARCHAR,      -- iso | compact14 | epoch | other (auditoria)
  data_ajuizamento         TIMESTAMP,
  data_ultima_atualizacao  TIMESTAMP,    -- censura: o documento só é conhecido até aqui
  timestamp_indice         TIMESTAMP,
  n_movimentos             INTEGER,
  n_assuntos               INTEGER,
  cnj_valido               BOOLEAN,
  cnj_ano                  INTEGER,      -- ano do número CNJ (coorte)
  cnj_segmento             INTEGER,
  cnj_tribunal             VARCHAR,
  cnj_origem               VARCHAR,      -- código da unidade de origem no número CNJ
  fonte                    VARCHAR,
  coletado_em              TIMESTAMP DEFAULT current_timestamp
);
CREATE INDEX IF NOT EXISTS idx_proc_num ON processos(numero_processo);
CREATE INDEX IF NOT EXISTS idx_proc_trib_classe_ano ON processos(tribunal, classe_codigo, cnj_ano);
CREATE INDEX IF NOT EXISTS idx_proc_oj ON processos(oj_codigo);

CREATE TABLE IF NOT EXISTS movimentos (
  doc_id            VARCHAR NOT NULL,
  seq_origem        INTEGER NOT NULL,   -- ordem enviada pelo tribunal
  seq_crono         INTEGER,            -- ordem cronológica reconstruída
  mov_codigo        INTEGER,            -- NULL = movimento sem código (TJAL)
  mov_nome          VARCHAR,
  mov_datahora_raw  VARCHAR,
  mov_datahora      TIMESTAMP,
  mov_oj_codigo     INTEGER,            -- órgão do movimento (redistribuição / 2º grau)
  n_complementos    INTEGER,
  complementos_json VARCHAR,   -- JSON serializado (evita extensão json do DuckDB)
  PRIMARY KEY (doc_id, seq_origem)
);
CREATE INDEX IF NOT EXISTS idx_mov_codigo ON movimentos(mov_codigo);
CREATE INDEX IF NOT EXISTS idx_mov_data ON movimentos(mov_datahora);

CREATE TABLE IF NOT EXISTS complementos (
  doc_id         VARCHAR NOT NULL,
  seq_origem     INTEGER NOT NULL,
  comp_codigo    INTEGER,
  comp_descricao VARCHAR,   -- ex.: tipo_de_documento, tipo_de_conclusao, tipo_de_peticao
  comp_valor     INTEGER,
  comp_nome      VARCHAR
);

CREATE TABLE IF NOT EXISTS assuntos (
  doc_id         VARCHAR NOT NULL,
  assunto_codigo INTEGER,
  assunto_nome   VARCHAR,
  ordem          INTEGER
);

-- Dicionários da TPU (versão registrada em tpu_versao)
CREATE TABLE IF NOT EXISTS tpu_movimentos (
  codigo INTEGER PRIMARY KEY, codigo_pai INTEGER, nome VARCHAR, situacao VARCHAR,
  nivel INTEGER, tem_filhos BOOLEAN, caminho VARCHAR
);
CREATE TABLE IF NOT EXISTS tpu_classes (
  codigo INTEGER PRIMARY KEY, codigo_pai INTEGER, nome VARCHAR, situacao VARCHAR,
  nivel INTEGER, tem_filhos BOOLEAN, caminho VARCHAR
);
CREATE TABLE IF NOT EXISTS tpu_versao (versao_data DATE, consultado_em DATE, fonte VARCHAR);

-- Mapeamento transparente movimento -> estado substantivo (carregado de config/state_mapping.csv)
CREATE TABLE IF NOT EXISTS state_mapping (
  estado VARCHAR, mov_codigo INTEGER, comp_descricao VARCHAR, comp_valor INTEGER,
  papel VARCHAR,            -- entrada | evidencia | terminal | reabertura | suspensao
  confianca VARCHAR,        -- alta | media | baixa (ambíguo: não força correspondência)
  observacao VARCHAR
);

-- Estados e transições reconstruídos (1 episódio por permanência em estado)
CREATE TABLE IF NOT EXISTS estados (
  doc_id VARCHAR NOT NULL, episodio INTEGER NOT NULL, estado VARCHAR NOT NULL,
  inicio TIMESTAMP, fim TIMESTAMP, dias DOUBLE, censurado BOOLEAN,
  mov_codigo_entrada INTEGER, confianca VARCHAR,
  PRIMARY KEY (doc_id, episodio)
);
CREATE TABLE IF NOT EXISTS transicoes (
  doc_id VARCHAR NOT NULL, de VARCHAR, para VARCHAR, quando TIMESTAMP, dias_no_estado DOUBLE
);

-- Unidades judiciárias e territórios
CREATE TABLE IF NOT EXISTS unidades (
  tribunal VARCHAR, oj_codigo INTEGER, oj_nome VARCHAR, municipio_ibge INTEGER,
  comarca VARCHAR, entrancia VARCHAR, competencia VARCHAR, fonte VARCHAR, ano_ref INTEGER,
  PRIMARY KEY (tribunal, oj_codigo)
);
CREATE TABLE IF NOT EXISTS municipios (
  municipio_ibge INTEGER PRIMARY KEY, nome VARCHAR, uf VARCHAR, regiao_imediata INTEGER,
  regiao_intermediaria INTEGER, area_km2 DOUBLE, lat DOUBLE, lon DOUBLE
);
CREATE TABLE IF NOT EXISTS indicadores_municipio (   -- painel município × ano (IBGE, Anatel)
  municipio_ibge INTEGER, ano INTEGER, variavel VARCHAR, valor DOUBLE, fonte VARCHAR, ano_ref_fonte INTEGER,
  PRIMARY KEY (municipio_ibge, ano, variavel)
);
CREATE TABLE IF NOT EXISTS indicadores_unidade (     -- painel unidade × ano (Justiça em Números / Módulo de Produtividade)
  tribunal VARCHAR, oj_codigo INTEGER, ano INTEGER, variavel VARCHAR, valor DOUBLE, fonte VARCHAR,
  PRIMARY KEY (tribunal, oj_codigo, ano, variavel)
);
CREATE TABLE IF NOT EXISTS politicas (               -- eventos de política datados (para DiD / estudo de evento)
  politica VARCHAR, tribunal VARCHAR, oj_codigo INTEGER, municipio_ibge INTEGER,
  data_inicio DATE, data_fim DATE, fonte VARCHAR, observacao VARCHAR
);

-- Auditoria de coleta
CREATE TABLE IF NOT EXISTS coleta_log (
  ts TIMESTAMP, tribunal VARCHAR, tag VARCHAR, key VARCHAR, status INTEGER, took_ms INTEGER,
  hits INTEGER, secs DOUBLE, error VARCHAR
);
