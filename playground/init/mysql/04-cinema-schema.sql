-- =====================================================================
-- poste-db MySQL playground — cinema schema
-- 影视 / 动漫 / 游戏 主题库，多语言演示数据（英文/中文/日文/拉丁/俄文）
-- 类型覆盖：整数族 / DECIMAL / FLOAT / DOUBLE / BOOLEAN / CHAR / VARCHAR /
--   TEXT / MEDIUMTEXT / ENUM / SET / DATE / DATETIME / TIMESTAMP / TIME /
--   YEAR / JSON / BINARY(16) / VARBINARY / BLOB / BIT(1)
-- 36 张表，供 DB browser 树分页与多字节字符显示演示。
-- =====================================================================

SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS cinema CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE cinema;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS list_items, user_lists, award_nominations, award_categories, awards,
  game_achievements, game_releases, posters, trailers, tracks, soundtracks, box_office,
  review_comments, reviews, work_ratings, rating_sources, work_characters, character_voices,
  character_aliases, characters, episode_lines, episodes, seasons, work_people, work_studios,
  work_genres, work_titles, works, people_aliases, people, franchises, studios, genres,
  countries, languages, platforms;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------- 维表 ----------

CREATE TABLE languages (
    code        CHAR(2) PRIMARY KEY,          -- ISO 639-1
    name_en     VARCHAR(50) NOT NULL,
    name_native VARCHAR(50) NOT NULL,         -- 各语言自称（多语演示）
    script      ENUM('Latin','CJK','Cyrillic','Arabic','Other') NOT NULL
) ENGINE=InnoDB COMMENT='语言';

CREATE TABLE countries (
    iso         CHAR(2) PRIMARY KEY,          -- ISO 3166-1
    name_en     VARCHAR(100) NOT NULL,
    name_zh     VARCHAR(100) NOT NULL,
    name_native VARCHAR(100)
) ENGINE=InnoDB COMMENT='国家/地区';

CREATE TABLE genres (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    name_en  VARCHAR(60) NOT NULL UNIQUE,
    name_zh  VARCHAR(60) NOT NULL,
    category ENUM('film','anime','game','general') NOT NULL DEFAULT 'general'
) ENGINE=InnoDB COMMENT='题材类型';

CREATE TABLE studios (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(200) NOT NULL,         -- 原名（含日文/拉丁）
    name_zh    VARCHAR(200),
    country_id CHAR(2),
    founded    SMALLINT,                   -- 成立年份（YEAR 仅支持 1901+，老牌公司可能更早）
    kind       ENUM('film','animation','game','tv','music') NOT NULL DEFAULT 'film',
    logo       VARBINARY(2048) NULL,          -- 二进制占位演示
    FOREIGN KEY (country_id) REFERENCES countries(iso)
) ENGINE=InnoDB COMMENT='制作公司/工作室';

CREATE TABLE franchises (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    name_zh     VARCHAR(200),
    first_year  YEAR,
    description TEXT
) ENGINE=InnoDB COMMENT='IP 系列';

CREATE TABLE people (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name_en     VARCHAR(200) NOT NULL,        -- 通用名（拉丁拼写）
    name_native VARCHAR(200),                 -- 原名（日文/西里尔/汉字）
    name_zh     VARCHAR(200),                 -- 中文译名
    gender      ENUM('female','male','non_binary','unknown') NOT NULL DEFAULT 'unknown',
    country_id  CHAR(2),
    birth_date  DATE NULL,
    death_date  DATE NULL,
    occupation  SET('actor','director','screenwriter','producer','composer',
                   'voice_actor','author','game_director','artist','engineer'),
    biography   TEXT,
    avatar      BLOB NULL
) ENGINE=InnoDB COMMENT='影人/创作者/声优';

