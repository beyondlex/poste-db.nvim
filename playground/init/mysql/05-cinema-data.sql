-- =====================================================================
-- poste-db MySQL playground — cinema data
-- 手写知名作品/人物/角色 + 批量生成达到分页演示量
-- 多语言演示：英文 / 中文 / 日文 / 拉丁 / 俄文
-- 生成技巧：WITH RECURSIVE seq(i)<100 × CROSS JOIN 突破 1000 递归上限
-- =====================================================================

SET NAMES utf8mb4;
USE cinema;

-- ---------- 维表 ----------

INSERT INTO languages (code, name_en, name_native, script) VALUES
  ('en', 'English', 'English', 'Latin'),
  ('zh', 'Chinese', '中文', 'CJK'),
  ('ja', 'Japanese', '日本語', 'CJK'),
  ('ru', 'Russian', 'Русский', 'Cyrillic'),
  ('la', 'Latin', 'Latina', 'Latin'),
  ('es', 'Spanish', 'Español', 'Latin');

INSERT INTO countries (iso, name_en, name_zh, name_native) VALUES
  ('CN', 'China', '中国', '中国'),
  ('JP', 'Japan', '日本', '日本'),
  ('US', 'United States', '美国', 'United States of America'),
  ('KR', 'South Korea', '韩国', '대한민국'),
  ('GB', 'United Kingdom', '英国', 'The United Kingdom'),
  ('FR', 'France', '法国', 'France'),
  ('DE', 'Germany', '德国', 'Deutschland'),
  ('IT', 'Italy', '意大利', 'Italia'),
  ('RU', 'Russia', '俄罗斯', 'Россия'),
  ('PL', 'Poland', '波兰', 'Polska'),
  ('CA', 'Canada', '加拿大', 'Canada'),
  ('AU', 'Australia', '澳大利亚', 'Australia'),
  ('SE', 'Sweden', '瑞典', 'Sverige');

INSERT INTO genres (name_en, name_zh, category) VALUES
  ('Action', '动作', 'film'), ('Adventure', '冒险', 'film'),
  ('Sci-Fi', '科幻', 'film'), ('Fantasy', '奇幻', 'film'),
  ('Romance', '爱情', 'film'), ('Drama', '剧情', 'film'),
  ('Comedy', '喜剧', 'film'), ('Horror', '恐怖', 'film'),
  ('Mystery', '悬疑', 'film'), ('Animation', '动画', 'anime'),
  ('Shounen', '少年', 'anime'), ('Slice of Life', '日常', 'anime'),
  ('Mecha', '机甲', 'anime'), ('RPG', '角色扮演', 'game');

-- 制作公司/工作室
INSERT INTO studios (name, name_zh, country_id, founded, kind) VALUES
  ('東映アニメーション / Toei Animation', '东映动画', 'JP', 1948, 'animation'),
  ('京都アニメーション / Kyoto Animation', '京都动画', 'JP', 1981, 'animation'),
  ('スタジオジブリ / Studio Ghibli', '吉卜力工作室', 'JP', 1985, 'animation'),
  ('MAPPA', 'MAPPA', 'JP', 2011, 'animation'),
  ('WIT STUDIO', 'WIT动画', 'JP', 2012, 'animation'),
  ('BONES', '骨头社', 'JP', 1998, 'animation');
INSERT INTO studios (name, name_zh, country_id, founded, kind) VALUES
  ('ufotable', '幽浮社', 'JP', 2000, 'animation'),
  ('ぴえろ / Pierrot', '小丑社', 'JP', 1979, 'animation'),
  ('カラー / khara', 'khara', 'JP', 2006, 'animation'),
  ('A-1 Pictures', 'A-1 Pictures', 'JP', 2005, 'animation'),
  ('Pixar Animation Studios', '皮克斯', 'US', 1986, 'animation'),
  ('Sony Pictures Animation', '索尼动画', 'US', 2002, 'animation'),
  ('Walt Disney Pictures', '迪士尼影片', 'US', 1983, 'film'),
  ('Warner Bros. Pictures', '华纳兄弟', 'US', 1923, 'film'),
  ('Marvel Studios', '漫威影业', 'US', 1993, 'film'),
  ('Columbia Pictures', '哥伦比亚影业', 'US', 1918, 'film'),
  ('Miramax', '米拉麦克斯', 'US', 1979, 'film'),
  ('20th Century Studios', '二十世纪影业', 'US', 1935, 'film'),
  ('Nintendo', '任天堂', 'JP', 1889, 'game'),
  ('Bandai Namco Entertainment', '万代南梦宫', 'JP', 2006, 'game'),
  ('FromSoftware', 'FromSoftware', 'JP', 1986, 'game'),
  ('CAPCOM', '卡普空', 'JP', 1979, 'game'),
  ('Square Enix', '史克威尔·艾尼克斯', 'JP', 1975, 'game'),
  ('ATLUS', 'Atlus', 'JP', 1986, 'game'),
  ('CD PROJEKT RED', 'CD Projekt Red', 'PL', 2002, 'game'),
  ('miHoYo / HoYoverse', '米哈游', 'CN', 2012, 'game'),
  ('Mojang Studios', 'Mojang', 'SE', 2009, 'game'),
  ('Team Cherry', 'Team Cherry', 'AU', 2014, 'game');

-- IP 系列
INSERT INTO franchises (name, name_zh, first_year, description) VALUES
  ('One Piece', '海贼王', 1997, '尾田栄一郎的日本超长篇少年漫,讲述路飞与草帽一伙寻找ONE PIECE的冒险'),
  ('Dragon Ball', '龙珠', 1984, '鸟山明经典战斗漫画,赛亚人孙悟空守护地球的故事'),
  ('Naruto', '火影忍者', 1999, '岸本齐史笔下的忍者世界,鸣人立志成为火影'),
  ('Demon Slayer', '鬼灭之刃', 2016, '灶门兄妹在鬼舞辻无惨肆虐的世界的猎鬼物语'),
  ('Attack on Titan', '进击的巨人', 2009, '墙内人类与巨人的生存战争'),
  ('Neon Genesis Evangelion', '新世纪福音战士', 1995, '庵野秀明的心理/机甲名作'),
  ('Mobile Suit Gundam', '机动战士高达', 1979, '高达系列开山之作'),
  ('Marvel Cinematic Universe', '漫威电影宇宙', 2008, 'MCU超级英雄电影宇宙'),
  ('Star Wars', '星球大战', 1977, '乔治·卢卡斯的太空歌剧传奇'),
  ('Harry Potter', '哈利·波特', 1997, 'J.K.罗琳的魔法世界'),
  ('The Lord of the Rings', '指环王', 1954, '托尔金笔下的中土大陆'), 
  ('The Legend of Zelda', '塞尔达传说', 1986, '宫本茂开创的动作冒险系列'),
  ('Super Mario', '超级马力欧', 1985, '任天堂招牌平台跳跃系列'),
  ('Final Fantasy', '最终幻想', 1987, '史克威尔国民级 RPG 系列'),
  ('Dark Souls', '黑暗之魂', 2009, '宫崎英高的高难度魂系代表作'),
  ('Persona', '女神异闻录', 1996, 'Atlus 校园 × 心理 RPG'),
  ('Genshin Impact', '原神', 2020, '米哈游开放世界 RPG'),
  ('Spy × Family', '间谍过家家', 2019, '间谍、杀手与超能力者的临时家庭喜剧');

-- 平台
INSERT INTO platforms (name, kind, owner) VALUES
  ('Theaters', 'theater', NULL),
  ('Netflix', 'streaming', 'Netflix'),
  ('Crunchyroll', 'streaming', 'Sony'),
  ('Disney+', 'streaming', 'Walt Disney'),
  ('Steam', 'pc', 'Valve'),
  ('Epic Games Store', 'pc', 'Epic Games'),
  ('GOG.com', 'pc', 'CD Projekt'),
  ('PlayStation Network', 'console', 'Sony'),
  ('Xbox Store', 'console', 'Microsoft'),
  ('Nintendo eShop', 'console', 'Nintendo'),
  ('App Store', 'mobile', 'Apple'),
  ('Google Play', 'mobile', 'Google'),
  ('TV Broadcasting', 'tv', NULL),
  ('Hulu', 'streaming', 'Walt Disney');

-- ---------- 影人/创作者/声优 ----------

