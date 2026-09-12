-- =====================================================================
-- poste-db MySQL playground — history schema
-- 世界历史主题库，多语言演示数据（英文/中文/日文/拉丁/俄文）
-- 在 cinema 基础上补充类型覆盖：DOUBLE / FLOAT / SMALLINT / POINT(GEOMETRY)
--   并复用 ENUM / SET / JSON / BINARY(16) / BLOB / TIME 等
-- 34 张表，含大表 timeline_events / citations 供树分页演示。
-- =====================================================================

SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS history CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE history;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS historical_photos, citations, timeline_events, maps, discoveries,
  expeditions, buildings, currencies, museum_holdings, museums, relics, archaeological_sites,
  deities, mythologies, religions, schools_of_thought, inventions, literary_works, documents,
  treaties, battles, wars, event_participants, historical_events, capitals, dynasties,
  family_members, figure_aliases, historical_figures, court_offices, families, eras,
  civilizations, regions;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------- 地理与早年维表 ----------

CREATE TABLE regions (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    code        CHAR(3) NOT NULL UNIQUE,      -- 区域代码（演示 CHAR）
    name_en     VARCHAR(100) NOT NULL,
    name_zh     VARCHAR(100) NOT NULL,
    name_native VARCHAR(100),
    continent   ENUM('asia','europe','africa','americas','oceania') NOT NULL,
    area_km2    DOUBLE NOT NULL,              -- 面积（演示 DOUBLE 大数）
    lat         DOUBLE NOT NULL,
    lng         DOUBLE NOT NULL,
    note        VARCHAR(300)
) ENGINE=InnoDB COMMENT='历史区域';