CREATE TABLE people_aliases (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    people_id  INT NOT NULL,
    alias      VARCHAR(200) NOT NULL,
    lang       CHAR(2) NOT NULL,
    kind       ENUM('stage_name','kanji','romanized','nickname','pen_name') NOT NULL DEFAULT 'nickname',
    FOREIGN KEY (people_id) REFERENCES people(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='影人别名';

CREATE TABLE platforms (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    kind ENUM('theater','streaming','console','pc','mobile','tv') NOT NULL,
    owner VARCHAR(100)
) ENGINE=InnoDB COMMENT='发行/播出平台';

-- ---------- 作品 ----------

CREATE TABLE works (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    kind         ENUM('film','series','anime','game') NOT NULL,
    title        VARCHAR(300) NOT NULL,       -- 原语言标题（多语演示）
    title_zh     VARCHAR(300) NOT NULL,       -- 中文标题
    original_lang CHAR(2) NOT NULL,
    country_id   CHAR(2),
    franchise_id INT,
    release_year YEAR NOT NULL,
    premiere_date DATE NULL,
    runtime      SMALLINT NULL,               -- 分钟
    maturity     ENUM('G','PG','PG-13','R','NC-17','All','12','15','18',
                      'E','E10+','T','M','AO') NOT NULL DEFAULT 'All',
    score        DECIMAL(3,2) NOT NULL DEFAULT 0.00,
    votes        INT NOT NULL DEFAULT 0,
    status       ENUM('released','airing','paused','cancelled','in_development') NOT NULL DEFAULT 'released',
    synopsis     TEXT,                        -- 剧情简介（多语）
    budget_usd   DECIMAL(14,2) NULL,
    revenue_usd  DECIMAL(14,2) NULL,
    msrp         DECIMAL(10,2) NULL,          -- 零售价（游戏）
    is_animation BOOLEAN NOT NULL DEFAULT FALSE,
    uuid         CHAR(36) NOT NULL,           -- UUID 字符串演示
    metadata     JSON NULL,                   -- JSON 演示（评分/标签/制作组）
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (franchise_id) REFERENCES franchises(id),
    FOREIGN KEY (country_id)  REFERENCES countries(iso),
    INDEX idx_works_kind_year (kind, release_year),
    INDEX idx_works_score (score DESC),
    INDEX idx_works_franchise (franchise_id)
) ENGINE=InnoDB COMMENT='作品（影视/动画/游戏统一表）';

CREATE TABLE work_titles (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    work_id INT NOT NULL,
    lang    CHAR(2) NOT NULL,                 -- en/zh/ja/ru/la
    title   VARCHAR(300) NOT NULL,
    UNIQUE KEY uq_work_title (work_id, lang),
    FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='作品多语言标题';

CREATE TABLE work_genres (
    work_id  INT NOT NULL,
    genre_id INT NOT NULL,
    PRIMARY KEY (work_id, genre_id),
    FOREIGN KEY (work_id)  REFERENCES works(id)  ON DELETE CASCADE,
    FOREIGN KEY (genre_id) REFERENCES genres(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='作品-题材';

CREATE TABLE work_studios (
    work_id  INT NOT NULL,
    studio_id INT NOT NULL,
    role     ENUM('production','animation','publisher','distribution','developer') NOT NULL DEFAULT 'production',
    PRIMARY KEY (work_id, studio_id, role),
    FOREIGN KEY (work_id)   REFERENCES works(id)   ON DELETE CASCADE,
    FOREIGN KEY (studio_id) REFERENCES studios(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='作品-制作公司';

CREATE TABLE work_people (
    work_id   INT NOT NULL,
    people_id INT NOT NULL,
    role      ENUM('director','screenwriter','producer','composer','voice_actor',
                   'actor','cinematographer','game_director','lead_artist','designer') NOT NULL,
    PRIMARY KEY (work_id, people_id, role),
    FOREIGN KEY (work_id)   REFERENCES works(id)   ON DELETE CASCADE,
    FOREIGN KEY (people_id) REFERENCES people(id)  ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='作品-主创';

-- ---------- 季/集 ----------

CREATE TABLE seasons (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    work_id        INT NOT NULL,
    season_no      TINYINT NOT NULL,
    title          VARCHAR(200),
    premiere       DATE,
    finale         DATE,
    episode_count  SMALLINT NOT NULL DEFAULT 0,
    FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE,
    INDEX idx_seasons_work (work_id, season_no)
) ENGINE=InnoDB COMMENT='剧集季度';

CREATE TABLE episodes (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    season_id    INT NOT NULL,
    ep_no        SMALLINT NOT NULL,
    title        VARCHAR(300) NOT NULL,
    air_date     DATE,
    air_time     TIME,
    duration_min SMALLINT,
    summary      TEXT,
    viewership   BIGINT DEFAULT 0,            -- 收视/观看量（演示 BIGINT）
    is_omake     BIT(1) DEFAULT b'0',         -- 特典回（演示 BIT）
    FOREIGN KEY (season_id) REFERENCES seasons(id) ON DELETE CASCADE,
    INDEX idx_episodes_season (season_id, ep_no)
) ENGINE=InnoDB COMMENT='分集';

CREATE TABLE characters (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    work_id     INT NOT NULL,                 -- 主场作品
    name        VARCHAR(200) NOT NULL,        -- 原名（多语）
    name_ja     VARCHAR(200),                 -- 日文名
    name_zh     VARCHAR(200) NOT NULL,        -- 中文名
    name_ru     VARCHAR(200),                 -- 俄文名
    species     VARCHAR(100),                 -- 种族（拉丁文物种名演示）
    role        ENUM('protagonist','deuteragonist','antagonist','supporting','cameo') NOT NULL DEFAULT 'supporting',
    description TEXT,
    is_main     BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE,
    INDEX idx_chars_work (work_id)
) ENGINE=InnoDB COMMENT='角色';

CREATE TABLE character_aliases (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    character_id INT NOT NULL,
    alias        VARCHAR(200) NOT NULL,
    lang         CHAR(2) NOT NULL,
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='角色别名';

CREATE TABLE character_voices (
    character_id INT NOT NULL,
    people_id    INT NOT NULL,
    lang         CHAR(2) NOT NULL DEFAULT 'ja',   -- 日语吹替 = ja；海外配 = en 等
    PRIMARY KEY (character_id, people_id, lang),
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
    FOREIGN KEY (people_id)    REFERENCES people(id)    ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='角色配音演员';

CREATE TABLE work_characters (
    work_id      INT NOT NULL,
    character_id INT NOT NULL,
    guest        BOOLEAN NOT NULL DEFAULT FALSE, -- 客串登场
    PRIMARY KEY (work_id, character_id),
    FOREIGN KEY (work_id)      REFERENCES works(id)      ON DELETE CASCADE,
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='作品-角色登场';

CREATE TABLE episode_lines (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    work_id         INT NOT NULL,             -- 所属作品（跨季）
    episode_id      INT NULL,                 -- 可空：剧场版/名场面
    character_id    INT NULL,
    line_en         TEXT,                     -- 英译
    line_native     TEXT,                     -- 原语言台词
    line_zh         TEXT,                     -- 中译
    line_ru         TEXT,                     -- 俄译
    margin_note     VARCHAR(200),             -- 旁注
    lang_of_original CHAR(2) NOT NULL DEFAULT 'ja',
    FOREIGN KEY (episode_id)   REFERENCES episodes(id)   ON DELETE CASCADE,
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='经典台词（多语言名场面）';

-- ---------- 评分与评价 ----------

CREATE TABLE rating_sources (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL UNIQUE,
    country_iso CHAR(2),
    url        VARCHAR(300)
) ENGINE=InnoDB COMMENT='评分渠道';

CREATE TABLE work_ratings (
    work_id    INT NOT NULL,
    source_id  INT NOT NULL,
    score      DECIMAL(3,2) NOT NULL,         -- 渠道评分（如 IMDB 9.2）
    votes      INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (work_id, source_id),
    FOREIGN KEY (work_id)   REFERENCES works(id)        ON DELETE CASCADE,
    FOREIGN KEY (source_id) REFERENCES rating_sources(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='作品各渠道评分';

CREATE TABLE reviews (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    work_id    INT NOT NULL,
    user_name  VARCHAR(100) NOT NULL,
    rating     TINYINT NOT NULL DEFAULT 8,    -- 1..10
    title      VARCHAR(200),
    body       MEDIUMTEXT NOT NULL,           -- 多语言正文
    lang       CHAR(2) NOT NULL DEFAULT 'en',
    created_at DATETIME NOT NULL,
    likes      INT NOT NULL DEFAULT 0,
    spoiler    BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE,
    INDEX idx_reviews_work (work_id, created_at)
) ENGINE=InnoDB COMMENT='影评';

CREATE TABLE review_comments (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    review_id  INT NOT NULL,
    user_name  VARCHAR(100) NOT NULL,
    body       TEXT NOT NULL,
    lang       CHAR(2) NOT NULL DEFAULT 'en',
    created_at DATETIME NOT NULL,
    FOREIGN KEY (review_id) REFERENCES reviews(id) ON DELETE CASCADE,
    INDEX idx_rc_review (review_id)
) ENGINE=InnoDB COMMENT='影评回复';

-- ---------- 商业与衍生 ----------

CREATE TABLE box_office (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    work_id         INT NOT NULL,
    region          CHAR(3) NOT NULL,         -- 币种区域（USD/CNY/JPY...）
    gross           DECIMAL(16,2) NOT NULL,
    currency        CHAR(3) NOT NULL,
    opening_weekend DECIMAL(14,2),
    year            YEAR NOT NULL,
    FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='票房/销售额';

CREATE TABLE soundtracks (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    work_id     INT NOT NULL,
    title       VARCHAR(200) NOT NULL,
    composer_id INT,
    released    YEAR,
    FOREIGN KEY (work_id)     REFERENCES works(id)    ON DELETE CASCADE,
    FOREIGN KEY (composer_id) REFERENCES people(id)   ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='原声带';

CREATE TABLE tracks (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    soundtrack_id INT NOT NULL,
    track_no    TINYINT NOT NULL,
    title       VARCHAR(200) NOT NULL,
    title_zh    VARCHAR(200),
    duration    TIME NOT NULL,                 -- 时长（演示 TIME）
    vocalist_id INT,
    is_theme    BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (soundtrack_id) REFERENCES soundtracks(id) ON DELETE CASCADE,
    FOREIGN KEY (vocalist_id)   REFERENCES people(id)     ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='曲目';

CREATE TABLE trailers (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    work_id     INT NOT NULL,
    platform_id INT,
    title       VARCHAR(200),
    url         VARCHAR(500),
    duration    SMALLINT,                      -- 秒
    released    DATE,
    views       BIGINT NOT NULL DEFAULT 0,
    FOREIGN KEY (work_id)     REFERENCES works(id)     ON DELETE CASCADE,
    FOREIGN KEY (platform_id) REFERENCES platforms(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='预告片';

CREATE TABLE posters (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    work_id INT NOT NULL,
    kind    ENUM('poster','backdrop','still','logo') NOT NULL DEFAULT 'poster',
    filename VARCHAR(255) NOT NULL,
    url     VARCHAR(500),
    width   SMALLINT NOT NULL,
    height  SMALLINT NOT NULL,
    format  ENUM('jpg','png','webp') NOT NULL DEFAULT 'jpg',
    FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE,
    INDEX idx_posters_work (work_id, kind)
) ENGINE=InnoDB COMMENT='海报等媒体物料';

-- ---------- 游戏 ----------

CREATE TABLE game_releases (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    work_id      INT NOT NULL,
    platform_id  INT NOT NULL,
    region       VARCHAR(40) NOT NULL DEFAULT 'WW',
    release_date DATE NOT NULL,
    price        DECIMAL(10,2) NOT NULL,
    physical     BOOLEAN NOT NULL DEFAULT TRUE,
    rating       ENUM('E','E10+','T','M','AO','All','12','16','18') NOT NULL DEFAULT 'T',
    FOREIGN KEY (work_id)     REFERENCES works(id)     ON DELETE CASCADE,
    FOREIGN KEY (platform_id) REFERENCES platforms(id) ON DELETE CASCADE,
    INDEX idx_releases_work (work_id, platform_id)
) ENGINE=InnoDB COMMENT='游戏各平台发售';

CREATE TABLE game_achievements (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    work_id     INT NOT NULL,
    name        VARCHAR(200) NOT NULL,
    name_zh     VARCHAR(200),
    hidden_hid  BINARY(16) NULL,               -- 二进制 GID 演示
    description VARCHAR(300),
    points      TINYINT NOT NULL DEFAULT 0,    -- 玩家分数
    hidden      BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE,
    INDEX idx_ach_work (work_id)
) ENGINE=InnoDB COMMENT='游戏成就';

-- ---------- 奖项 ----------

CREATE TABLE awards (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(200) NOT NULL UNIQUE,
    org         VARCHAR(200),
    country_iso CHAR(2),
    first_year  YEAR
) ENGINE=InnoDB COMMENT='奖项';

CREATE TABLE award_categories (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    award_id INT NOT NULL,
    name    VARCHAR(200) NOT NULL,
    FOREIGN KEY (award_id) REFERENCES awards(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='奖项分类';

CREATE TABLE award_nominations (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    award_category_id   INT NOT NULL,
    work_id             INT NULL,
    people_id           INT NULL,
    year                YEAR NOT NULL,
    won                 BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (award_category_id) REFERENCES award_categories(id) ON DELETE CASCADE,
    FOREIGN KEY (work_id)   REFERENCES works(id)   ON DELETE CASCADE,
    FOREIGN KEY (people_id) REFERENCES people(id)  ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='颁奖提名';

-- ---------- 用户片单 ----------

CREATE TABLE user_lists (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    user_name   VARCHAR(100) NOT NULL,
    title       VARCHAR(200) NOT NULL,
    description VARCHAR(300),
    is_public   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB COMMENT='用户片单';

CREATE TABLE list_items (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    list_id  INT NOT NULL,
    work_id  INT NOT NULL,
    position INT NOT NULL DEFAULT 0,
    note     VARCHAR(300),
    FOREIGN KEY (list_id) REFERENCES user_lists(id) ON DELETE CASCADE,
    FOREIGN KEY (work_id) REFERENCES works(id)      ON DELETE CASCADE,
    INDEX idx_list_items (list_id, position)
) ENGINE=InnoDB COMMENT='片单项';