INSERT INTO people (name_en, name_native, name_zh, gender, country_id, birth_date, death_date, occupation, biography) VALUES
  ('Eiichiro Oda', '尾田栄一郎', '尾田荣一郎', 'male', 'JP', '1975-01-01', NULL, 'author', '海贼王作者。'),
  ('Mayumi Tanaka', '田中真弓', '田中真弓', 'female', 'JP', '1955-01-15', NULL, 'voice_actor,actor', '蒙奇·D·路飞声优。'),
  ('Akira Toriyama', '鳥山明', '鸟山明', 'male', 'JP', '1955-04-05', '2024-03-01', 'author,artist', '龙珠作者。'),
  ('Masashi Kishimoto', '岸本斉史', '岸本齐史', 'male', 'JP', '1974-11-08', NULL, 'author', '火影忍者作者。'),
  ('Hayao Miyazaki', '宮崎駿', '宫崎骏', 'male', 'JP', '1941-01-05', NULL, 'director,author,artist', '吉卜力灵魂人物,奥斯卡得主。'),
  ('Makoto Shinkai', '新海誠', '新海诚', 'male', 'JP', '1973-02-09', NULL, 'director,author', '你的名字导演。'),
  ('Hideaki Anno', '庵野秀明', '庵野秀明', 'male', 'JP', '1960-05-22', NULL, 'director,screenwriter', 'EVA 导演。'),
  ('Koyoharu Gotouge', '吾峠呼世晴', '吾峠呼世晴', 'unknown', 'JP', '1989-05-05', NULL, 'author', '鬼灭之刃作者。'),
  ('Hajime Isayama', '諫山創', '谏山创', 'male', 'JP', '1986-08-29', NULL, 'author', '进击的巨人作者。'),
  ('Hiromu Arakawa', '荒川弘', '荒川弘', 'female', 'JP', '1973-05-08', NULL, 'author', '钢之炼金术师作者。'),
  ('Christopher Nolan', 'クリストファー・ノーラン', '克里斯托弗·诺兰', 'male', 'GB', '1970-07-30', NULL, 'director,screenwriter,producer', '盗梦空间/星际穿越导演。'),
  ('James Cameron', 'ジェームズ・キャメロン', '詹姆斯·卡梅隆', 'male', 'CA', '1954-08-16', NULL, 'director,producer', '泰坦尼克号/阿凡达导演。'),
  ('Frank Darabont', 'フランク・ダラボン', '弗兰克·德拉邦特', 'male', 'FR', '1959-01-28', NULL, 'director,screenwriter', '肖申克的救赎导演。'),
  ('Francis Ford Coppola', 'フランシス・コッポラ', '弗朗西斯·福特·科波拉', 'male', 'US', '1939-04-07', NULL, 'director,screenwriter', '教父导演。'),
  ('George Lucas', 'ジョージ・ルーカス', '乔治·卢卡斯', 'male', 'US', '1944-05-14', NULL, 'director,screenwriter', '星球大战之父。'),
  ('Quentin Tarantino', 'クエンティン・タランティーノ', '昆汀·塔伦蒂诺', 'male', 'US', '1963-03-27', NULL, 'director,screenwriter', '低俗小说导演。'),
  ('Steven Spielberg', 'スティーヴン・スピルバーグ', '史蒂文·斯皮尔伯格', 'male', 'US', '1946-12-18', NULL, 'director,producer', '好莱坞传奇导演。'),
  ('Walt Disney', 'ウォルト・ディズニー', '沃尔特·迪士尼', 'male', 'US', '1901-12-05', '1966-12-15', 'director,producer', '迪士尼创始人。'),
  ('Leonardo DiCaprio', 'レオナルド・ディカプリオ', '莱昂纳多·迪卡普里奥', 'male', 'US', '1974-11-11', NULL, 'actor,producer', '泰坦尼克号/盗梦空间男主角。'),
  ('Tom Hanks', 'トム・ハンクス', '汤姆·汉克斯', 'male', 'US', '1956-07-09', NULL, 'actor,producer', '阿甘正传主演。'),
  ('Shigeru Miyamoto', '宮本茂', '宫本茂', 'male', 'JP', '1952-11-16', NULL, 'game_director,artist', '马里奥/塞尔达之父。'),
  ('Hidetaka Miyazaki', '宮崎英高', '宫崎英高', 'male', 'JP', '1974-09-19', NULL, 'game_director', '魂系创始人。'),
  ('Hironobu Sakaguchi', '坂口博信', '坂口博信', 'male', 'JP', '1962-11-25', NULL, 'game_director', '最终幻想之父。'),
  ('Markus Persson', 'マルクス・ペルソン', '马库斯·佩尔松', 'male', 'SE', '1979-06-01', NULL, 'game_director,engineer', 'Minecraft 创始人(Notch)。'),
  ('Yui Ishikawa', '石川由依', '石川由依', 'female', 'JP', '1989-05-30', NULL, 'voice_actor,actor', '三笠·阿克曼声优。'),
  ('Kana Hanazawa', '花澤香菜', '花泽香菜', 'female', 'JP', '1989-02-25', NULL, 'voice_actor', '日本知名声优。'),
  ('Hiroshi Kamiya', '神谷浩史', '神谷浩史', 'male', 'JP', '1975-01-28', NULL, 'voice_actor', '冈部伦太郎声优。'),
  ('Rie Takahashi', '高橋李依', '高桥李依', 'female', 'JP', '1994-02-27', NULL, 'voice_actor', '艾米莉亚声优。'),
  ('Hideo Kojima', '小島秀夫', '小岛秀夫', 'male', 'JP', '1963-08-24', NULL, 'game_director', '合金装备/死亡搁浅制作人。'),
  ('Nobuo Uematsu', '植松伸夫', '植松伸夫', 'male', 'JP', '1959-03-21', NULL, 'composer', '最终幻想配乐大师。'),
  ('Joe Hisaishi', '久石譲', '久石让', 'male', 'JP', '1950-12-06', NULL, 'composer', '宫崎骏电影御用配乐。');

-- 批量影人（含多语言名）
INSERT INTO people (name_en, name_native, name_zh, gender, country_id, birth_date, death_date, occupation, biography)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 470
)
SELECT
  ELT(1 + (i % 5),
      CONCAT('Actor ', i + 100),
      CONCAT('声優 ', i + 100),
      CONCAT('Актёр ', i + 100),
      CONCAT('Director ', i + 100),
      CONCAT('ゲーム開発者 ', i + 100)),
  CONCAT('Cineast ', i + 100),
  CONCAT('演示影人 ', i + 100),
  ELT(1 + (i % 3), 'female', 'male', 'unknown'),
  ELT(1 + (i % 13), 'CN','JP','US','KR','GB','FR','DE','IT','RU','PL','CA','AU','SE'),
  DATE_ADD('1960-01-01', INTERVAL (i * 137) DAY),
  NULL,
  ELT(1 + (i % 6), 'actor', 'director', 'voice_actor,actor', 'composer', 'screenwriter', 'producer,actor'),
  ELT(1 + (i % 4), 'An experienced performer with a wide range.',
                    '身经百战的实力派演员。',
                    'Опытный исполнитель широкого профиля.',
                    'Experientia peritus histrio.')
FROM seq;

-- 批量影人别名
INSERT INTO people_aliases (people_id, alias, lang, kind)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 100
)
SELECT
  1 + (i % 31),
  ELT(1 + (i % 6),
      CONCAT('Alias-', i),
      CONCAT('艺名', i),
      CONCAT('別名', i),
      CONCAT('Псевдоним ', i),
      CONCAT('Nom ', i),
      CONCAT('キッチネーム', i)),
  ELT(1 + (i % 5), 'en', 'zh', 'ja', 'ru', 'la'),
  ELT(1 + (i % 4), 'stage_name', 'nickname', 'pen_name', 'romanized')
FROM seq;

-- ---------- 作品 ----------