CREATE TABLE civilizations (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    region_id     INT NOT NULL,
    name_en       VARCHAR(120) NOT NULL,
    name_native   VARCHAR(120),
    name_zh       VARCHAR(120) NOT NULL,
    start_year    INT,                        -- 负值 = 公元前
    end_year      INT,
    writing_system ENUM('cuneiform','hieroglyphs','ideographic','syllabic','alphabet','other'),
    flourish      VARCHAR(200),
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='文明';

CREATE TABLE eras (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    name_en   VARCHAR(100) NOT NULL,
    name_zh   VARCHAR(100) NOT NULL,
    name_ja   VARCHAR(100),
    name_ru   VARCHAR(100),
    start_year INT,
    end_year   INT,
    description TEXT
) ENGINE=InnoDB COMMENT='历史分期';

CREATE TABLE families (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    region_id INT,
    name_en   VARCHAR(150) NOT NULL,
    name_zh   VARCHAR(150) NOT NULL,
    name_native VARCHAR(150),
    rallied   VARCHAR(200),                   -- 发迹地
    sigil     VARCHAR(200),                   -- 纹章/族徽
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='世家/家族';

CREATE TABLE court_offices (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    region_id  INT,
    name_en    VARCHAR(150) NOT NULL,
    name_zh    VARCHAR(150) NOT NULL,
    rank_en    VARCHAR(100),
    office_function VARCHAR(300),
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='官职/头衔';

-- ---------- 人物 ----------

CREATE TABLE historical_figures (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    region_id      INT NOT NULL,
    family_id      INT,
    court_office_id INT,
    name_en        VARCHAR(200) NOT NULL,     -- 通用名
    name_zh        VARCHAR(200) NOT NULL,
    name_ja        VARCHAR(200),
    name_ru        VARCHAR(200),
    name_la        VARCHAR(200),              -- 拉丁化名（多语演示）
    gender         ENUM('female','male','non_binary','unknown') NOT NULL DEFAULT 'unknown',
    birth_year     INT NULL,                  -- 负值 = 公元前
    death_year     INT NULL,
    reign_start    INT NULL,                  -- 在位起
    reign_end      INT NULL,
    biography      MEDIUMTEXT,                -- 多语传记
    honors         JSON NULL,                 -- 名号/谥号/庙号
    portrait       BLOB NULL,
    FOREIGN KEY (region_id)      REFERENCES regions(id),
    FOREIGN KEY (family_id)      REFERENCES families(id)      ON DELETE SET NULL,
    FOREIGN KEY (court_office_id) REFERENCES court_offices(id) ON DELETE SET NULL,
    INDEX idx_hist_region (region_id),
    INDEX idx_hist_reign (reign_start, reign_end)
) ENGINE=InnoDB COMMENT='历史人物';

CREATE TABLE figure_aliases (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    figure_id    INT NOT NULL,
    alias        VARCHAR(200) NOT NULL,
    lang         CHAR(2) NOT NULL,
    kind         ENUM('regnal name','era name','posthumous name','temple name','cognomen','hidden'),
    FOREIGN KEY (figure_id) REFERENCES historical_figures(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='人物别名/称号';

CREATE TABLE family_members (
    family_id INT NOT NULL,
    figure_id INT NOT NULL,
    relation  ENUM('founder','patriarch','matriarch','heir','spouse','consort','collateral') NOT NULL,
    start_year INT,
    end_year   INT,
    PRIMARY KEY (family_id, figure_id, relation),
    FOREIGN KEY (family_id) REFERENCES families(id)          ON DELETE CASCADE,
    FOREIGN KEY (figure_id) REFERENCES historical_figures(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='家族成员关系';

-- ---------- 朝代与都城 ----------

CREATE TABLE dynasties (
    id                INT AUTO_INCREMENT PRIMARY KEY,
    region_id         INT NOT NULL,
    civilization_id   INT,
    era_id            INT,
    founder_figure_id INT,
    name_en           VARCHAR(150) NOT NULL,
    name_zh           VARCHAR(150) NOT NULL,
    name_native       VARCHAR(150),
    established_year  INT NULL,               -- 负值 = 公元前
    ended_year        INT NULL,
    sovereigns        TINYINT,                -- 帝数
    note              TEXT,
    FOREIGN KEY (region_id)       REFERENCES regions(id),
    FOREIGN KEY (civilization_id) REFERENCES civilizations(id),
    FOREIGN KEY (era_id)          REFERENCES eras(id),
    FOREIGN KEY (founder_figure_id) REFERENCES historical_figures(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='朝代/王朝';

CREATE TABLE capitals (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    dynasty_id   INT NOT NULL,
    name_en      VARCHAR(150) NOT NULL,
    name_zh      VARCHAR(150) NOT NULL,
    name_ja      VARCHAR(150),
    coord        POINT NOT NULL,              -- 经纬度（演示 POINT / GEOMETRY）
    elevation_m  SMALLINT,                    -- 海拔（演示 SMALLINT）
    first_year   INT NULL,
    last_year    INT NULL,
    FOREIGN KEY (dynasty_id) REFERENCES dynasties(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='都城（含地理坐标）';

-- ---------- 事件与战争 ----------

CREATE TABLE historical_events (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    region_id   INT NOT NULL,
    era_id      INT,
    name_en     VARCHAR(250) NOT NULL,
    name_zh     VARCHAR(250) NOT NULL,
    name_ja     VARCHAR(250),
    name_ru     VARCHAR(250),
    event_year  INT NULL,                     -- 负值 = 公元前
    kind        ENUM('rebellion','war','reform','revolution','disaster','trade','diplomacy','exploration','cultural','politics','misc') NOT NULL DEFAULT 'misc',
    description MEDIUMTEXT,
    FOREIGN KEY (region_id) REFERENCES regions(id),
    FOREIGN KEY (era_id)    REFERENCES eras(id),
    INDEX idx_events_year (event_year)
) ENGINE=InnoDB COMMENT='历史事件';

CREATE TABLE event_participants (
    event_id     INT NOT NULL,
    figure_id    INT NOT NULL,
    role         ENUM('leader','general','advisor','chronicler','opponent','victim','beneficiary') NOT NULL DEFAULT 'leader',
    note         VARCHAR(300),
    PRIMARY KEY (event_id, figure_id, role),
    FOREIGN KEY (event_id)  REFERENCES historical_events(id)  ON DELETE CASCADE,
    FOREIGN KEY (figure_id) REFERENCES historical_figures(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='事件参与人物';

CREATE TABLE wars (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    region_id   INT NOT NULL,
    era_id      INT,
    name_en     VARCHAR(250) NOT NULL,
    name_zh     VARCHAR(250) NOT NULL,
    name_ja     VARCHAR(250),
    started     INT NULL,
    ended       INT NULL,
    result_en   VARCHAR(200),
    belligerents SET('China','Japan','India','Persia','Greece','Rome','Egypt','Mesopotamia','Maya','Inca','Carthage','Ottoman','Byzantine','Europe','Islamic','Mongol','America'),  -- 参战方（演示 SET）
    FOREIGN KEY (region_id) REFERENCES regions(id),
    FOREIGN KEY (era_id)    REFERENCES eras(id)
) ENGINE=InnoDB COMMENT='战争';

CREATE TABLE battles (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    war_id       INT NOT NULL,
    name_en      VARCHAR(250) NOT NULL,
    name_zh      VARCHAR(250) NOT NULL,
    name_ja      VARCHAR(250),
    battle_date  INT NULL,                    -- 负值 = 公元前
    coord        POINT NULL,                  -- 战场坐标（演示 POINT）
    troops_a     INT,                         -- 甲军
    troops_b     INT,                         -- 乙军
    casualty_ratio FLOAT,                     -- 伤亡比（演示 FLOAT）
    outcome      ENUM('A victory','B victory','stalemate','inconclusive','unknown') NOT NULL DEFAULT 'unknown',
    FOREIGN KEY (war_id) REFERENCES wars(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='战役（含坐标与双军规模）';

CREATE TABLE treaties (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    war_id     INT,
    name_en    VARCHAR(250) NOT NULL,
    name_zh    VARCHAR(250) NOT NULL,
    name_ja    VARCHAR(250),
    sign_year  INT NULL,
    parties    VARCHAR(300),
    FOREIGN KEY (war_id) REFERENCES wars(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='条约/和约';

-- ---------- 文书与典籍 ----------

CREATE TABLE documents (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    region_id    INT NOT NULL,
    era_id       INT,
    author_figure_id INT,
    title_en     VARCHAR(250) NOT NULL,
    title_zh     VARCHAR(250) NOT NULL,
    lang         CHAR(2) NOT NULL DEFAULT 'la',
    material     ENUM('bamboo','bronze','papyrus','parchment','paper','stone','wax','clay') NOT NULL,
    archive_hid  BINARY(16),                  -- 档案编号（演示 BINARY）
    body         MEDIUMTEXT,
    issued_year  INT NULL,
    FOREIGN KEY (region_id) REFERENCES regions(id),
    FOREIGN KEY (era_id)    REFERENCES eras(id),
    FOREIGN KEY (author_figure_id) REFERENCES historical_figures(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='重要文书/法典';

CREATE TABLE literary_works (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    author_figure_id INT,
    dynasty_id INT,
    title_en   VARCHAR(250) NOT NULL,
    title_zh   VARCHAR(250) NOT NULL,
    title_ja   VARCHAR(250),
    title_ru   VARCHAR(250),
    lang       CHAR(2) NOT NULL DEFAULT 'en',
    genre      ENUM('epic','drama','poetry','novel','essay','chronicle','philosophy') NOT NULL DEFAULT 'epic',
    written_year INT,
    source_hid BINARY(16),                    -- 版本编号（演示 BINARY）
    excerpt    MEDIUMTEXT,
    FOREIGN KEY (author_figure_id) REFERENCES historical_figures(id) ON DELETE SET NULL,
    FOREIGN KEY (dynasty_id) REFERENCES dynasties(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='文学典籍';

CREATE TABLE inventions (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    region_id  INT,
    dynasty_id INT,
    inventor_id INT,
    name_en    VARCHAR(200) NOT NULL,
    name_zh    VARCHAR(200) NOT NULL,
    name_ja    VARCHAR(200),
    year       INT NULL,
    field      ENUM('military','navigation','agriculture','textile','medicine','communication','transport','print','engineering') NOT NULL DEFAULT 'engineering',
    description VARCHAR(400),
    is_four_great BOOLEAN NOT NULL DEFAULT FALSE,   -- 四大发明标记
    FOREIGN KEY (region_id)  REFERENCES regions(id),
    FOREIGN KEY (dynasty_id) REFERENCES dynasties(id) ON DELETE SET NULL,
    FOREIGN KEY (inventor_id) REFERENCES historical_figures(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='发明创造';

CREATE TABLE schools_of_thought (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    region_id     INT,
    founder_id    INT,
    name_en       VARCHAR(200) NOT NULL,
    name_zh       VARCHAR(200) NOT NULL,
    name_ja       VARCHAR(200),
    classification ENUM('philosophy','religion','military','political','economic','science') NOT NULL DEFAULT 'philosophy',
    tenet         TEXT,
    flourished    VARCHAR(150),
    FOREIGN KEY (region_id) REFERENCES regions(id),
    FOREIGN KEY (founder_id) REFERENCES historical_figures(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='思想流派';

CREATE TABLE religions (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    region_id    INT,
    name_en      VARCHAR(200) NOT NULL,
    name_zh      VARCHAR(200) NOT NULL,
    name_ja      VARCHAR(200),
    classification ENUM('monotheistic','polytheistic','henotheistic','non-theistic','animistic','dualistic') NOT NULL,
    founded_year INT NULL,
    followers_est BIGINT,                     -- 估计信众（演示 BIGINT）
    sacred_text  VARCHAR(300),
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='宗教';

CREATE TABLE mythologies (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    region_id INT,
    name_en   VARCHAR(200) NOT NULL,
    name_zh   VARCHAR(200) NOT NULL,
    culture   VARCHAR(150),
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='神话体系';

CREATE TABLE deities (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    mythology_id INT NOT NULL,
    name_en     VARCHAR(150) NOT NULL,
    name_zh     VARCHAR(150) NOT NULL,
    name_ja     VARCHAR(150),
    name_ru     VARCHAR(150),
    name_la     VARCHAR(150),
    domains     SET('sky','war','wisdom','love','death','sea','hearth','nature','thunder','sun','moon','underworld','fertility') NOT NULL,
    worship_index FLOAT,                      -- 崇拜热度（演示 FLOAT）
    attributes  JSON NULL,                    -- 圣兽/圣物/对应希腊神
    FOREIGN KEY (mythology_id) REFERENCES mythologies(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='神祇';

-- ---------- 考古与文物 ----------

CREATE TABLE archaeological_sites (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    region_id  INT NOT NULL,
    name_en    VARCHAR(200) NOT NULL,
    name_zh    VARCHAR(200) NOT NULL,
    name_ja    VARCHAR(200),
    coord      POINT NOT NULL,                -- 遗址坐标（演示 POINT）
    found_year INT,
    excavator  VARCHAR(150),
    description TEXT,
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='考古遗址';

CREATE TABLE relics (
    id                INT AUTO_INCREMENT PRIMARY KEY,
    dynasty_id        INT,
    discovered_site_id INT,
    name_en           VARCHAR(200) NOT NULL,
    name_zh           VARCHAR(200) NOT NULL,
    name_ja           VARCHAR(200),
    material          ENUM('bronze','jade','gold','silver','pottery','stone','silk','iron','bone','wood') NOT NULL,
    geodata           BINARY(16),             -- 文物唯一编号（演示 BINARY）
    excavated_year    INT,
    appraisal         DECIMAL(12,2) NULL,     -- 估值（演示 DECIMAL 大数）
    description       TEXT,
    FOREIGN KEY (dynasty_id)        REFERENCES dynasties(id)        ON DELETE SET NULL,
    FOREIGN KEY (discovered_site_id) REFERENCES archaeological_sites(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='文物';

CREATE TABLE museums (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    region_id    INT,
    name_en      VARCHAR(200) NOT NULL,
    name_zh      VARCHAR(200) NOT NULL,
    city         VARCHAR(120) NOT NULL,
    established  SMALLINT,
    admission    DECIMAL(8,2) NULL,
    url          VARCHAR(300),
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='博物馆';

CREATE TABLE museum_holdings (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    museum_id  INT NOT NULL,
    relic_id   INT NOT NULL,
    acquired   DATE,
    collection VARCHAR(120),
    UNIQUE KEY uq_holding (museum_id, relic_id),
    FOREIGN KEY (museum_id) REFERENCES museums(id) ON DELETE CASCADE,
    FOREIGN KEY (relic_id)  REFERENCES relics(id)  ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='博物馆馆藏';

CREATE TABLE currencies (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    region_id    INT,
    dynasty_id   INT,
    name_en      VARCHAR(150) NOT NULL,
    name_zh      VARCHAR(150) NOT NULL,
    code         CHAR(3),                     -- 通货代码（演示 CHAR）
    introduced   SMALLINT,
    demonetized  SMALLINT NULL,
    subdivision  VARCHAR(60),
    FOREIGN KEY (region_id)  REFERENCES regions(id),
    FOREIGN KEY (dynasty_id) REFERENCES dynasties(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='货币';

CREATE TABLE buildings (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    region_id  INT,
    dynasty_id INT,
    name_en    VARCHAR(200) NOT NULL,
    name_zh    VARCHAR(200) NOT NULL,
    name_ja    VARCHAR(200),
    built_year INT NULL,
    style      ENUM('gothic','baroque','classical','han','tang','ming','modern','other') NOT NULL DEFAULT 'other',
    lat        DOUBLE,                        -- 演示 DOUBLE
    lng        DOUBLE,
    height_m   DOUBLE,
    FOREIGN KEY (region_id)  REFERENCES regions(id),
    FOREIGN KEY (dynasty_id) REFERENCES dynasties(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='建筑';

-- ---------- 探索与测绘 ----------

CREATE TABLE expeditions (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    leader_figure_id INT,
    region_id      INT,
    name_en        VARCHAR(250) NOT NULL,
    name_zh        VARCHAR(250) NOT NULL,
    name_ja        VARCHAR(250),
    start_year     INT NULL,
    end_year       INT NULL,
    departure      POINT NULL,                -- 出发地坐标（演示 POINT）
    ships_count    SMALLINT,                  -- 船队规模（演示 SMALLINT）
    crew_count     INT,
    route_desc     TEXT,
    FOREIGN KEY (leader_figure_id) REFERENCES historical_figures(id) ON DELETE SET NULL,
    FOREIGN KEY (region_id) REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='远航/远征';

CREATE TABLE discoveries (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    expedition_id INT,
    region_id     INT,
    name_en       VARCHAR(200) NOT NULL,
    name_zh       VARCHAR(200) NOT NULL,
    year          INT NULL,
    field         ENUM('geography','biology','astronomy','physics','chemistry','archaeology','medicine','cartography') NOT NULL DEFAULT 'geography',
    note          VARCHAR(400),
    FOREIGN KEY (expedition_id) REFERENCES expeditions(id) ON DELETE SET NULL,
    FOREIGN KEY (region_id)     REFERENCES regions(id)
) ENGINE=InnoDB COMMENT='发现/发明记录';

CREATE TABLE maps (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    region_id      INT,
    cartographer_id INT,
    title_en       VARCHAR(200) NOT NULL,
    title_zh       VARCHAR(200) NOT NULL,
    produced_year  INT,
    projection     VARCHAR(100),
    source_hid     BINARY(16),                -- 馆藏影像编号（演示 BINARY）
    FOREIGN KEY (region_id)       REFERENCES regions(id),
    FOREIGN KEY (cartographer_id) REFERENCES historical_figures(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='历史地图';

-- ---------- 大表（分页演示） ----------

CREATE TABLE timeline_events (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    region_id  INT,
    era_id     INT,
    event_year INT NULL,                      -- 负值 = 公元前
    title_en   VARCHAR(250) NOT NULL,
    title_zh   VARCHAR(250) NOT NULL,
    title_ja   VARCHAR(250),
    title_ru   VARCHAR(250),
    kind       ENUM('war','politics','culture','science','economy','religion','disaster','misc') NOT NULL DEFAULT 'misc',
    detail     TEXT,
    FOREIGN KEY (region_id) REFERENCES regions(id),
    FOREIGN KEY (era_id)    REFERENCES eras(id),
    INDEX idx_timeline_year (event_year),
    INDEX idx_timeline_kind (kind)
) ENGINE=InnoDB COMMENT='时间线事件（大表，2000+ 行）';

CREATE TABLE citations (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    figure_id     INT NOT NULL,
    source_work_id INT,                       -- 出处典籍
    quote_en      VARCHAR(500) NOT NULL,
    quote_zh      VARCHAR(500) NOT NULL,
    quote_ja      VARCHAR(500),
    quote_ru      VARCHAR(500),
    quote_la      VARCHAR(500),
    lang          CHAR(2) NOT NULL DEFAULT 'en',
    page_no       SMALLINT,                   -- 页码（演示 SMALLINT）
    FOREIGN KEY (figure_id)       REFERENCES historical_figures(id) ON DELETE CASCADE,
    FOREIGN KEY (source_work_id)  REFERENCES literary_works(id)     ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='人物名言引用（多语，900+ 行）';

CREATE TABLE historical_photos (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    figure_id   INT,
    site_id     INT,
    relic_id    INT,
    title_en    VARCHAR(200) NOT NULL,
    title_zh    VARCHAR(200) NOT NULL,
    filename    VARCHAR(255) NOT NULL,
    year        SMALLINT,
    format      ENUM('jpg','png','tiff') NOT NULL DEFAULT 'jpg',
    image       BLOB NULL,                    -- 缩略图二进制占位
    FOREIGN KEY (figure_id) REFERENCES historical_figures(id)  ON DELETE SET NULL,
    FOREIGN KEY (site_id)   REFERENCES archaeological_sites(id) ON DELETE SET NULL,
    FOREIGN KEY (relic_id)  REFERENCES relics(id)             ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='历史照片';