-- 手写知名作品（影视/动画/游戏）
INSERT INTO works
  (id, kind, title, title_zh, original_lang, country_id, franchise_id, release_year,
   premiere_date, runtime, maturity, score, votes, status, synopsis,
   budget_usd, revenue_usd, msrp, is_animation, uuid, metadata) VALUES
  (1,  'anime', 'ONE PIECE', '海贼王', 'ja', 'JP', 1, 1999, '1999-10-20', 24, '12',  8.71, 2100000, 'airing',
    '蒙奇·D·路飞和他的草帽海贼团追寻传说中的大秘宝 ONE PIECE 的伟大冒险。',
    30000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111101',
    JSON_OBJECT('seasons', 20, 'episodes', 1100, 'network', 'フジテレビ', 'tags', JSON_ARRAY('pirate','adventure','shounen'))),
  (2,  'anime', 'NARUTO', '火影忍者', 'ja', 'JP', 3, 2002, '2002-10-03', 24, '12', 8.20, 1500000, 'released',
    '忍者村的吊车尾漩涡鸣人立志成为火影的成长之旅。',
    25000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111102',
    JSON_OBJECT('seasons', 9, 'episodes', 720, 'tags', JSON_ARRAY('ninja','coming-of-age'))),
  (3,  'anime', 'DRAGON BALL', '龙珠', 'ja', 'JP', 2, 1986, '1986-02-26', 24, 'All', 8.30, 1300000, 'released',
    '收集龙珠许愿的冒险,以及孙悟空不断变强的战斗史诗。',
    20000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111103', NULL),
  (4,  'anime', '鬼滅の刃', '鬼灭之刃', 'ja', 'JP', 4, 2019, '2019-04-06', 24, '15', 8.60, 1800000, 'airing',
    '灶门炭治郎为拯救变成鬼的妹妹,加入鬼杀队讨伐恶鬼。',
    22000000.00, 5000000000.00, NULL, TRUE, '11111111-1111-1111-1111-111111111104',
    JSON_OBJECT('studio', 'ufotable', 'box_office', '史上最大の爆発的ヒット', 'tags', JSON_ARRAY('demon','sword-fighting'))),
  (5,  'anime', '進撃の巨人', '进击的巨人', 'ja', 'JP', 5, 2013, '2013-04-07', 24, '18', 8.80, 1900000, 'released',
    '墙内人类面对巨人威胁而觉醒的战斗与自由。',
    24000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111105',
    JSON_OBJECT('manga', 34, 'volumes', 34, 'tags', JSON_ARRAY('titan','freedom'))),
  (6,  'anime', '新世紀エヴァンゲリオン', '新世纪福音战士', 'ja', 'JP', 6, 1995, '1995-10-04', 24, '15', 8.40, 700000, 'released',
    '少年驾驶巨大人形兵器迎战使徒,心理创伤与救赎的物语。',
    8000000.00, 150000000.00, NULL, TRUE, '11111111-1111-1111-1111-111111111106', NULL),
  (7,  'anime', 'となりのトトロ', '龙猫', 'ja', 'JP', NULL, 1988, '1988-04-16', 86, 'G', 8.20, 900000, 'released',
    '小月与小梅姐妹在乡间与龙猫邂逅的治愈童话。',
    5000000.00, 20000000.00, NULL, TRUE, '11111111-1111-1111-1111-111111111107',
    JSON_OBJECT('director', '宮崎駿', 'music', '久石譲', 'tags', JSON_ARRAY('neighborhood','fantasy'))),
  (8,  'anime', '千と千尋の神隠し', '千与千寻', 'ja', 'JP', NULL, 2001, '2001-07-20', 125, 'G', 8.80, 2300000, 'released',
    '少女千寻误入神灵世界,在汤屋打工寻找回家之路。',
    19000000.00, 395000000.00, NULL, TRUE, '11111111-1111-1111-1111-111111111108',
    JSON_OBJECT('oscar', 'Best Animated Feature', 'tags', JSON_ARRAY('spirits','coming-of-age'))),
  (9,  'anime', 'もののけ姫', '幽灵公主', 'ja', 'JP', NULL, 1997, '1997-07-12', 134, 'PG-13', 8.40, 1100000, 'released',
    '人与自然冲突的宏阔史诗,阿席达卡与珊的相遇。',
    23500000.00, 190000000.00, NULL, TRUE, '11111111-1111-1111-1111-111111111109', NULL),
  (10, 'anime', '鋼の錬金術師 FULLMETAL ALCHEMIST', '钢之炼金术师', 'ja', 'JP', NULL, 2009, '2009-04-05', 24, 'PG-13', 9.10, 1600000, 'released',
    '兄弟二人为取回失去的身体踏上寻找贤者之石的旅程。',
    20000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111110', NULL),
  (11, 'anime', 'ワンパンマン', '一拳超人', 'ja', 'JP', NULL, 2015, '2015-10-05', 24, 'PG-13', 8.50, 1200000, 'released',
    '一拳就能打倒任何敌人的埼玉的都市英雄喜剧。',
    10000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111111', NULL),
  (12, 'anime', '呪術廻戦', '咒术回战', 'ja', 'JP', NULL, 2020, '2020-10-03', 24, '15', 8.60, 1500000, 'airing',
    '虎杖悠仁吞下特级咒物后卷入咒术师与咒灵的战斗。',
    18000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111112', NULL),
  (13, 'anime', 'シュタインズ・ゲート', '命运石之门', 'ja', 'JP', NULL, 2011, '2011-04-06', 24, 'PG-13', 9.00, 800000, 'released',
    '疯狂科学家冈部伦太郎发现时空跳跃的装置。',
    9000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111113', NULL),
  (14, 'anime', 'SPY×FAMILY', '间谍过家家', 'ja', 'JP', 18, 2022, '2022-04-09', 24, 'All', 8.10, 1100000, 'airing',
    '间谍黄昏、杀手约尔与超能力女孩阿尼亚组成的临时家庭。',
    12000000.00, 0.00, NULL, TRUE, '11111111-1111-1111-1111-111111111114', NULL),
  (15, 'film', '君の名は。', '你的名字。', 'ja', 'JP', NULL, 2016, '2016-08-26', 106, 'PG', 8.40, 1900000, 'released',
    '互换身体的少年泷与少女三叶跨越时空的思念。',
    21000000.00, 380000000.00, NULL, TRUE, '11111111-1111-1111-1111-111111111115', NULL),
  (16, 'film', 'Inception', '盗梦空间', 'en', 'US', NULL, 2010, '2010-07-16', 148, 'PG-13', 8.80, 2500000, 'released',
    '盗梦团队深入多重梦境植入意念。',
    160000000.00, 837000000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111116', NULL),
  (17, 'film', 'Titanic', '泰坦尼克号', 'en', 'US', NULL, 1997, '1997-12-19', 195, 'PG-13', 7.90, 2300000, 'released',
    '巨轮沉没之夜,杰克与露丝的生死之恋。',
    200000000.00, 2267000000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111117', NULL),
  (18, 'film', 'The Shawshank Redemption', '肖申克的救赎', 'en', 'US', NULL, 1994, '1994-09-23', 142, 'R', 9.30, 2900000, 'released',
    '含冤入狱的安迪在肖申克监狱中的希望与救赎。',
    25000000.00, 73300000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111118', NULL),
  (19, 'film', 'The Godfather', '教父', 'en', 'US', NULL, 1972, '1972-03-24', 175, 'R', 9.20, 2000000, 'released',
    '柯里昂家族的权力继承与黑帮史诗。',
    6000000.00, 250000000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111119', NULL),
  (20, 'film', 'Star Wars: Episode IV - A New Hope', '星球大战：新希望', 'en', 'US', 9, 1977, '1977-05-25', 121, 'PG', 8.60, 1400000, 'released',
    '卢克·天行者加入义军对抗帝国的太空歌剧开篇。',
    11000000.00, 775000000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111120', NULL),
  (21, 'film', 'Avengers: Endgame', '复仇者联盟4：终局之战', 'en', 'US', 8, 2019, '2019-04-26', 181, 'PG-13', 8.40, 1300000, 'released',
    '复仇者联盟集结逆转灭霸的响指。',
    356000000.00, 2798000000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111121', NULL),
  (22, 'film', 'The Lord of the Rings: The Return of the King', '指环王：王者无敌', 'en', 'US', 11, 2003, '2003-12-17', 201, 'PG-13', 9.00, 1900000, 'released',
    '魔戒远征队完成至尊戒销毁的最终章。',
    94000000.00, 1142000000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111122', NULL),
  (23, 'film', 'Pulp Fiction', '低俗小说', 'en', 'US', NULL, 1994, '1994-10-14', 154, 'R', 8.90, 2100000, 'released',
    '昆汀式环形叙事的黑帮黑色喜剧。',
    8000000.00, 214000000.00, NULL, FALSE, '11111111-1111-1111-1111-111111111123', NULL),
  (24, 'game', 'The Legend of Zelda: Breath of the Wild', '塞尔达传说 旷野之息', 'en', 'JP', 12, 2017, '2017-03-03', NULL, 'E10+', 9.60, 3400000, 'released',
    '林克从百年沉睡中醒来,在海拉鲁大陆对抗灾厄盖侬。',
    0.00, 0.00, 79.99, FALSE, '11111111-1111-1111-1111-111111111124',
    JSON_OBJECT('platforms', JSON_ARRAY('Switch','Wii U'), 'gdc_award', 'Game of the Year')),
  (25, 'game', 'FINAL FANTASY VII', '最终幻想7', 'en', 'JP', 14, 1997, '1997-01-31', NULL, 'T', 9.20, 1500000, 'released',
    '克劳德对抗神罗与萨菲罗斯的科幻名作。',
    45000000.00, 0.00, 49.99, FALSE, '11111111-1111-1111-1111-111111111125', NULL),
  (26, 'game', 'Elden Ring', '艾尔登法环', 'en', 'JP', 15, 2022, '2022-02-25', NULL, 'M', 9.60, 2900000, 'released',
    '褪色者穿越交界地追寻艾尔登法环。',
    100000000.00, 1400000000.00, 59.99, FALSE, '11111111-1111-1111-1111-111111111126', NULL),
  (27, 'game', 'Minecraft', '我的世界', 'en', 'SE', NULL, 2011, '2011-11-18', NULL, 'E', 8.90, 4200000, 'released',
    '无限沙盒中的建造、探索与生存。',
    0.00, 0.00, 26.95, FALSE, '11111111-1111-1111-1111-111111111127', NULL),
  (28, 'game', 'Super Mario Bros.', '超级马力欧兄弟', 'en', 'JP', 13, 1985, '1985-09-13', NULL, 'E', 8.80, 1900000, 'released',
    '马力欧穿越蘑菇王国营救公主的舞台系列开山作。',
    0.00, 0.00, 4.99, FALSE, '11111111-1111-1111-1111-111111111128', NULL),
  (29, 'game', 'Genshin Impact', '原神', 'zh', 'CN', 17, 2020, '2020-09-28', NULL, 'T', 8.50, 3100000, 'airing',
    '旅行者在提瓦特大陆寻找失散亲人的开放世界。',
    100000000.00, 5000000000.00, 0.00, FALSE, '11111111-1111-1111-1111-111111111129',
    JSON_OBJECT('platforms', JSON_ARRAY('PC','PS5','iOS','Android'), 'gacha', TRUE)),
  (30, 'game', 'Persona 5', '女神异闻录5', 'en', 'JP', 16, 2016, '2016-09-15', NULL, 'M', 9.40, 1200000, 'released',
    '东京少年少女以怪盗身份潜入心灵宫殿对抗扭曲欲望。',
    30000000.00, 0.00, 59.99, FALSE, '11111111-1111-1111-1111-111111111130', NULL);

-- 批量作品（多语言标题）：270 批量 + 30 手写 = 300，kind 覆盖 4 类
INSERT INTO works
  (id, kind, title, title_zh, original_lang, country_id, franchise_id, release_year,
   premiere_date, runtime, maturity, score, votes, status, synopsis,
   budget_usd, revenue_usd, msrp, is_animation, uuid, metadata)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 270
)
SELECT
  30 + i,
  ELT(1 + (i % 4), 'film', 'series', 'anime', 'game'),
  ELT(1 + (i % 5),
      CONCAT('Chronicle of Ages ', i),
      CONCAT('时代编年史 ', i),
      CONCAT('時代のクロニクル ', i),
      CONCAT('Хроника эпох ', i),
      CONCAT('Annales Temporum ', i)),
  CONCAT('演示作品', 30 + i),
  ELT(1 + (i % 4), 'en', 'ja', 'zh', 'ru'),
  ELT(1 + (i % 13), 'CN','JP','US','KR','GB','FR','DE','IT','RU','PL','CA','AU','SE'),
  CASE WHEN i % 7 = 0 THEN NULL ELSE 1 + (i % 18) END,
  1985 + (i % 40),
  CASE WHEN i % 5 = 0 THEN NULL ELSE DATE_ADD('1985-01-01', INTERVAL (i * 90) DAY) END,
  CASE WHEN i % 4 = 0 THEN NULL ELSE 90 + (i % 60) END,
  ELT(1 + (i % 9), 'G','PG','PG-13','R','All','12','15','18','NC-17'),
  ROUND(5.5 + (i % 40) / 10.0, 2),
  (i % 7 + 1) * 10000,
  ELT(1 + (i % 5), 'released', 'released', 'released', 'cancelled', 'in_development'),
  ELT(1 + (i % 4),
      CONCAT('The story of work number ', 30 + i, '.'),
      CONCAT('第 ', 30 + i, ' 号作品的剧情简介。'),
      CONCAT('作品 ', 30 + i, ' のあらすじ。'),
      CONCAT('Сюжет произведения №', 30 + i, '.')),
  ROUND(RAND() * 200000000, 2),
  ROUND(RAND() * 500000000, 2),
  CASE WHEN (30 + i) % 4 = 1 THEN ROUND(RAND() * 60 + 10, 2) ELSE NULL END,
  (i % 3 = 1),
  UUID(),
  CASE WHEN i % 3 = 0 THEN NULL ELSE JSON_OBJECT('tags', JSON_ARRAY(ELT(1+(i%4),'action','drama','adventure','rpg'), i)) END
FROM seq;

-- 多语言标题（全部作品 × 5 语言）
INSERT INTO work_titles (work_id, lang, title)
SELECT w.id, t.lang,
  CASE t.lang
    WHEN 'zh' THEN w.title_zh
    WHEN 'ja' THEN CONCAT('『', w.title, '』')
    WHEN 'ru' THEN CONCAT(w.title, ' — Мир, где оживают истории')
    WHEN 'la' THEN CONCAT('Opus Temporum ', w.id)
    ELSE w.title
  END
FROM works w
CROSS JOIN (SELECT 'en' AS lang UNION ALL SELECT 'zh' UNION ALL SELECT 'ja' UNION ALL SELECT 'ru' UNION ALL SELECT 'la') t
ORDER BY w.id, t.lang;

-- 作品-题材
INSERT INTO work_genres (work_id, genre_id)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 300
)
SELECT
  1 + (i % 300),
  1 + ((i * 7) % 14)
FROM seq;

-- 作品-制作公司
INSERT INTO work_studios (work_id, studio_id, role)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 350
)
SELECT
  1 + (i % 300),
  1 + ((i * 3) % 28),
  ELT(1 + (i % 4), 'production', 'animation', 'publisher', 'developer')
FROM seq;

-- 作品-主创（手写明星组）
INSERT INTO work_people (work_id, people_id, role) VALUES
  (1, 1, 'screenwriter'),  (1, 2, 'voice_actor'),
  (2, 4, 'screenwriter'),
  (3, 3, 'screenwriter'),
  (4, 8, 'screenwriter'),
  (5, 9, 'screenwriter'),  (5, 25, 'voice_actor'),
  (6, 7, 'director'),
  (7, 5, 'director'),      (7, 31, 'composer'),
  (8, 5, 'director'),      (8, 31, 'composer'),
  (9, 5, 'director'),      (9, 31, 'composer'),
  (10, 10, 'screenwriter'),
  (13, 27, 'voice_actor'),
  (15, 6, 'director'),
  (16, 11, 'director'),    (16, 19, 'actor'),
  (17, 12, 'director'),    (17, 19, 'actor'),
  (18, 13, 'director'),
  (19, 14, 'director'),
  (20, 15, 'director'),
  (21, 16, 'director'),
  (23, 16, 'director'),
  (24, 21, 'game_director'),
  (25, 23, 'game_director'), (25, 30, 'composer'),
  (26, 22, 'game_director'),
  (27, 24, 'game_director'),
  (28, 21, 'game_director'),
  (29, 24, 'game_director'),
  (30, 22, 'game_director');

-- 作品-主创（批量）：INSERT IGNORE 防与手写行重复
INSERT IGNORE INTO work_people (work_id, people_id, role)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 900
)
SELECT
  1 + ((i * 7) % 300),
  1 + ((i * 13) % 31),
  ELT(1 + (i % 5), 'director', 'producer', 'screenwriter', 'composer', 'designer')
FROM seq;

-- ---------- 季/集 ----------

-- 季度（仅动画/剧集类型）
INSERT INTO seasons (work_id, season_no, title, premiere, finale, episode_count)
SELECT w.id, s.n,
  CONCAT('Season ', s.n),
  DATE_ADD(MAKEDATE(w.release_year, 1), INTERVAL (s.n - 1) * 365 DAY),
  DATE_ADD(DATE_ADD(MAKEDATE(w.release_year, 1), INTERVAL (s.n - 1) * 365 DAY), INTERVAL 100 DAY),
  8 + (s.n * 3) % 8
FROM works w
CROSS JOIN (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6) s
WHERE w.kind IN ('anime', 'series');

-- 分集（演示 BIT / TIME / BIGINT）
INSERT INTO episodes (season_id, ep_no, title, air_date, air_time, duration_min, summary, viewership, is_omake)
SELECT s.id, ep.n,
  CONCAT('Episode ', ep.n),
  DATE_ADD(s.premiere, INTERVAL (ep.n - 1) * 7 DAY),
  SEC_TO_TIME(1380 + (ep.n % 8) * 60),
  21 + (ep.n % 12),
  CONCAT('第', ep.n, '集剧情概要 / Episode ', ep.n, ' summary'),
  FLOOR(RAND() * 9000000) + 500000,
  IF(ep.n % 11 = 0, 1, 0)
FROM seasons s
CROSS JOIN (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
            UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
            UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14) ep;

-- ---------- 角色 ----------

INSERT INTO characters (id, work_id, name, name_ja, name_zh, name_ru, species, role, description, is_main) VALUES
  (1,  1,  'Monkey D. Luffy',  'モンキー・D・ルフィ',  '蒙奇·D·路飞',  'Монки Д. Луффи',    'Homo sapiens (Devil Fruit user)', 'protagonist',  '草帽海贼团船长,橡胶果实能力者,目标是成为海贼王。', TRUE),
  (2,  1,  'Roronoa Zoro',     'ロロノア・ゾロ',        '罗罗诺亚·索隆', 'Ророноа Зоро',      'Homo sapiens', 'deuteragonist', '三刀流剑士,立志成为世界第一大剑豪。', TRUE),
  (3,  1,  'Nami',             'ナミ',                 '娜美',         'Нами',              'Homo sapiens', 'deuteragonist', '草帽一伙航海士。', TRUE),
  (4,  3,  'Son Goku',         '孫悟空',               '孙悟空',       'Сон Гоку',          'Saiyan',        'protagonist',   '来自贝吉塔行星的赛亚人,战斗民族最强战士。', TRUE),
  (5,  3,  'Vegeta',           'ベジータ',             '贝吉塔',       'Вегета',            'Saiyan',        'antagonist',    '赛亚人王子,后期成为伙伴。', TRUE),
  (6,  2,  'Naruto Uzumaki',   'うずまきナルト',        '漩涡鸣人',     'Наруто Удзумаки',   'Homo sapiens (Jinchuriki)', 'protagonist', '九尾人柱力,第七班成员,梦想成为火影。', TRUE),
  (7,  2,  'Sasuke Uchiha',    'うちはサスケ',          '宇智波佐助',   'Саске Учиха',       'Homo sapiens',  'antagonist',    '宇智波一族的遗孤,走向复仇之路。', TRUE),
  (8,  2,  'Sakura Haruno',    '春野サクラ',           '春野樱',       'Сакура Харуно',     'Homo sapiens',  'supporting',    '医疗忍者,七班的一员。', TRUE),
  (9,  4,  'Tanjiro Kamado',   '竈門炭治郎',           '灶门炭治郎',   'Тандзиро Камадо',   'Homo sapiens',  'protagonist',   '鬼杀队剑士,为让妹妹变回人类而战斗。', TRUE),
  (10, 4,  'Nezuko Kamado',    '竈門禰豆子',           '灶门祢豆子',   'Нэдзуко Камадо',    'Demon (Oni)',   'supporting',    '变成鬼的炭治郎之妹。', TRUE),
  (11, 5,  'Eren Yeager',      'エレン・イェーガー',    '艾伦·耶格尔',  'Эрен Йегер',        'Homo sapiens (Titan)', 'protagonist', '进击的巨人继承者。', TRUE),
  (12, 5,  'Mikasa Ackerman',  'ミカサ・アッカーマン',  '三笠·阿克曼',  'Микаса Аккерман',   'Homo sapiens (Ackermann)', 'deuteragonist', '立体机动装置达人,艾伦的青梅竹马。', TRUE),
  (13, 7,  'Totoro',           'トトロ',               '龙猫',         'Тоторо',            'Spirit of the Forest', 'supporting', '森林精灵,孩子们的朋友。', TRUE),
  (14, 8,  'Chihiro Ogino',    '荻野千尋',             '荻野千寻',     'Тихиро Огино',      'Homo sapiens',  'protagonist',   '误入神灵世界打工的少女。', TRUE),
  (15, 8,  'Haku',             'ハク',                '白龙',         'Хаку',              'River Spirit',  'deuteragonist', '汤屋的少年,实为琥珀川的河神。', TRUE),
  (16, 8,  'No Face',          '顔なし',               '无脸男',       'Безликий',          'Yokai',         'supporting',    '安静而孤独的妖怪。', TRUE),
  (17, 9,  'San',              'サン',                '珊',           'Сан',               'Homo sapiens (raised by wolves)', 'protagonist', '被狼神养大的少女。', TRUE),
  (18, 9,  'Ashitaka',         'アシタカ',             '阿席达卡',     'Аситака',           'Homo sapiens',  'deuteragonist', '被诅咒的青年,寻求解除诅咒之法。', TRUE),
  (19, 10, 'Edward Elric',     'エドワード・エルリック','爱德华·艾尔利克', 'Эдвард Элрик',   'Homo sapiens',  'protagonist',   '钢之炼金术师。', TRUE),
  (20, 10, 'Alphonse Elric',   'アルフォンス・エルリック','阿尔冯斯·艾尔利克', 'Альфонс Элрик', 'Armor (Soul bound)', 'deuteragonist', '爱德华之弟,灵魂寄宿于铠甲。', TRUE),
  (21, 6,  'Shinji Ikari',     '碇シンジ',             '碇真嗣',       'Синдзи Икари',      'Homo sapiens',  'protagonist',   'EVA 初号机驾驶员。', TRUE),
  (22, 6,  'Rei Ayanami',      '綾波レイ',             '绫波丽',       'Рей Аянами',        'Homo sapiens',  'supporting',    'EVA 零号机驾驶员。', TRUE),
  (23, 6,  'Asuka Langley',    '惣流・アスカ・ラングレー','惣流·明日香·兰格雷', 'Аска Лэнгли',   'Homo sapiens',  'supporting',    'EVA 二号机驾驶员。', TRUE),
  (24, 11, 'Saitama',          'サイタマ',             '埼玉',         'Сайтама',           'Homo sapiens',  'protagonist',   '一拳打爆一切的英雄。', TRUE),
  (25, 12, 'Satoru Gojo',      '五条悟',               '五条悟',       'Сатору Годзё',      'Homo sapiens',  'supporting',    '咒术界最强术师。', TRUE),
  (26, 12, 'Yuji Itadori',     '虎杖悠仁',             '虎杖悠仁',     'Юдзи Итадори',      'Homo sapiens',  'protagonist',   '宿傩的宿主。', TRUE),
  (27, 12, 'Ryomen Sukuna',    '両面宿儺',             '两面宿傩',     'Рёмен Сукуна',      'Cursed Spirit', 'antagonist',    '诅咒之王。', TRUE),
  (28, 13, 'Okabe Rintaro',    '岡部倫太郎',           '冈部伦太郎',   'Ринтаро Окабэ',     'Homo sapiens',  'protagonist',   '自称疯狂科学家的电话微波炉发明者。', TRUE),
  (29, 13, 'Kurisu Makise',    '牧瀬紅莉栖',           '牧濑红莉栖',   'Курису Макисэ',     'Homo sapiens',  'deuteragonist', '天才少女,时间旅行理论专家。', TRUE),
  (30, 14, 'Anya Forger',      'アーニャ・フォージャー','阿尼亚·福杰', 'Аня Форджер',       'Homo sapiens (esper)', 'protagonist', '能读心的超能力少女。', TRUE),
  (31, 14, 'Loid Forger',      'ロイド・フォージャー',  '黄昏（罗伊德·福杰）','Лоид Форджер','Homo sapiens', 'deuteragonist', '代号黄昏的西国间谍。', TRUE),
  (32, 15, 'Taki Tachibana',   '立花瀧',               '立花泷',       'Таки Татибана',     'Homo sapiens',  'protagonist',   '东京的高中生。', TRUE),
  (33, 15, 'Mitsuha Miyamizu', '宮水三葉',             '宫水三叶',     'Мицуха Миямадзу',   'Homo sapiens',  'deuteragonist', '糸守町的巫女高中生。', TRUE),
  (34, 16, 'Dom Cobb',         'ドム・コブ',           '多姆·柯布',    'Дом Кобб',          'Homo sapiens',  'protagonist',   '梦境窃贼。', TRUE),
  (35, 17, 'Jack Dawson',      'ジャック・ドーソン',    '杰克·道森',    'Джек Доусон',       'Homo sapiens',  'protagonist',   '泰坦尼克号上的穷画家。', TRUE),
  (36, 17, 'Rose DeWitt Bukater','ローズ・デウィット・ブカター','露丝·迪威特·布卡特', 'Роза Девитт', 'Homo sapiens','deuteragonist','富家小姐,与杰克相恋。', TRUE),
  (37, 19, 'Vito Corleone',    'ヴィト・コルレオーネ', '维托·柯里昂', 'Вито Корлеоне',     'Homo sapiens',  'protagonist',   '柯里昂家族教父。', TRUE),
  (38, 19, 'Michael Corleone', 'マイケル・コルレオーネ','迈克·柯里昂','Майкл Корлеоне',    'Homo sapiens',  'deuteragonist', '继承教父之位的幼子。', TRUE),
  (39, 20, 'Luke Skywalker',   'ルーク・スカイウォーカー','卢克·天行者','Люк Скайуокер',  'Homo sapiens',  'protagonist',   '绝地武士。', TRUE),
  (40, 20, 'Darth Vader',      'ダース・ベイダー',     '达斯·维达',    'Дарт Вейдер',       'Human (cyborg)', 'antagonist',  '帝国黑暗尊主。', TRUE),
  (41, 21, 'Tony Stark',       'トニー・スターク',     '托尼·斯塔克',  'Тони Старк',        'Homo sapiens',  'protagonist',   '钢铁侠,复仇者核心。', TRUE),
  (42, 21, 'Thanos',           'サノス',              '灭霸',         'Танос',             'Eternal',       'antagonist',    '收集无限宝石的泰坦人。', TRUE),
  (43, 22, 'Frodo Baggins',    'フロド・バギンズ',     '弗罗多·巴金斯','Фродо Бэггинс',     'Hobbit',        'protagonist',   '持戒人。', TRUE),
  (44, 22, 'Gandalf',          'ガンダルフ',           '甘道夫',       'Гэндальф',          'Maia (Istari)', 'supporting',    '灰袍巫师。', TRUE),
  (45, 24, 'Link',             'リンク',              '林克',         'Линк',              'Hylian',        'protagonist',   '勇者,与盖侬对抗。', TRUE),
  (46, 24, 'Princess Zelda',   'ゼルダ姫',             '塞尔达公主',   'Принцесса Зельда',  'Hylian',        'deuteragonist', '海拉鲁王国的公主。', TRUE),
  (47, 25, 'Cloud Strife',     'クラウド・ストライフ', '克劳德·斯特莱夫','Клауд Страйф',    'Homo sapiens',  'protagonist',   '前神罗特种兵。', TRUE),
  (48, 25, 'Sephiroth',        'セフィロス',           '萨菲罗斯',     'Сефирот',           'Hybrid (Jenova cells)', 'antagonist','神罗英雄,后堕落为反派。', TRUE),
  (49, 26, 'The Tarnished',    '褪色者',              '褪色者',       'Потускневший',      'Tarnished',     'protagonist',   '被引导到交界地的玩家角色。', TRUE),
  (50, 26, 'Ranni the Witch',  '菈妮',                '菈妮',         'Ранни',             'Empyrean (spirit)', 'supporting', '月之女巫,魔女线的关键人物。', TRUE),
  (51, 27, 'Steve',            'スティーブ',           '史蒂夫',       'Стив',              'Human (Block)', 'protagonist',   'Minecraft 默认角色。', TRUE),
  (52, 28, 'Mario',            'マリオ',              '马里奥',       'Марио',             'Human (Mushroom Kingdom)', 'protagonist', '蘑菇王国的水管工英雄。', TRUE),
  (53, 29, 'Aether (Traveler)', '空（旅人）',          '空（旅行者）',  'Айтер',             'Descender',     'protagonist',   '穿越提瓦特的旅行者。', TRUE),
  (54, 29, 'Paimon',           'パイモン',             '派蒙',         'Паймон',            'Unknown (Paimon)', 'supporting', '旅行者的漂浮伙伴。', TRUE),
  (55, 30, 'Joker (Ren Amamiya)', '主人公（雨宮蓮）',   '心之怪盗团团长', 'Джокер',           'Homo sapiens',  'protagonist',   '代号 Joker 的怪盗团长。', TRUE);

-- 批量角色
INSERT INTO characters (work_id, name, name_ja, name_zh, name_ru, species, role, description, is_main)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 395
)
SELECT
  1 + ((i * 7) % 300),
  ELT(1 + (i % 5),
      CONCAT('Character ', i + 100),
      CONCAT('角色', i + 100),
      CONCAT('キャラクター ', i + 100),
      CONCAT('Персонаж ', i + 100),
      CONCAT('Persona ', i + 100)),
  CONCAT('キャラ', i + 100),
  CONCAT('演示角色', i + 100),
  CONCAT('Персонаж-', i + 100),
  ELT(1 + (i % 6), 'Homo sapiens', 'Spirit', 'Yokai', 'Demon', 'Saiyan', 'Hylian'),
  ELT(1 + (i % 5), 'supporting', 'supporting', 'supporting', 'cameo', 'antagonist'),
  CONCAT('演示用角色,位于作品 ', 1 + (i * 7) % 300, ' 中。'),
  FALSE
FROM seq
WHERE i <= 395;

-- 批量角色别名
INSERT INTO character_aliases (character_id, alias, lang)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 450
)
SELECT
  1 + (i % 450),
  ELT(1 + (i % 6),
      CONCAT('Nick-', i),
      CONCAT('外号', i),
      CONCAT('異名', i),
      CONCAT('Прозвище ', i),
      CONCAT('Agnomen ', i),
      CONCAT('どっちの', i)),
  ELT(1 + (i % 6), 'en', 'zh', 'ja', 'ru', 'la', 'es')
FROM seq
WHERE i <= 450;

-- 角色配音
INSERT INTO character_voices (character_id, people_id, lang) VALUES
  (1, 2, 'ja'), (1, 38, 'en'), (4, 3, 'ja'), (12, 25, 'ja'),
  (28, 27, 'ja'), (24, 26, 'ja'), (19, 3, 'ja'), (21, 30, 'ja');

INSERT IGNORE INTO character_voices (character_id, people_id, lang)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 400
)
SELECT
  1 + (i % 450),
  1 + ((i * 11) % 31),
  ELT(1 + (i % 3), 'ja', 'en', 'ru')
FROM seq
WHERE i <= 400;

-- 作品-角色登场
INSERT INTO work_characters (work_id, character_id, guest)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 400
)
SELECT
  1 + ((i * 5) % 300),
  1 + (i % 450),
  (i % 7 = 0)
FROM seq
WHERE i <= 400;

-- 经典台词（手写多语言名场面）
INSERT INTO episode_lines (work_id, character_id, line_native, line_en, line_zh, line_ru, margin_note, lang_of_original) VALUES
  (1,  1, '俺は海賊王になる男だ！！',      'I am the man who is going to become the Pirate King!',
        '我是要成为海贼王的男人！',          'Я стану королём пиратов!', '路飞宣言', 'ja'),
  (1,  2, '強さを求めているなら、これ以上はないな。', 'If you seek strength, look no further.',
        '若是追求强大,此招正是极致。',        'Если искать силу, то вот она.', '索隆三刀流', 'ja'),
  (3,  4, '私はサイヤ人の孫悟空です！！', 'I am Son Goku, a Saiyan!',
        '我是赛亚人孙悟空！！',            'Я Сон Гоку, саяц!', '首次变超赛', 'ja'),
  (2,  6, '俺は絶対に火影になる！！',     'I will definitely become the Hokage!',
        '我一定要成为火影！！',             'Я обязательно стану Хокаге!', '鸣人宣言', 'ja'),
  (4,  9, '俺は、家族を取り戻すために戦う。', 'I fight to bring my family back.',
        '我战斗,是为了夺回家人。',           'Я сражаюсь, чтобы вернуть семью.', '炭治郎', 'ja'),
  (5,  11, '壁の向こうに海があるとわかった日から、見るもの全てが変わった。',
        'Since I learned the sea exists beyond the walls, everything I see has changed.',
        '自从知道墙外有海,我看到的一切都变了。', 'С тех пор как я узнал, что за стенами есть море, всё изменилось.',
        '艾伦看海', 'ja'),
  (6,  21, '逃げちゃダメだ！',          'I must not run away!',
        '不能逃避！',                    'Нельзя убегать!', '碇真嗣', 'ja'),
  (13, 29, 'エル・プサイ・コングルゥ',    'El Psy Kongroo.',
        'El Psy Kongroo。',             'Эл Псай Конгруу.', '牧濑红莉栖的口头禅', 'ja'),
  (14, 30, 'ワクワク！',                 'Waku waku!',
        '哇酷哇酷！',                    'Вакку-вакку!', '阿尼亚的兴奋', 'ja'),
  (8,  14, '湯ばあば、私をここで働かせてください！', 'Grandma Yubaba, please let me work here!',
        '汤婆婆,请让我在这里工作吧！',      'Бабушка Юбаба, разрешите мне здесь работать!', '千寻求工', 'ja'),
  (19, 37, 'I am going to make him an offer he cannot refuse.', 'Gli farò un''offerta che non potrà rifiutare.',
        '我要开一个他无法拒绝的条件。',      'Я сделаю ему предложение, от которого он не сможет отказаться.', '教父名言', 'en'),
  (20, 40, 'No, I am your father.',     'Nō, ego pater tuus sum.',
        '不,我是你的父亲。',              'Нет, я — твой отец.', '星球大战反转', 'en'),
  (19, 38, 'Keep your friends close, but your enemies closer.', 'Amicos prope serva, inimicos propius.',
        '把朋友留在身边,把敌人留得更近。',   'Держи друзей близко, а врагов ещё ближе.', '迈克·柯里昂', 'en');

-- 批量台词（分页演示量）：100 × 15 交叉生成 1500 条
INSERT INTO episode_lines (work_id, episode_id, character_id, line_native, line_en, line_zh, line_ru, margin_note, lang_of_original)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 100
),
ps (j) AS (
    SELECT 1 UNION ALL SELECT j + 1 FROM ps WHERE j < 15
)
SELECT
  1 + ((((a.i - 1) * 15 + b.j) * 7) % 300),
  1 + (((a.i - 1) * 15 + b.j) % 4500),
  1 + (((a.i - 1) * 15 + b.j) % 450),
  CONCAT('これは台詞のデモです ', (a.i - 1) * 15 + b.j, '。'),
  CONCAT('This is a demo line #', (a.i - 1) * 15 + b.j, '.'),
  CONCAT('这是一句演示台词 第', (a.i - 1) * 15 + b.j, '句。'),
  CONCAT('Это демонстрационная реплика №', (a.i - 1) * 15 + b.j, '.'),
  CONCAT('margin-', (a.i - 1) * 15 + b.j),
  ELT(1 + (((a.i - 1) * 15 + b.j) % 4), 'ja', 'ja', 'en', 'ru')
FROM seq a
CROSS JOIN ps b;

-- ---------- 评分与评价 ----------

INSERT INTO rating_sources (name, country_iso, url) VALUES
  ('IMDb', 'US', 'https://www.imdb.com'),
  ('Rotten Tomatoes', 'US', 'https://www.rottentomatoes.com'),
  ('Metacritic', 'US', 'https://www.metacritic.com'),
  ('MyAnimeList', 'JP', 'https://myanimelist.net'),
  ('Douban', 'CN', 'https://movie.douban.com'),
  ('Steam', 'US', 'https://store.steampowered.com');

INSERT INTO work_ratings (work_id, source_id, score, votes)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 300
)
SELECT
  1 + (i % 300),
  1 + (i % 6),
  ROUND(6.0 + RAND() * 3.8, 2),
  FLOOR(RAND() * 90000) + 1000
FROM seq;

INSERT INTO reviews (work_id, user_name, rating, title, body, lang, created_at, likes, spoiler) VALUES
  (1, 'pirate_fan', 9, '長編の金字塔',          '海贼王是少年漫画的杰作,世界观宏大且角色塑造深厚。', 'zh', DATE_SUB(NOW(), INTERVAL 30 DAY), 320, FALSE),
  (8, 'ghibli_lover', 10, 'Timeless classic',  'A breathtaking journey through a spirit world that still resonates today.',
       'en', DATE_SUB(NOW(), INTERVAL 25 DAY), 540, FALSE),
  (16, 'nolanist', 9, 'One of the best sci-fi films', 'The dream-layer concept is genius; the performance is impeccable.',
       'en', DATE_SUB(NOW(), INTERVAL 20 DAY), 410, TRUE),
  (4, '鬼舞辻推し', 10, '作画の神',             '战斗场面丝滑,炭治郎的成长令人动容。', 'zh', DATE_SUB(NOW(), INTERVAL 18 DAY), 390, FALSE),
  (26, 'tarnished_quest', 10, '年度神作',       '開放世界とハードコアバトルの完璧な融合。', 'ja', DATE_SUB(NOW(), INTERVAL 15 DAY), 610, FALSE),
  (29, '旅行者', 8, '开放世界的巅峰',           '提瓦特大陆处处是惊喜,就是抽卡有点上头。', 'zh', DATE_SUB(NOW(), INTERVAL 12 DAY), 270, FALSE),
  (18, 'andymane', 10, 'Hope is a good thing', 'It reminds us that hope never dies even in the darkest place.', 'en',
       DATE_SUB(NOW(), INTERVAL 10 DAY), 730, FALSE),
  (5, '遼', 9, '巨人を見て人生観が変わった',   '戦争と自由のテーマが深すぎる。', 'ja', DATE_SUB(NOW(), INTERVAL 8 DAY), 350, TRUE),
  (19, 'donc89', 10, 'Крёстный отец — это величайшая мафиозная сага', 'Сила персонажей, диалогов и режиссуры вне времени.', 'ru',
       DATE_SUB(NOW(), INTERVAL 6 DAY), 290, FALSE),
  (24, 'hylian_knight', 10, 'Survey, explore, and you will find yourself', 'Breath of the Wild redefined open worlds.', 'en',
       DATE_SUB(NOW(), INTERVAL 4 DAY), 480, FALSE);

INSERT INTO reviews (work_id, user_name, rating, title, body, lang, created_at, likes, spoiler)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 700
)
SELECT
  1 + (i % 300),
  CONCAT(ELT(1 + (i % 5), 'user', '观众', '観客', 'Критик', 'lector'), '_', i),
  3 + (i % 8),
  ELT(1 + (i % 5),
      CONCAT('Demo review ', i),
      CONCAT('演示评价 ', i),
      CONCAT('レビュー ', i),
      CONCAT('Отзыв ', i),
      CONCAT('Recensio ', i)),
  CONCAT('Body of the demo review #', i
         , '. 中文演示正文。日本語の本文。Русский текст рецензии. Latīna recensio.')
  ,
  ELT(1 + (i % 5), 'en', 'zh', 'ja', 'ru', 'la'),
  DATE_SUB(NOW(), INTERVAL (i % 30) DAY),
  (i % 200) * 3,
  (i % 11 = 0)
FROM seq
WHERE i <= 700;

INSERT INTO review_comments (review_id, user_name, body, lang, created_at)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 900
)
SELECT
  1 + (i % 710),
  CONCAT('commenter_', i),
  ELT(1 + (i % 4),
      CONCAT('Totally agree with this review #', (i % 710 + 1), '.'),
      CONCAT('同意这条评价。'),
      CONCAT('このレビューに同意します。'),
      CONCAT('Согласен с этим отзывом.')),
  ELT(1 + (i % 4), 'en', 'zh', 'ja', 'ru'),
  DATE_SUB(NOW(), INTERVAL (i % 14) DAY)
FROM seq
WHERE i <= 900;

-- ---------- 商业与衍生 ----------

INSERT INTO box_office (work_id, region, gross, currency, opening_weekend, year)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 300
)
SELECT
  1 + (i % 300),
  ELT(1 + (i % 5), 'USD', 'CNY', 'JPY', 'RUB', 'EUR'),
  ROUND(RAND() * 900000000 + 10000000, 2),
  ELT(1 + (i % 5), 'USD', 'CNY', 'JPY', 'RUB', 'EUR'),
  ROUND(RAND() * 120000000, 2),
  1990 + (i % 36)
FROM seq
WHERE i <= 300;

INSERT INTO soundtracks (work_id, title, composer_id, released) VALUES
  (8,  '千と千尋の神隠し イメージアルバム', 31, 2001),
  (7,  'となりのトトロ サウンドトラック集', 31, 1988),
  (15, '君の名は。 サウンドトラック', NULL, 2016),
  (25, 'FINAL FANTASY VII ORIGINAL SOUNDTRACK', 30, 1997),
  (19, 'The Godfather: Original Motion Picture Soundtrack', NULL, 1972),
  (24, 'Breath of the Wild: Official Soundtrack', NULL, 2017),
  (27, 'Minecraft - Volume Beta', NULL, 2013),
  (16, 'Inception: Music from the Motion Picture', NULL, 2010),
  (29, '原神 主題曲集', NULL, 2020),
  (30, 'PERSONA5 ORIGINAL SOUNDTRACK', NULL, 2016);

INSERT INTO soundtracks (work_id, title, composer_id, released)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 100
)
SELECT
  1 + ((i * 3) % 300),
  CONCAT('Soundtrack ', 1 + (i % 300), ' Vol.', i),
  1 + (i % 31),
  1990 + (i % 34)
FROM seq
WHERE i <= 50;

INSERT INTO tracks (soundtrack_id, track_no, title, title_zh, duration, vocalist_id, is_theme)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 720
)
SELECT
  1 + (i % 60),                     -- 60 张原声带 × 12 首
  (i % 12) + 1,
  CONCAT(ELT(1 + (i % 5),
      CONCAT('Track ', i),
      CONCAT('曲目', i),
      CONCAT('トラック', i),
      CONCAT('Трек ', i),
      CONCAT('Canticum ', i)), ' · ',
      IF(i % 2 = 0, CONCAT(' Demo ', i), CONCAT(' 演示 ', i))),
  CONCAT('演示曲目', i),
  SEC_TO_TIME(170 + (i % 6) * 40),
  1 + (i % 31),
  (i % 9 = 0)
FROM seq
WHERE i <= 720;

INSERT INTO trailers (work_id, platform_id, title, url, duration, released, views)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 200
)
SELECT
  1 + ((i * 5) % 300),
  1 + (i % 14),
  CONCAT('Official Trailer ', i),
  CONCAT('https://video.example.com/tr-', 1 + (i % 300), '-', i),
  60 + (i % 180),
  DATE_ADD('2005-01-01', INTERVAL (i * 37) DAY),
  (i % 50 + 1) * 100000
FROM seq
WHERE i <= 200;

INSERT INTO posters (work_id, kind, filename, url, width, height, format)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 600
)
SELECT
  1 + ((i % 300)),
  ELT(1 + (i % 4), 'poster', 'backdrop', 'still', 'logo'),
  CONCAT('work_', 1 + (i % 300), '_', ELT(1 + (i % 4), 'poster', 'wide', 'still', 'logo'), '.', ELT(1 + (i % 3), 'jpg', 'png', 'webp')),
  CONCAT('https://images.example.com/', 1 + (i % 300), '/', i, '.', ELT(1 + (i % 3), 'jpg', 'png', 'webp')),
  500 + (i % 800),
  500 + ((i * 3) % 800),
  ELT(1 + (i % 3), 'jpg', 'png', 'webp')
FROM seq
WHERE i <= 600;

-- ---------- 游戏 ----------

INSERT INTO game_releases (work_id, platform_id, region, release_date, price, physical, rating)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 180
)
SELECT
  1 + (i % 300),
  1 + (i % 14),
  ELT(1 + (i % 4), 'WW', 'JP', 'US', 'CN'),
  DATE_ADD('2010-01-01', INTERVAL (i * 41) DAY),
  ROUND(RAND() * 60 + 4.99, 2),
  (i % 3 != 0),
  ELT(1 + (i % 6), 'E', 'E10+', 'T', 'M', 'All', '12')
FROM seq
WHERE i <= 180;

INSERT INTO game_achievements (work_id, name, name_zh, hidden_hid, description, points, hidden)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 600
)
SELECT
  1 + (i % 300),
  CONCAT('Achievement ', i),
  CONCAT('成就', i),
  UNHEX(REPLACE(UUID(), '-', '')),
  CONCAT('Finished a demo task #', i, '.'),
  (i % 10) * 5 + 5,
  (i % 7 = 0)
FROM seq
WHERE i <= 600;

-- ---------- 奖项 ----------

INSERT INTO awards (name, org, country_iso, first_year) VALUES
  ('Oscar', 'Academy of Motion Picture Arts and Sciences', 'US', 1929),
  ('Cannes Palme d''Or', 'Cannes Film Festival', 'FR', 1946),
  ('Golden Lion', 'Venice Film Festival', 'IT', 1949),
  ('Golden Bear', 'Berlin International Film Festival', 'DE', 1951),
  ('Emmy Award', 'Academy of Television Arts & Sciences', 'US', 1949),
  ('Golden Globe Award', 'Hollywood Foreign Press Association', 'US', 1944),
  ('Annie Award', 'ASIFA-Hollywood', 'US', 1972),
  ('Seiyu Award', 'Seiyu Awards Executive Committee', 'JP', 2007),
  ('Tokyo Anime Award', 'Tokyo Anime Award Festival', 'JP', 2002),
  ('Golden Joystick Award', 'Future Publishing', 'GB', 1983),
  ('The Game Awards', 'The Game Awards', 'US', 2014),
  ('Douban Annual Film Awards', 'Douban', 'CN', 2010);

INSERT INTO award_categories (award_id, name) VALUES
  (1, 'Best Picture'), (1, 'Best Director'), (1, 'Best Animated Feature'),
  (2, 'Palme d''Or'), (2, 'Grand Prix'),
  (3, 'Golden Lion for Best Film'),
  (4, 'Golden Bear for Best Film'),
  (5, 'Outstanding Drama Series'),
  (6, 'Best Motion Picture - Drama'),
  (7, 'Best Animated Feature'),
  (8, 'Best Leading Voice Actor'), (8, 'Best Leading Voice Actress'),
  (9, 'Anime of the Year'),
  (10, 'Game of the Year'),
  (11, 'Game of the Year'), (11, 'Best Narrative'), (11, 'Best Art Direction'),
  (12, '年度最佳影片'), (12, '年度评分最高动漫');

INSERT INTO award_nominations (award_category_id, work_id, people_id, year, won)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 500
)
SELECT
  1 + (i % 18),
  CASE WHEN i % 3 = 0 THEN NULL ELSE 1 + (i % 300) END,
  CASE WHEN i % 3 = 0 THEN 1 + (i % 31) ELSE NULL END,
  2010 + (i % 15),
  (i % 9 = 0)
FROM seq
WHERE i <= 500;

-- ---------- 用户片单 ----------

INSERT INTO user_lists (user_name, title, description) VALUES
  ('深海鱼', '必看动漫 TOP 50', '个人向神作合集'),
  ('Mizuki', 'Studio Ghibli Complete', 'All the films ranked'),
  ('tarnished', '魂系通关记录', 'FromSoftware 全家桶'),
  ('旅人', '开放世界巡礼', '值得逛的地图'),
  ('cinephile', 'IMDb Top 100 挑战', '正在缓慢完成中');

INSERT INTO user_lists (user_name, title, description)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 100
)
SELECT
  ELT(1 + (i % 4), 'demo_user', '演示用户', '観客', 'Критик'),
  CONCAT('My List ', i),
  CONCAT('Description of list ', i, '. 中文描述。')
FROM seq
WHERE i <= 35;

INSERT INTO list_items (list_id, work_id, position, note)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 400
)
SELECT
  1 + (i % 40),
  1 + (i % 300),
  i,
  IF(i % 5 = 0, CONCAT('推荐理由：', i), NULL)
FROM seq
WHERE i <= 400;