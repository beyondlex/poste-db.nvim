-- =====================================================================
-- poste-db MySQL playground — history data
-- 手写知名朝代/人物/事件/文物/典籍 + 批量生成达到分页演示量
-- 多语言演示：英文 / 中文 / 日文 / 拉丁 / 俄文
-- 大表：timeline_events 2000 +、citations 918，人物 504，事件 640
-- 类型补充：DOUBLE/FLOAT/SMALLINT/POINT（capitals/battles/sites/expeditions）
-- =====================================================================

SET NAMES utf8mb4;
USE history;

-- ---------- 区域 ----------

INSERT INTO regions (code, name_en, name_zh, name_native, continent, area_km2, lat, lng, note) VALUES
  ('CN', 'China', '中国', '中国', 'asia', 9600000, 35.0, 105.0, '华夏大地'),
  ('JP', 'Japan', '日本', '日本', 'asia', 378000, 36.5, 138.2, '列岛文明'),
  ('KR', 'Korea', '朝鲜半岛', '한국', 'asia', 219000, 36.5, 127.9, '半岛三韩'),
  ('IN', 'India', '印度', 'भारत', 'asia', 3287000, 20.6, 79.0, '印度次大陆'),
  ('IR', 'Persia', '波斯', 'ایران', 'asia', 1648000, 32.4, 53.7, '高原帝国'),
  ('EG', 'Egypt', '埃及', 'مصر', 'africa', 1002000, 26.8, 30.8, '尼罗河文明'),
  ('IQ', 'Mesopotamia', '美索不达米亚', 'بلاد الرافدين', 'asia', 438000, 33.3, 43.4, '两河流域'),
  ('GR', 'Greece', '希腊', 'Ελλάδα', 'europe', 132000, 39.1, 21.8, '爱琴海城邦'),
  ('IT', 'Rome', '罗马（意大利）', 'Italia', 'europe', 301000, 41.9, 12.5, '亚平宁半岛'),
  ('EU', 'Western Europe', '西欧', 'Europe Occidentalis', 'europe', 1500000, 48.8, 2.3, '西欧诸国'),
  ('SE', 'Norse / Scandinavia', '北欧', 'Norden', 'europe', 1100000, 60.4, 15.2, '斯堪的纳维亚'),
  ('AM', 'Mesoamerica', '中美洲', 'Mesoamérica', 'americas', 970000, 19.5, -99.1, '玛雅/阿兹特克');

INSERT INTO regions (code, name_en, name_zh, name_native, continent, area_km2, lat, lng, note)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 23
)
SELECT
  UPPER(CONCAT(LEFT(ELT(1 + (i % 4), 'tn', 'st', 'rr', 'sp'), 1), i)),
  CONCAT('Region ', i + 12),
  CONCAT('演示区域', i + 12),
  CONCAT('Regio ', i + 12, ' Temporum'),
  ELT(1 + (i % 5), 'asia', 'europe', 'africa', 'americas', 'oceania'),
  ROUND((i % 90 + 3) * 100000.0 + i * 7.0, 2),
  ROUND((i % 60 - 30) + i * 0.13, 2),
  ROUND((i % 90 + 50) + i * 0.21, 2),
  CONCAT('Historical demo region #', i + 12)
FROM seq;

-- ---------- 文明 / 分期 / 家族 / 官职 ----------
INSERT INTO civilizations
(region_id, name_en, name_native, name_zh, start_year, end_year, flourish)
VALUES
  -- 东亚
  (1,  'Chinese civilization',      '中华文明',          '中华文明',        -3800, NULL,  '黄河/长江流域'),
  (2,  'Yamato civilization',       '大和',              '大和文明',        250,   NULL,  '畿内'),
  (3,  'Korean civilization',       '한국',              '朝鲜文明',        -1500, NULL,  '朝鲜半岛'),

  -- 南亚
  (4,  'Indus Valley civilization', 'सिंधु घाटी',             '印度河谷文明',    -2600, -1900, '摩亨佐-达罗/哈拉帕'),
  (19, 'Indian civilization',       'भारतीय सभ्यता',     '印度文明',        -1500, NULL,    '恒河流域'),

  -- 西亚/北非
  (6,  'Egyptian civilization',     'حضارة مصر',         '古埃及文明',      -3100, -30,    '尼罗河'),
  (7,  'Mesopotamian civilization', 'بلاد الرافدين',     '美索不达米亚文明', -3500, -539,   '乌尔/巴比伦'),
  (11, 'Elamite civilization',      'هَتَمتی',           '埃兰文明',        -3200, -539,    '苏萨/安善'),
  (12, 'Hittite civilization',      '𒌷𒄩𒀜𒋾',          '赫梯文明',        -1900, -1178,   '哈图沙'),
  (13, 'Assyrian civilization',     '𒀸𒋩',             '亚述文明',        -2500, -609,   '尼尼微/亚述城'),
  (14, 'Phoenician civilization',   '𐤊𐤍𐤏𐤍',           '腓尼基文明',      -1500, -539,       '推罗/西顿/迦太基'),
  (5,  'Persian civilization',      'تمدن ایران',        '波斯文明',        -550,  NULL,    '波斯波利斯'),
  (18, 'Islamic civilization',      'الحضارة الإسلامية', '伊斯兰文明',      622,   NULL,       '麦加/巴格达/开罗'),

  -- 欧洲
  (8,  'Greek civilization',        'Ελληνικός πολιτισμός', '希腊文明',     -1600, -146,    '雅典/爱琴海'),
  (9,  'Roman civilization',        'Civitas Romana',    '罗马文明',        -753,  476,       '台伯河七丘'),
  (17, 'Byzantine civilization',    'Βυζάντιον',         '拜占庭文明',      330,   1453,      '君士坦丁堡'),
  (10, 'European civilization',     'Europa',            '欧洲文明',        476,   NULL,      '西欧基督教世界'),
  (20, 'Celtic civilization',       'Celtic',            '凯尔特文明',      -1200, 500,       '中欧/不列颠/高卢'),

  -- 美洲
  (15, 'Maya civilization',         'Maya',              '玛雅文明',        -2000, 1697,   '尤卡坦/佩滕'),
  (16, 'Inca civilization',         'Tawantinsuyu',      '印加文明',        -1438, 1533,         '库斯科');

INSERT INTO civilizations (region_id, name_en, name_native, name_zh, start_year, end_year, flourish)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 30
)
SELECT
  1 + (i % 12),
  CONCAT('Civilization ', i + 10),
  CONCAT('Civilizatio ', i + 10),
  CONCAT('演示文明', i + 10),
  -2000 + i * 120,
  -2000 + i * 120 + 1600,
  CONCAT('Bloom of demo civilization #', i + 10)
FROM seq;

INSERT INTO eras (name_en, name_zh, name_ja, name_ru, start_year, end_year, description) VALUES
  ('Ancient', '上古', '上古', 'Древность', -3200, -500, '文字与城邦兴起'),
  ('Classical', '古典', '古典', 'Классика', -500, 500, '轴心时代与帝国'),
  ('Medieval', '中世纪', '中世', 'Средневековье', 500, 1450, '封建与宗教'),
  ('Early Modern', '早期近代', '近世', 'Новое время', 1450, 1789, '大航海与启蒙'),
  ('Modern', '近代', '近代', 'Новейшее время', 1789, 1945, '革命与工业'),
  ('Contemporary', '现代', '現代', 'Современность', 1945, NULL, '冷战与全球化');

INSERT INTO eras (name_en, name_zh, name_ja, name_ru, start_year, end_year, description)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 20
)
SELECT
  CONCAT('Era ', i + 6),
  CONCAT('时代', i + 6),
  CONCAT('時代', i + 6),
  CONCAT('Эпоха ', i + 6),
  -3000 + i * 220,
  -3000 + i * 220 + 180,
  CONCAT('演示分期 #', i + 6)
FROM seq;

INSERT INTO families (region_id, name_en, name_zh, name_native, rallied, sigil) VALUES
  (1, 'House of Liu', '刘氏', '劉氏', '沛县', '黑龙'),
  (1, 'House of Li (Tang)', '李氏（唐）', '李氏', '陇西', '金龙'),
  (1, 'House of Zhao (Song)', '赵氏（宋）', '趙氏', '涿郡', '赤日'),
  (1, 'House of Zhu (Ming)', '朱氏（明）', '朱氏', '凤阳', '朱龙'),
  (1, 'House of Aisin Gioro', '爱新觉罗氏', '愛新覺羅', '赫图阿拉', '黄带'),
  (9, 'Gens Julia', '尤利乌斯家族', 'ユリウス氏族', '阿尔巴朗格', '月桂'),
  (9, 'Gens Claudia', '克劳狄家族', 'クラウディウス', '罗马', '橡冠'),
  (10, 'House of Tudor', '都铎王朝', 'テューダー家', '伦敦', '双玫瑰');

INSERT INTO families (region_id, name_en, name_zh, name_native, rallied, sigil)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 12
)
SELECT
  1 + (i % 12),
  CONCAT('Clan ', i + 8),
  CONCAT('氏', i + 8),
  CONCAT('ゲン', i + 8),
  CONCAT('Rallied at site ', i + 8),
  CONCAT('Sigil-', i + 8)
FROM seq;

INSERT INTO court_offices (region_id, name_en, name_zh, rank_en, office_function) VALUES
  (1, 'Chancellor', '丞相', 'Second', '总揽政务'),
  (1, 'Censor-in-Chief', '御史大夫', 'Third', '监察百官'),
  (1, 'Grand Secretary', '内阁首辅', 'First', '票拟批红'),
  (2, 'Shogun', '征夷大将军', 'First', '武家最高权'),
  (9, 'Consul', '执政官', 'First', '军政最高长官'),
  (5, 'Grand Vizier', '大维齐尔', 'First', '帝国宰相');

INSERT INTO court_offices (region_id, name_en, name_zh, rank_en, office_function)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 14
)
SELECT
  1 + (i % 12),
  CONCAT('Office ', i + 6),
  CONCAT('官署', i + 6),
  ELT(1 + (i % 3), 'First', 'Second', 'Third'),
  CONCAT('演示职掌 #', i + 6)
FROM seq;

-- ---------- 历史人物 ----------

INSERT INTO historical_figures
  (id, region_id, family_id, court_office_id, name_en, name_zh, name_ja, name_ru, name_la,
   gender, birth_year, death_year, reign_start, reign_end, biography, honors, portrait) VALUES
  (1,  1, 1, 1, 'Qin Shi Huang', '秦始皇', '秦の始皇帝', 'Цинь Шихуан', 'Qin Shi Huangdi', 'male', -259, -210, -221, -210,
    '统一六国，书同文车同轨，筑长城修驰道。', JSON_OBJECT('temple', '始皇帝', 'posthumous', '始皇帝', 'era', '天下归一'), NULL),
  (2,  1, 1, 1, 'Emperor Wu of Han', '汉武帝', '漢武帝', 'У-ди', 'Wu of Han', 'male', -156, -87, -141, -87,
    '北击匈奴、南定百越、张骞凿空西域。', JSON_OBJECT('temple', '世宗', 'era', '建元'), NULL),
  (3,  1, 2, 1, 'Emperor Taizong of Tang', '唐太宗', '唐太宗', 'Тайцзун', 'Taizong of Tang', 'male', 598, 649, 626, 649,
    '贞观之治，纳谏如流，被尊为天可汗。', JSON_OBJECT('temple', '太宗', 'era', '贞观'), NULL),
  (4,  1, 2, NULL, 'Wu Zetian', '武则天', '武則天', 'У Цзэтянь', 'Wu Zetian', 'female', 624, 705, 690, 705,
    '中国历史上唯一正统女皇帝。', JSON_OBJECT('temple', '则天大圣', 'era', '载初/天授'), NULL),
  (5,  1, 5, NULL, 'Genghis Khan', '成吉思汗', 'チンギス・ハン', 'Чингисхан', 'Cingis Cham', 'male', 1162, 1227, 1206, 1227,
    '统一蒙古诸部，建立大蒙古国。', JSON_OBJECT('temple', '元太祖', 'title', '成吉思汗'), NULL),
  (6,  1, 5, NULL, 'Kublai Khan', '忽必烈', 'クビライ', 'Хубилай', 'Kublai', 'male', 1215, 1294, 1260, 1294,
    '建立元朝，灭亡南宋，定都大都。', JSON_OBJECT('temple', '元世祖', 'era', '中统/至元'), NULL),
  (7,  10, NULL, NULL, 'Napoleon Bonaparte', '拿破仑·波拿巴', 'ナポレオン・ボナパルト', 'Наполеон', 'Napoleo Bonaparte', 'male', 1769, 1821, 1804, 1815,
    '法兰西第一帝国皇帝，民法典传世。', JSON_OBJECT('era', '法皇', 'title', '皇帝'), NULL),
  (8,  9, 6, 5, 'Gaius Julius Caesar', '盖乌斯·尤利乌斯·凯撒', 'ユリウス・カエサル', 'Цезарь', 'Julius Caesar', 'male', -100, -44, -49, -44,
    '高卢征服者，跨过卢比孔河，终结共和。', JSON_OBJECT('title', '独裁官', 'posthumous', 'Divus Iulius'), NULL),
  (9,  8, NULL, NULL, 'Alexander the Great', '亚历山大大帝', 'アレクサンドロス大王', 'Александр Македонский', 'Alexander Magnus', 'male', -356, -323, -336, -323,
    '马其顿国王，横跨欧亚的征服者。', JSON_OBJECT('title', '世界之王'), NULL),
  (10, 9, 6, 5, 'Augustus', '奥古斯都', 'アウグストゥス', 'Август', 'Augustus', 'male', -63, 14, -27, 14,
    '罗马帝国元首政制的开创者。', JSON_OBJECT('posthumous', 'Divus Augustus', 'era', '元首制'), NULL),
  (11, 1, NULL, 1, 'Yue Fei', '岳飞', '岳飛', 'Юэ Фэй', 'Io Fei', 'male', 1103, 1142, NULL, NULL,
    '精忠报国，南宋名将。', JSON_OBJECT('posthumous', '武穆', 'palace', '鄂王'), NULL),
  (12, 1, NULL, NULL, 'Zheng He', '郑和', '鄭和', 'Чжэн Хэ', 'Zheng He', 'male', 1371, 1433, NULL, NULL,
    '七下西洋，宝船远航。', JSON_OBJECT('title', '三宝太监'), NULL),
  (13, 10, NULL, NULL, 'Leonardo da Vinci', '莱昂纳多·达·芬奇', 'レオナルド・ダ・ヴィンチ', 'Леонардо', 'Leonardus Vincius', 'male', 1452, 1519, NULL, NULL,
    '文艺复兴全才，画家科学家。', JSON_OBJECT('work', 'Mona Lisa'), NULL),
  (14, 10, NULL, NULL, 'Isaac Newton', '艾萨克·牛顿', 'アイザック・ニュートン', 'Ньютон', 'Isaacus Newtonus', 'male', 1643, 1727, NULL, NULL,
    '万有引力与经典力学奠基人。', JSON_OBJECT('work', 'Principia'), NULL),
  (15, 1, 1, NULL, 'Confucius', '孔子', '孔子', 'Конфуций', 'Confucius', 'male', -551, -479, NULL, NULL,
    '儒家学派创始人，仁义礼智信。', JSON_OBJECT('title', '至圣先师'), NULL),
  (16, 1, NULL, NULL, 'Laozi', '老子', '老子', 'Лао-цзы', 'Laozi', 'male', -571, -471, NULL, NULL,
    '道家始祖，道德经五千言。', JSON_OBJECT('title', '太上老君'), NULL),
  (17, 1, 1, NULL, 'Mencius', '孟子', '孟子', 'Мэн-цзы', 'Mencius', 'male', -372, -289, NULL, NULL,
    '亚圣，性善论，民贵君轻。', JSON_OBJECT('title', '亚圣'), NULL),
  (18, 1, NULL, NULL, 'Mozi', '墨子', '墨子', 'Мо-цзы', 'Motse', 'male', -468, -376, NULL, NULL,
    '墨家巨子，兼爱非攻。', JSON_OBJECT('title', '墨家祖师'), NULL),
  (19, 8, NULL, NULL, 'Socrates', '苏格拉底', 'ソクラテス', 'Сократ', 'Socrates', 'male', -470, -399, NULL, NULL,
    '古希腊三贤之首，助产术。', JSON_OBJECT('title', '西方哲学之父'), NULL),
  (20, 8, NULL, NULL, 'Plato', '柏拉图', 'プラトン', 'Платон', 'Plato', 'male', -427, -347, NULL, NULL,
    '理想国，理念论。', JSON_OBJECT('work', 'Republic'), NULL),
  (21, 8, NULL, NULL, 'Aristotle', '亚里士多德', 'アリストテレス', 'Аристотель', 'Aristoteles', 'male', -384, -322, NULL, NULL,
    '百科全书式学者，形式逻辑。', JSON_OBJECT('work', 'Metaphysics'), NULL),
  (22, 10, NULL, NULL, 'Dante Alighieri', '但丁', 'ダンテ', 'Данте', 'Dantes Alagherius', 'male', 1265, 1321, NULL, NULL,
    '神曲作者，意大利语文学之父。', JSON_OBJECT('work', 'La Divina Commedia'), NULL),
  (23, 10, NULL, NULL, 'James Cook', '詹姆斯·库克', 'ジェームズ・クック', 'Кук', 'Iacobus Cook', 'male', 1728, 1779, NULL, NULL,
    '太平洋三度远航，绘制海图。', JSON_OBJECT('title', 'Captain Cook'), NULL),
  (24, 10, NULL, NULL, 'Christopher Columbus', '克里斯托弗·哥伦布', 'コロンブス', 'Колумб', 'Columbus', 'male', 1451, 1506, NULL, NULL,
    '横渡大西洋抵达美洲。', JSON_OBJECT('title', '航海家'), NULL),
  (25, 10, NULL, NULL, 'Ferdinand Magellan', '费迪南德·麦哲伦', 'マゼラン', 'Магеллан', 'Magellanus', 'male', 1480, 1521, NULL, NULL,
    '环球航行计划者。', JSON_OBJECT('title', '环球航海'), NULL),
  (26, 10, NULL, NULL, 'Joan of Arc', '圣女贞德', 'ジャンヌ・ダルク', 'Жанна д''Арк', 'Ioanna Arcensis', 'female', 1412, 1431, NULL, NULL,
    '百年战争法国民族英雄。', JSON_OBJECT('title', '奥尔良少女'), NULL),
  (27, 10, 8, NULL, 'Elizabeth I', '伊丽莎白一世', 'エリザベス1世', 'Елизавета I', 'Elizabetha I', 'female', 1533, 1603, 1558, 1603,
    '都铎王朝最后君主，黄金时代。', JSON_OBJECT('title', '童贞女王'), NULL),
  (28, 10, NULL, NULL, 'Peter the Great', '彼得大帝', 'ピョートル1世', 'Пётр I', 'Petrus Magnus', 'male', 1672, 1725, 1682, 1725,
    '俄国西化改革，建圣彼得堡。', JSON_OBJECT('title', '大帝'), NULL),
  (29, 4, NULL, NULL, 'Ashoka', '阿育王', 'アショーカ王', 'Ашока', 'Asoka', 'male', -304, -232, -268, -232,
    '孔雀王朝转信佛法。', JSON_OBJECT('title', 'Dharma Raja'), NULL),
  (30, 9, 7, NULL, 'Hannibal', '汉尼拔', 'ハンニバル', 'Ганнибал', 'Hannibal', 'male', -247, -183, NULL, NULL,
    '翻越阿尔卑斯奇袭罗马。', JSON_OBJECT('title', '布匿战争名将'), NULL),
  (31, 9, NULL, NULL, 'Spartacus', '斯巴达克', 'スパルタクス', 'Спартак', 'Spartacus', 'male', -111, -71, NULL, NULL,
    '角斗士起义领袖。', JSON_OBJECT('title', '角斗士领袖'), NULL),
  (32, 8, NULL, NULL, 'Leonidas', '列奥尼达', 'レオニダス', 'Леонид', 'Leonidas', 'male', -540, -480, -490, -480,
    '温泉关三百勇士统帅。', JSON_OBJECT('title', '斯巴达国王'), NULL),
  (33, 1, NULL, 1, 'Xuanzang', '玄奘', '玄奘', 'Сюаньцзан', 'Hsüan-tsang', 'male', 602, 664, NULL, NULL,
    '西行求法，翻译佛经。', JSON_OBJECT('title', '三藏法师'), NULL),
  (34, 1, 1, 2, 'Sima Qian', '司马迁', '司馬遷', 'Сыма Цянь', 'Sima Qian', 'male', -145, -86, NULL, NULL,
    '史记作者，史家之绝唱。', JSON_OBJECT('work', '史记'), NULL),
  (35, 1, NULL, NULL, 'Du Fu', '杜甫', '杜甫', 'Ду Фу', 'Du Fu', 'male', 712, 770, NULL, NULL,
    '诗圣，安史之乱见证者。', JSON_OBJECT('title', '诗圣'), NULL),
  (36, 1, NULL, NULL, 'Li Bai', '李白', '李白', 'Ли Бай', 'Li Bai', 'male', 701, 762, NULL, NULL,
    '诗仙，浪漫主义高峰。', JSON_OBJECT('title', '诗仙'), NULL),
  (37, 1, 3, NULL, 'Su Shi', '苏轼', '蘇軾', 'Су Ши', 'Si Sce', 'male', 1037, 1101, NULL, NULL,
    '唐宋八大家，东坡居士。', JSON_OBJECT('title', '东坡居士', 'work', '赤壁赋'), NULL),
  (38, 1, NULL, 1, 'Wen Tianxiang', '文天祥', '文天祥', 'Вэнь Тяньсян', 'Wen Tianxiang', 'male', 1236, 1283, NULL, NULL,
    '人生自古谁无死，留取丹心照汗青。', JSON_OBJECT('posthumous', '忠烈'), NULL),
  (39, 1, NULL, 3, 'Zhang Juzheng', '张居正', '張居正', 'Чжан Цзюйчжэн', 'Zhang Juzheng', 'male', 1525, 1582, NULL, NULL,
    '万历首辅，一条鞭法。', JSON_OBJECT('office', '内阁首辅'), NULL),
  (40, 1, 4, NULL, 'Wang Yangming', '王阳明', '王陽明', 'Ван Янмин', 'Wang Yangming', 'male', 1472, 1529, NULL, NULL,
    '阳明心学，知行合一。', JSON_OBJECT('title', '阳明先生'), NULL),
  (41, 10, NULL, NULL, 'Francis Bacon', '弗朗西斯·培根', 'フランシス・ベーコン', 'Бэкон', 'Franciscus Bacon', 'male', 1561, 1626, NULL, NULL,
    '归纳法宣言者。', JSON_OBJECT('work', 'Novum Organum'), NULL),
  (42, 10, NULL, NULL, 'Galileo Galilei', '伽利略', 'ガリレオ', 'Галилей', 'Galilaeus', 'male', 1564, 1642, NULL, NULL,
    '现代科学之父，天文观测。', JSON_OBJECT('work', 'Dialogo'), NULL),
  (43, 10, NULL, NULL, 'Adam Smith', '亚当·斯密', 'アダム・スミス', 'Адам Смит', 'Adam Smith', 'male', 1723, 1790, NULL, NULL,
    '国富论，现代经济学之父。', JSON_OBJECT('work', 'Wealth of Nations'), NULL),
  (44, 10, NULL, NULL, 'Karl Marx', '卡尔·马克思', 'カール・マルクス', 'Маркс', 'Carolus Marx', 'male', 1818, 1883, NULL, NULL,
    '共产党宣言，历史唯物主义。', JSON_OBJECT('work', 'Das Kapital'), NULL),
  (45, 10, NULL, NULL, 'George Washington', '乔治·华盛顿', 'ジョージ・ワシントン', 'Вашингтон', 'Georgius Washington', 'male', 1732, 1799, NULL, NULL,
    '美国开国总统。', JSON_OBJECT('title', '国父'), NULL),
  (46, 10, NULL, NULL, 'Abraham Lincoln', '亚伯拉罕·林肯', 'リンカーン', 'Линкольн', 'Abrahamus Lincoln', 'male', 1809, 1865, NULL, NULL,
    '解放黑奴宣言，南北战争。', JSON_OBJECT('title', '国家统一者'), NULL),
  (47, 5, NULL, NULL, 'Osman I', '奥斯曼一世', 'オスマン1世', 'Осман I', 'Osmanus', 'male', 1258, 1326, 1299, 1326,
    '奥斯曼帝国奠基人。', JSON_OBJECT('title', '帝国之父'), NULL),
  (48, 9, 6, NULL, 'Romulus', '罗慕路斯', 'ロームルス', 'Ромул', 'Romulus', 'male', -771, -717, NULL, NULL,
    '罗马上古的建城者。', JSON_OBJECT('title', '建城者'), NULL);

INSERT INTO historical_figures
  (region_id, family_id, court_office_id, name_en, name_zh, name_ja, name_ru, name_la,
   gender, birth_year, death_year, reign_start, reign_end, biography, honors)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 456
)
SELECT
  1 + (i % 12),
  CASE WHEN i % 5 = 0 THEN 1 + (i % 20) ELSE NULL END,
  CASE WHEN i % 7 = 0 THEN 1 + (i % 20) ELSE NULL END,
  ELT(1 + (i % 5),
      CONCAT('Statesman ', i + 48),
      CONCAT('文人', i + 48),
      CONCAT('人物', i + 48),
      CONCAT('Правитель ', i + 48),
      CONCAT('Vir Illustris ', i + 48)),
  CONCAT('演示人物', i + 48),
  CONCAT('デモ人物', i + 48),
  CONCAT('Персонаж ', i + 48),
  CONCAT('Persona Historica ', i + 48),
  ELT(1 + (i % 3), 'male', 'female', 'unknown'),
  -1000 + i * 3,
  -1000 + i * 3 + 60,
  CASE WHEN i % 4 = 0 THEN -900 + i * 3 ELSE NULL END,
  CASE WHEN i % 4 = 0 THEN -900 + i * 3 + 50 ELSE NULL END,
  ELT(1 + (i % 4), 'A notable figure in world history.',
                   '世界历史上的杰出人物。',
                   '世界史に名を残す人物。',
                   'Мagnae historiae persona.'),
  JSON_OBJECT('code', i + 48)
FROM seq;

-- 人物别名
INSERT INTO figure_aliases (figure_id, alias, lang, kind)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 480
)
SELECT
  1 + (i % 504),
  ELT(1 + (i % 6),
      CONCAT('Alias-', i),
      CONCAT('谥号', i),
      CONCAT('ね', i),
      CONCAT('Cognomen ', i),
      CONCAT('촐', i),
      CONCAT('Прозвище ', i)),
  ELT(1 + (i % 6), 'en', 'zh', 'ja', 'la', 'ru', 'zh'),
  ELT(1 + (i % 6), 'regnal name', 'era name', 'posthumous name', 'temple name', 'cognomen', 'hidden')
FROM seq;

-- 家族成员
INSERT INTO family_members (family_id, figure_id, relation, start_year, end_year)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 200
)
SELECT
  1 + (i % 20),
  1 + ((i * 7) % 504),
  ELT(1 + (i % 6), 'founder', 'patriarch', 'heir', 'spouse', 'consort', 'collateral'),
  CASE WHEN i % 3 = 0 THEN NULL ELSE -500 + i * 5 END,
  CASE WHEN i % 3 = 0 THEN NULL ELSE -500 + i * 5 + 40 END
FROM seq;

-- ---------- 朝代与都城 ----------

INSERT INTO dynasties
  (id, region_id, civilization_id, era_id, founder_figure_id, name_en, name_zh, name_native,
   established_year, ended_year, sovereigns, note) VALUES
  (1,  1, 1, 2, 1,  'Qin dynasty', '秦', '秦', -221, -207, 3, '首次大一统'),
  (2,  1, 1, 2, 2,  'Han dynasty', '汉', '汉', -202, 220, 29, '文景之治、丝绸之路'),
  (3,  1, 1, 3, 3,  'Tang dynasty', '唐', '唐', 618, 907, 21, '贞观之治、开元盛世'),
  (4,  1, 1, 3, NULL, 'Northern Song', '北宋', '北宋', 960, 1127, 9, '商业繁荣、理学兴起'),
  (5,  1, 1, 3, 6,  'Yuan dynasty', '元', '元', 1271, 1368, 10, '蒙古统治中原'),
  (6,  1, 1, 4, NULL, 'Ming dynasty', '明', '明', 1368, 1644, 16, '永乐大典、长城'),
  (7,  1, 1, 4, NULL, 'Qing dynasty', '清', '清', 1644, 1912, 12, '康乾盛世'),
  (8,  9, 9, 2, 10, 'Roman Empire', '罗马帝国', 'Romanum Imperium', -27, 476, 43, '奥古斯都至西罗马'),
  (9,  5, 5, 3, 47, 'Ottoman Empire', '奥斯曼帝国', 'Osmanlı İmparatorluğu', 1299, 1922, 36, '横跨三洲'),
  (10, 9, 9, 3, NULL, 'Byzantine Empire', '拜占庭帝国', 'Βυζαντινή', 330, 1453, 92, '千年帝国'),
  (11, 10, 10, 3, NULL, 'Holy Roman Empire', '神圣罗马帝国', 'Heiliges Römisches Reich', 962, 1806, 44, '既不神圣也不罗马'),
  (12, 10, 10, 3, NULL, 'Plantagenet', '金雀花王朝', 'Plantagenêts', 1154, 1485, 11, '英格兰安茹王朝');

INSERT INTO dynasties (region_id, civilization_id, era_id, founder_figure_id, name_en, name_zh, name_native,
   established_year, ended_year, sovereigns, note)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 28
)
SELECT
  1 + (i % 12),
  CASE WHEN i % 3 = 0 THEN 1 + (i % 10) ELSE NULL END,
  1 + (i % 6),
  CASE WHEN i % 5 = 0 THEN 1 + (i % 48) ELSE NULL END,
  CONCAT('Dynasty ', i + 12),
  CONCAT('王朝', i + 12),
  CONCAT('Dynastia ', i + 12),
  -800 + i * 47,
  -800 + i * 47 + 110,
  1 + (i % 14),
  CONCAT('演示王朝 #', i + 12)
FROM seq;

INSERT INTO capitals (id, dynasty_id, name_en, name_zh, name_ja, coord, elevation_m, first_year, last_year) VALUES
  (1,  1,  'Xianyang', '咸阳', '咸陽', POINT(108.71, 34.33), 385, -350, -207),
  (2,  2,  'Chang''an', '长安', '長安', POINT(108.94, 34.34), 400, -202, 220),
  (3,  3,  'Chang''an (Tang)', '长安（唐）', '長安', POINT(108.94, 34.34), 400, 618, 904),
  (4,  4,  'Kaifeng', '开封', '開封', POINT(114.31, 34.79), 75, 960, 1127),
  (5,  5,  'Khanbaliq (Dadu)', '大都', '大都', POINT(116.40, 39.90), 43, 1267, 1368),
  (6,  6,  'Nanjing', '南京（应天）', '南京', POINT(118.80, 32.06), 20, 1368, 1421),
  (7,  7,  'Beijing', '北京（京师）', '北京', POINT(116.40, 39.90), 43, 1421, 1912),
  (8,  8,  'Rome', '罗马', 'ローマ', POINT(12.50, 41.89), 21, -27, 476),
  (9,  9,  'Constantinople', '君士坦丁堡', 'コンスタンティノープル', POINT(28.98, 41.01), 40, 330, 1453),
  (10, 9,  'Istanbul', '伊斯坦布尔', 'イスタンブール', POINT(28.98, 41.01), 40, 1453, 1922),
  (11, 11, 'Aachen', '亚琛', 'アーヘン', POINT(6.08, 50.78), 173, 800, 1531),
  (12, 12, 'London', '伦敦', 'ロンドン', POINT(-0.13, 51.51), 11, 1154, 1485);

INSERT INTO capitals (dynasty_id, name_en, name_zh, name_ja, coord, elevation_m, first_year, last_year)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 28
)
SELECT
  1 + (i % 40),
  CONCAT('Caput ', i + 12),
  CONCAT('都城', i + 12),
  CONCAT('彼都', i + 12),
  POINT(20 + (i % 120) + (i % 10) / 100.0, 0 + (i % 60) + (i % 10) / 100.0),
  20 + (i % 800),
  -500 + i * 37,
  -500 + i * 37 + 150
FROM seq;

-- ---------- 事件与参与 ----------

INSERT INTO historical_events
  (id, region_id, era_id, name_en, name_zh, name_ja, name_ru, event_year, kind, description) VALUES
  (1,  1, 2, 'Unification of China by Qin', '秦统一六国', '中国統一', 'Объединение Китая', -221, 'war', '始皇帝扫灭六国，书同文车同轨。'),
  (2,  1, 2, 'Dazexiang Uprising', '陈胜吴广起义', '陳勝呉広の乱', 'Восстание в Дацзэсяне', -209, 'rebellion', '王侯将相宁有种乎。'),
  (3,  1, 2, 'Battle of Red Cliffs', '赤壁之战', '赤壁の戦い', 'Битва при Чиби', 208, 'war', '孙刘联军火攻大破曹操。'),
  (4,  1, 2, 'Battle of Guandu', '官渡之战', '官渡の戦い', 'Битва при Гуаньду', 200, 'war', '曹操以少胜多。'),
  (5,  1, 3, 'Battle of Fei River', '淝水之战', '淝水の戦い', 'Битва на реке Фэйшуй', 383, 'war', '东晋以少胜多，风声鹤唳。'),
  (6,  1, 3, 'Xuanwu Gate Incident', '玄武门之变', '玄武門の変', 'Инцидент у ворот Сюаньу', 626, 'war', '李世民夺位。'),
  (7,  1, 3, 'An Lushan Rebellion', '安史之乱', '安史の乱', 'Восстание Ань Лушаня', 755, 'rebellion', '大唐由盛转衰。'),
  (8,  1, 3, 'Jingkang Incident', '靖康之变', '靖康の変', 'Инцидент Цзинкан', 1127, 'war', '北宋灭亡，汴京沦陷。'),
  (9,  1, 3, 'Battle of Yamen', '崖山海战', '崖山の戦い', 'Морское сражение при Ямыне', 1279, 'war', '南宋灭亡，陆秀夫负帝蹈海。'),
  (10, 1, 4, 'Zheng He''s voyages', '郑和下西洋', '鄭和の大航海', 'Плавания Чжэн Хэ', 1405, 'exploration', '宝船七下西洋。'),
  (11, 1, 4, 'Yongle relocation to Beijing', '永乐迁都北京', '永楽遷都', 'Перенос столицы в Пекин', 1421, 'politics', '天子守国门。'),
  (12, 1, 4, 'Tumu Crisis', '土木堡之变', '土木の変', 'Кризис в Туму', 1449, 'war', '明英宗被俘。'),
  (13, 1, 4, 'Peasant uprisings of late Ming', '明末农民起义', '明末の民乱', 'Крестьянские восстания', 1644, 'rebellion', '李自成入北京。'),
  (14, 1, 5, 'Marco Polo Bridge Incident', '卢沟桥事变', '盧溝橋事件', 'Инцидент на мосту Лугоу', 1937, 'war', '全民族抗战开始。'),
  (15, 1, 5, 'Hundred Days Reform', '戊戌变法', '戊戌変法', 'Реформы 1898 года', 1898, 'reform', '康梁维新百日而败。'),
  (16, 1, 5, 'Self-Strengthening Movement', '洋务运动', '洋務運動', 'Движение самоусиления', 1861, 'reform', '师夷长技以制夷。'),
  (17, 1, 5, 'First Sino-Japanese War', '甲午战争', '日清戦争', 'Японо-китайская война', 1894, 'war', '北洋水师覆灭。'),
  (18, 10, 2, 'Battle of Marathon', '马拉松战役', 'マラトンの戦い', 'Марафонская битва', -490, 'war', '希腊以少胜多。'),
  (19, 8, 2, 'Battle of Thermopylae', '温泉关之战', 'テルモピレーの戦い', 'Фермопильское сражение', -480, 'war', '斯巴达三百壮士。'),
  (20, 8, 2, 'Peloponnesian War', '伯罗奔尼撒战争', 'ペロポネソス戦争', 'Пелопоннесская война', -431, 'war', '雅典与斯巴达争霸。'),
  (21, 8, 2, 'Alexander''s conquest of Persia', '亚历山大东征', 'アレクサンドロス東征', 'Поход Александра', -334, 'war', '征服波斯帝国。'),
  (22, 9, 2, 'Founding of Rome', '罗马建城', 'ローマ建国', 'Основание Рима', -753, 'misc', '罗慕路斯建城。'),
  (23, 9, 2, 'First Punic War', '第一次布匿战争', '第一次ポエニ戦争', 'Первая Пуническая война', -264, 'war', '罗马与迦太基争地中海。'),
  (24, 9, 2, 'Spartacus Revolt', '斯巴达克起义', 'スパルタクスの乱', 'Восстание Спартака', -73, 'rebellion', '角斗士起义。'),
  (25, 9, 2, 'Caesar crosses the Rubicon', '凯撒渡卢比孔河', 'ルビコン渡河', 'Переход Рубикона', -49, 'war', '骰子已经掷下。'),
  (26, 9, 2, 'Augustus becomes princeps', '奥古斯都时代开始', 'アウグストゥス即位', 'Принципат Августа', -27, 'politics', '罗马帝国开端。'),
  (27, 9, 3, 'Fall of the Western Roman Empire', '西罗马帝国灭亡', '西ローマ帝国滅亡', 'Падение Западной Римской империи', 476, 'war', '古典时代落幕。'),
  (28, 10, 3, 'First Crusade', '第一次十字军东征', '第一次十字軍', 'Первый крестовый поход', 1096, 'war', '克复耶路撒冷。'),
  (29, 10, 3, 'Black Death', '黑死病', '黒死病', 'Чёрная смерть', 1347, 'disaster', '横扫欧亚，人口骤减。'),
  (30, 9, 3, 'Fall of Constantinople', '君士坦丁堡陷落', 'コンスタンティノープル陥落', 'Падение Константинополя', 1453, 'war', '千年帝国终结。'),
  (31, 10, 4, 'Columbus reaches the Americas', '哥伦布抵达美洲', 'コロンブス上陸', 'Колумб в Америке', 1492, 'exploration', '新旧大陆连接。'),
  (32, 10, 4, 'Magellan circumnavigation', '麦哲伦环球航行', 'マゼラン世界一周', 'Кругосветное плавание', 1519, 'exploration', '首次环球。'),
  (33, 10, 4, 'Thirty Years'' War', '三十年战争', '三十年戦争', 'Тридцатилетняя война', 1618, 'war', '欧陆宗教战争。'),
  (34, 10, 4, 'French Revolution', '法国大革命', 'フランス革命', 'Великая французская революция', 1789, 'revolution', '自由平等博爱。'),
  (35, 10, 5, 'Napoleon crowned Emperor', '拿破仑称帝', 'ナポレオン戴冠', 'Коронация Наполеона', 1804, 'politics', '法兰西第一帝国。'),
  (36, 10, 5, 'Battle of Waterloo', '滑铁卢战役', 'ワーテルローの戦い', 'Битва при Ватерлоо', 1815, 'war', '拿破仑帝国终结。'),
  (37, 10, 5, 'Industrial Revolution', '工业革命', '産業革命', 'Промышленная революция', 1769, 'misc', '蒸汽时代开启。'),
  (38, 10, 5, 'American Revolutionary War', '美国独立战争', 'アメリカ独立戦争', 'Война за независимость США', 1775, 'war', '十三州独立。'),
  (39, 2, 5, 'Meiji Restoration', '明治维新', '明治維新', 'Реставрация Мэйдзи', 1868, 'reform', '日本近代化改革。'),
  (40, 9, 3, 'Ottoman conquest of Constantinople', '奥斯曼联军攻陷君堡', 'オスマンの征服', 'Завоевание Константинополя', 1453, 'war', '新帝国崛起。');

INSERT INTO historical_events (region_id, era_id, name_en, name_zh, name_ja, name_ru, event_year, kind, description)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 600
)
SELECT
  1 + (i % 12),
  1 + (i % 6),
  CONCAT('Event ', i + 40),
  CONCAT('事件', i + 40),
  CONCAT('出来事', i + 40),
  CONCAT('Событие ', i + 40),
  -1500 + i * 4,
  ELT(1 + (i % 10), 'rebellion', 'war', 'reform', 'revolution', 'disaster', 'trade', 'diplomacy', 'exploration', 'cultural', 'politics'),
  CONCAT('演示事件 #', i + 40)
FROM seq
WHERE i <= 600;

INSERT INTO event_participants (event_id, figure_id, role, note)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 500
)
SELECT
  1 + (i % 640),
  1 + ((i * 7) % 504),
  ELT(1 + (i % 5), 'leader', 'general', 'advisor', 'chronicler', 'beneficiary'),
  CONCAT('demo-', i)
FROM seq;

-- ---------- 战争 / 战役 / 条约 ----------

INSERT INTO wars
  (id, region_id, era_id, name_en, name_zh, name_ja, started, ended, result_en, belligerents) VALUES
  (1,  1, 2, 'Wars at the end of Han', '汉末三国混战', '三国時代の戦乱', 184, 280, 'Three Kingdoms', 'China'),
  (2,  1, 2, 'Jin vs Former Qin', '晋与前秦之战', '前秦と東晋の戦争', 373, 383, 'Eastern Jin', 'China'),
  (3,  1, 3, 'Sui-Tang transition wars', '隋末唐初群雄逐鹿', '隋末唐初の戦乱', 611, 630, 'Tang united China', 'China'),
  (4,  1, 4, 'Qing-Dzungar War', '清准战争', '清のジュンガル征討', 1688, 1757, 'Qing victory', 'China'),
  (5,  1, 3, 'Mongol conquest of Song', '蒙元灭宋', '南宋征服', 1235, 1279, 'Yuan consolidated', 'China,Mongol'),
  (6,  1, 3, 'Song-Jin Wars', '宋金战争', '金の南侵', 1125, 1234, 'Joint Song-Mongol defeat of Jin', 'China,Mongol'),
  (7,  10, 3, 'Crusades', '十字军东征', '十字軍', 1096, 1291, 'Crusader states', 'Europe,Islamic'),
  (8,  8, 2, 'Greco-Persian Wars', '希波战争', 'ペルシア戦争', -499, -449, 'Greek victory', 'Greece,Persia'),
  (9,  8, 2, 'Peloponnesian War', '伯罗奔尼撒战争', 'ペロポネソス戦争', -431, -404, 'Spartan victory', 'Greece'),
  (10, 9, 2, 'Punic Wars', '布匿战争', 'ポエニ戦争', -264, -146, 'Roman victory', 'Rome,Carthage'),
  (11, 10, 5, 'Napoleonic Wars', '拿破仑战争', 'ナポレオン戦争', 1803, 1815, 'Coalition victory', 'Europe'),
  (12, 10, 5, 'American Revolutionary War', '美国独立战争', 'アメリカ独立戦争', 1775, 1783, 'American independence', 'America'),
  (13, 9, 3, 'Byzantine-Seljuk Wars', '拜占廷-塞尔柱战争', '東ローマ・セルジューク戦争', 1048, 1138, 'Seljuk advance', 'Byzantine,Islamic'),
  (14, 9, 3, 'Byzantine-Ottoman Wars', '拜占廷-奥斯曼战争', '東ローマ・オスマン戦争', 1341, 1453, 'Ottoman conquest', 'Byzantine,Ottoman'),
  (15, 6, 2, 'Kadesh / Egyptian-Hittite War', '埃及-赫梯战争', 'カデシュの戦い', -1274, -1259, 'Treaty of Kadesh', 'Egypt,Mesopotamia'),
  (16, 10, 3, 'Hundred Years'' War', '英法百年战争', '百年戦争', 1337, 1453, 'French victory', 'Europe');

INSERT INTO wars (region_id, era_id, name_en, name_zh, name_ja, started, ended, result_en, belligerents)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 24
)
SELECT
  1 + (i % 12),
  1 + (i % 6),
  CONCAT('War ', i + 16),
  CONCAT('战争', i + 16),
  CONCAT('戦争', i + 16),
  -1000 + i * 61,
  -1000 + i * 61 + 40,
  CONCAT('Outcome ', i % 3),
  ELT(1 + (i % 5), 'China', 'Rome', 'Europe', 'Greece', 'Islamic')
FROM seq;

INSERT INTO battles
  (id, war_id, name_en, name_zh, name_ja, battle_date, coord, troops_a, troops_b, casualty_ratio, outcome) VALUES
  (1,  8,  'Battle of Thermopylae', '温泉关之战', 'テルモピレー', -480, POINT(22.78, 38.80), 7000, 180000, 0.05, 'B victory'),
  (2,  8,  'Battle of Marathon', '马拉松战役', 'マラトン', -490, POINT(23.96, 38.12), 10000, 25000, 0.3, 'A victory'),
  (3,  8,  'Battle of Salamis', '萨拉米斯海战', 'サラミス', -480, POINT(23.46, 37.95), 380, 1200, NULL, 'A victory'),
  (4,  10, 'Battle of Cannae', '坎尼会战', 'カンナエ', -216, POINT(16.44, 41.30), 50000, 87000, 0.5, 'B victory'),
  (5,  10, 'Battle of Zama', '扎马战役', 'ザマ', -202, POINT(9.42, 36.33), 30000, 40000, 0.4, 'A victory'),
  (6,  10, 'Battle of Pharsalus', '法萨卢斯战役', 'ファルサルス', -48, POINT(22.38, 39.36), 22000, 45000, 0.35, 'A victory'),
  (7,  1,  'Battle of Guandu', '官渡之战', '官渡', 200, POINT(113.90, 34.80), 20000, 100000, 0.15, 'A victory'),
  (8,  1,  'Battle of Red Cliffs', '赤壁之战', '赤壁', 208, POINT(114.20, 29.98), 50000, 220000, 0.1, 'A victory'),
  (9,  2,  'Battle of Fei River', '淝水之战', '淝水', 383, POINT(116.35, 33.30), 80000, 270000, 0.05, 'A victory'),
  (10, 13, 'Battle of Manzikert', '曼齐刻尔特战役', 'マンジケルト', 1071, POINT(42.55, 38.60), 20000, 35000, 0.25, 'B victory'),
  (11, 11, 'Battle of Austerlitz', '奥斯特里茨战役', 'アウステルリッツ', 1805, POINT(16.64, 49.13), 68000, 90000, 0.2, 'A victory'),
  (12, 11, 'Battle of Waterloo', '滑铁卢战役', 'ワーテルロー', 1815, POINT(4.36, 50.68), 72000, 118000, 0.35, 'B victory'),
  (13, 12, 'Siege of Yorktown', '约克镇围城战', 'ヨークタウン', 1781, POINT(-76.46, 37.24), 17000, 9000, 0.1, 'A victory'),
  (14, 7,  'Battle of Hattin', '哈丁战役', 'ハッティーン', 1187, POINT(35.45, 32.81), 20000, 30000, 0.2, 'B victory'),
  (15, 13, 'Battle of Tours', '图尔战役', 'トゥール', 732, POINT(0.68, 47.39), 30000, 40000, 0.15, 'A victory'),
  (16, 14, 'Fall of Constantinople', '君士坦丁堡攻城战', 'コンスタンティノープル', 1453, POINT(28.98, 41.01), 8000, 80000, 0.6, 'B victory');

INSERT INTO battles (war_id, name_en, name_zh, name_ja, battle_date, coord, troops_a, troops_b, casualty_ratio, outcome)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 144
)
SELECT
  1 + (i % 40),
  CONCAT('Battle ', i + 16),
  CONCAT('战役', i + 16),
  CONCAT('合戦', i + 16),
  -800 + i * 19,
  POINT(90 + (i % 60), 20 + (i % 40)),
  5000 + (i % 200) * 500,
  5000 + ((i * 7) % 200) * 500,
  ROUND(0.05 + (i % 12) * 0.03, 2),
  ELT(1 + (i % 5), 'A victory', 'B victory', 'stalemate', 'inconclusive', 'unknown')
FROM seq
WHERE i <= 144;

INSERT INTO treaties
  (id, war_id, name_en, name_zh, name_ja, sign_year, parties) VALUES
  (1, 4,  'Treaty of Nerchinsk', '尼布楚条约', 'ネルチンスク条約', 1689, '清朝/俄罗斯'),
  (2, 15, 'Treaty of Kadesh', '卡迭什和约', 'カデシュ条約', -1259, '埃及/赫梯'),
  (3, NULL, 'Peace of Westphalia', '威斯特伐利亚和约', 'ヴェストファーレン条約', 1648, '欧洲诸国'),
  (4, 16, 'Treaty of Troyes', '特鲁瓦条约', 'トロワ条約', 1420, '英格兰/法兰西'),
  (5, 11, 'Treaty of Campo Formio', '坎波福米奥条约', 'カンポ・フォルミオ条約', 1797, '法国/奥地利'),
  (6, 12, 'Treaty of Paris (1783)', '巴黎和约（1783）', 'パリ条約', 1783, '美国/英国');

INSERT INTO treaties (war_id, name_en, name_zh, name_ja, sign_year, parties)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 34
)
SELECT
  CASE WHEN i % 4 = 0 THEN NULL ELSE 1 + (i % 40) END,
  CONCAT('Foederis Pactum ', i + 6),
  CONCAT('和约', i + 6),
  CONCAT('条約', i + 6),
  -500 + i * 53,
  CONCAT('Parties of treaty ', i + 6)
FROM seq;

-- ---------- 文书与典籍 ----------

INSERT INTO documents
  (id, region_id, era_id, author_figure_id, title_en, title_zh, lang, material, archive_hid, body, issued_year) VALUES
  (1, 1, 2, NULL, 'Qin Stipulated Law', '秦律（云梦简）', 'zh', 'bamboo', UNHEX(REPEAT('A1', 16)),
   '凡律令，明著之于官府，黔首莫敢犯禁。', -221),
  (2, 9, 2, NULL, 'Twelve Tables', '十二铜表法', 'la', 'stone', UNHEX(REPEAT('B2', 16)),
   'Lex duodecim tabularum, fons omnis publici privatique iuris.', -450),
  (3, 10, 3, NULL, 'Magna Carta', '大宪章', 'en', 'parchment', UNHEX(REPEAT('C3', 16)),
   'No free man shall be seized or imprisoned except by the lawful judgment of peers.', 1215),
  (4, 10, 4, NULL, 'Declaration of Independence', '独立宣言', 'en', 'paper', UNHEX(REPEAT('D4', 16)),
   'We hold these truths to be self-evident, that all men are created equal...', 1776),
  (5, 10, 5, NULL, 'Napoleonic Code', '拿破仑法典', 'fr', 'paper', UNHEX(REPEAT('E5', 16)),
   'Le droit de propriété est inviolable et sacré.', 1804),
  (6, 7, 2, NULL, 'Code of Hammurabi', '汉谟拉比法典', 'la', 'stone', UNHEX(REPEAT('F6', 16)),
   'An eye for an eye, a tooth for a tooth.', -1754),
  (7, 10, 5, NULL, 'Declaration of the Rights of Man', '人权宣言', 'fr', 'paper', UNHEX(REPEAT('07', 16)),
   'Les hommes naissent et demeurent libres et égaux en droits.', 1789),
  (8, 10, 5, NULL, 'Communist Manifesto', '共产党宣言', 'de', 'paper', UNHEX(REPEAT('18', 16)),
   'Workers of the world, unite! You have nothing to lose but your chains!', 1848),
  (9, 1, 2, NULL, 'Art of War', '孙子兵法', 'zh', 'bamboo', UNHEX(REPEAT('29', 16)),
   '知己知彼，百战不殆。', -512),
  (10, 1, 2, NULL, 'Discourse on Salt and Iron', '盐铁论', 'zh', 'bamboo', UNHEX(REPEAT('3A', 16)),
   '闭关自守则国贫，通流则国富。', -81);

INSERT INTO documents (region_id, era_id, author_figure_id, title_en, title_zh, lang, material, archive_hid, body, issued_year)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 90
)
SELECT
  1 + (i % 12),
  1 + (i % 6),
  CASE WHEN i % 5 = 0 THEN 1 + (i % 48) ELSE NULL END,
  CONCAT('Document ', i + 10),
  CONCAT('文书', i + 10),
  ELT(1 + (i % 5), 'zh', 'la', 'en', 'fr', 'ru'),
  ELT(1 + (i % 5), 'bamboo', 'bronze', 'papyrus', 'parchment', 'paper'),
  UNHEX(LPAD(HEX(i + 10), 32, '0')),
  CONCAT('Body text of document #', i + 10,
         '。中文正文。Litterae Latinae. Русский текст.'),
  -800 + i * 31
FROM seq
WHERE i <= 90;

INSERT INTO literary_works
  (id, author_figure_id, dynasty_id, title_en, title_zh, title_ja, title_ru, lang, genre, written_year, source_hid, excerpt) VALUES
  (1,  NULL, NULL, 'Shi Jing (Book of Songs)', '诗经', '詩経', 'Шицзин', 'zh', 'poetry', -600, UNHEX(REPEAT('4B', 16)),
   '关关雎鸠，在河之洲。窈窕淑女，君子好逑。'),
  (2,  NULL, NULL, 'I Ching', '周易', '易経', 'Ицзин', 'zh', 'philosophy', -800, UNHEX(REPEAT('5C', 16)),
   '天行健，君子以自强不息。'),
  (3,  34, 2, 'Records of the Grand Historian', '史记', '史記', 'Ши цзи', 'zh', 'chronicle', -91, UNHEX(REPEAT('6D', 16)),
   '究天人之际，通古今之变，成一家之言。'),
  (4,  NULL, 6, 'Romance of the Three Kingdoms', '三国演义', '三国志演義', 'Троецарствие', 'zh', 'novel', 1522, UNHEX(REPEAT('7E', 16)),
   '天下大势，分久必合，合久必分。'),
  (5,  NULL, 6, 'Journey to the West', '西游记', '西遊記', 'Путешествие на Запад', 'zh', 'novel', 1592, UNHEX(REPEAT('8F', 16)),
   '我自长安去，取经西蜀来。'),
  (6,  NULL, 7, 'Dream of the Red Chamber', '红楼梦', '紅楼夢', 'Сон в красном тереме', 'zh', 'novel', 1791, UNHEX(REPEAT('90', 16)),
   '满纸荒唐言，一把辛酸泪。'),
  (7,  NULL, NULL, 'Iliad', '伊利亚特', 'イーリアス', 'Илиада', 'la', 'epic', -750, UNHEX(REPEAT('A1', 16)),
   'Sing, O goddess, the anger of Achilles son of Peleus.'),
  (8,  NULL, NULL, 'Odyssey', '奥德赛', 'オデュッセイア', 'Одиссея', 'la', 'epic', -725, UNHEX(REPEAT('B2', 16)),
   'Tell me, O Muse, of that ingenious hero who travelled far and wide.'),
  (9,  NULL, NULL, 'The Tale of Genji', '源氏物語', '源氏物語', 'Повесть о Гэндзи', 'ja', 'novel', 1008, UNHEX(REPEAT('C3', 16)),
   'ゆく河の流れは絶えずして、しかも本の水にあらず。'),
  (10, 22, NULL, 'Divine Comedy', '神曲', '神曲', 'Божественная комедия', 'la', 'epic', 1321, UNHEX(REPEAT('D4', 16)),
   'Abandon all hope, ye who enter here.'),
  (11, NULL, NULL, 'Hamlet', '哈姆雷特', 'ハムレット', 'Гамлет', 'en', 'drama', 1603, UNHEX(REPEAT('E5', 16)),
   'To be, or not to be, that is the question.'),
  (12, 15, NULL, 'Analects', '论语', '論語', 'Луньюй', 'zh', 'philosophy', -479, UNHEX(REPEAT('F6', 16)),
   '学而时习之，不亦说乎。');

INSERT INTO literary_works (author_figure_id, dynasty_id, title_en, title_zh, title_ja, title_ru, lang, genre, written_year, source_hid, excerpt)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 88
)
SELECT
  CASE WHEN i % 4 = 0 THEN 1 + (i % 48) ELSE NULL END,
  CASE WHEN i % 3 = 0 THEN 1 + (i % 40) ELSE NULL END,
  CONCAT('Liber ', i + 12),
  CONCAT('典籍', i + 12),
  CONCAT('書物', i + 12),
  CONCAT('Книга ', i + 12),
  ELT(1 + (i % 6), 'zh', 'la', 'en', 'ja', 'ru', 'la'),
  ELT(1 + (i % 6), 'epic', 'drama', 'poetry', 'essay', 'chronicle', 'philosophy'),
  -1000 + i * 37,
  UNHEX(LPAD(HEX(i + 12), 32, '0')),
  CONCAT('Excerpt of work #', i + 12, '。摘录中文。Excerptum Latinum.')
FROM seq
WHERE i <= 88;

-- ---------- 发明 / 思想 / 宗教 / 神话 ----------

INSERT INTO inventions (region_id, dynasty_id, inventor_id, name_en, name_zh, name_ja, year, field, description, is_four_great) VALUES
  (1, 2, NULL, 'Papermaking', '造纸术', '製紙術', -105, 'print', '蔡伦改进造纸。', TRUE),
  (1, 3, NULL, 'Woodblock printing', '雕版印刷', '木版印刷', 618, 'print', '佛教经卷刻印。', TRUE),
  (1, 3, NULL, 'Gunpowder', '火药', '火薬', 800, 'military', '炼丹副产，火器始祖。', TRUE),
  (1, 4, NULL, 'Compass (lodestone)', '指南针', '羅針盤', 1040, 'navigation', '司南演化。', TRUE),
  (1, 2, NULL, 'Seismoscope', '地动仪', '地動儀', 132, 'engineering', '张衡候风地动仪。', FALSE),
  (1, 3, NULL, 'Curved-shaft plow', '曲辕犁', '曲轅犁', 618, 'agriculture', '江南水田耕作效率提升。', FALSE),
  (10, NULL, 14, 'Steam engine (improved)', '改良蒸汽机', '蒸気機関', 1712, 'engineering', '工业革命动力源。', FALSE),
  (10, NULL, NULL, 'Telegraph', '电报', '電信', 1837, 'communication', '莫尔斯电码。', FALSE),
  (1, 4, NULL, 'Movable type', '活字印刷', '活版印刷', 1040, 'print', '毕昇泥活字。', FALSE),
  (10, NULL, NULL, 'Penicillin', '青霉素', 'ペニシリン', 1928, 'medicine', '真菌杀菌，抗生素之始。', FALSE);

INSERT INTO inventions (region_id, dynasty_id, inventor_id, name_en, name_zh, name_ja, year, field, description, is_four_great)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 40
)
SELECT
  1 + (i % 12),
  CASE WHEN i % 3 = 0 THEN 1 + (i % 40) ELSE NULL END,
  CASE WHEN i % 5 = 0 THEN 1 + (i % 48) ELSE NULL END,
  CONCAT('Inventio ', i + 10),
  CONCAT('发明', i + 10),
  CONCAT('発明', i + 10),
  -900 + i * 41,
  ELT(1 + (i % 7), 'military', 'navigation', 'agriculture', 'medicine', 'communication', 'print', 'engineering'),
  CONCAT('演示发明 #', i + 10),
  (i % 11 = 0)
FROM seq
WHERE i <= 40;

INSERT INTO schools_of_thought (region_id, founder_id, name_en, name_zh, name_ja, classification, tenet, flourished) VALUES
  (1, 15, 'Confucianism', '儒家', '儒教', 'philosophy', '仁政礼治，修身齐家治国平天下', '春秋-汉'),
  (1, 16, 'Taoism', '道家', '道家', 'philosophy', '道法自然，无为而治', '春秋-汉'),
  (1, NULL, 'Legalism', '法家', '法家', 'political', '以法治国，奖励耕战', '战国'),
  (1, 18, 'Mohism', '墨家', '墨家', 'philosophy', '兼爱非攻，尚贤尚同', '战国'),
  (1, NULL, 'School of Military', '兵家', '兵家', 'military', '兵者诡道，百战不殆', '春秋'),
  (9, NULL, 'Stoicism', '斯多葛学派', 'ストア派', 'philosophy', '顺应自然，德性即幸福', '希腊化'),
  (9, NULL, 'Epicureanism', '伊壁鸠鲁学派', 'エピクロス派', 'philosophy', '快乐至善，原子论', '希腊化'),
  (10, NULL, 'Scholasticism', '经院哲学', 'スコラ学', 'philosophy', '信仰寻求理解', '中世纪'),
  (10, 41, 'Empiricism', '经验主义', '経験論', 'science', '知识源于感觉经验', '近代'),
  (4, NULL, 'Vedanta', '吠檀多哲学', 'ヴェーダーンタ', 'philosophy', '梵我一如', '古代');

INSERT INTO schools_of_thought (region_id, founder_id, name_en, name_zh, name_ja, classification, tenet, flourished)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 30
)
SELECT
  1 + (i % 12),
  CASE WHEN i % 5 = 0 THEN 1 + (i % 48) ELSE NULL END,
  CONCAT('Secta ', i + 10),
  CONCAT('学派', i + 10),
  CONCAT('学派', i + 10),
  ELT(1 + (i % 6), 'philosophy', 'religion', 'military', 'political', 'economic', 'science'),
  CONCAT('Tenet of school #', i + 10),
  CONCAT('Flourished ', i + 10)
FROM seq
WHERE i <= 30;

INSERT INTO religions (region_id, name_en, name_zh, name_ja, classification, founded_year, followers_est, sacred_text) VALUES
  (4, 'Buddhism', '佛教', '仏教', 'non-theistic', -483, 520000000, '三藏'),
  (1, 'Taoism', '道教', '道教', 'polytheistic', 142, 12000000, '道德经'),
  (7, 'Christianity', '基督教', 'キリスト教', 'monotheistic', 33, 2400000000, '圣经'),
  (7, 'Islam', '伊斯兰教', 'イスラム教', 'monotheistic', 610, 1900000000, '古兰经'),
  (4, 'Hinduism', '印度教', 'ヒンドゥー教', 'polytheistic', -1500, 1200000000, '吠陀'),
  (7, 'Judaism', '犹太教', 'ユダヤ教', 'monotheistic', -1300, 15000000, '妥拉'),
  (2, 'Shinto', '神道教', '神道', 'animistic', -300, 100000000, '古事记/日本书纪'),
  (5, 'Zoroastrianism', '琐罗亚斯德教', 'ゾロアスター教', 'dualistic', -1500, 100000, '阿维斯陀');

INSERT INTO religions (region_id, name_en, name_zh, name_ja, classification, founded_year, followers_est, sacred_text)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 22
)
SELECT
  1 + (i % 12),
  CONCAT('Religio ', i + 8),
  CONCAT('教派', i + 8),
  CONCAT('宗教', i + 8),
  ELT(1 + (i % 6), 'monotheistic', 'polytheistic', 'henotheistic', 'non-theistic', 'animistic', 'dualistic'),
  -1500 + i * 87,
  (i % 8) * 1000000,
  CONCAT('Sacred text of religion #', i + 8)
FROM seq
WHERE i <= 22;

INSERT INTO mythologies (id, region_id, name_en, name_zh, culture) VALUES
  (1, 1,  'Chinese mythology', '中华神话', '黄河-长江文明'),
  (2, 2,  'Japanese mythology', '日本神话', '古坟-大和'),
  (3, 8,  'Greek mythology', '希腊神话', '爱琴文明'),
  (4, 9,  'Roman mythology', '罗马神话', '拉丁姆'),
  (5, 11, 'Norse mythology', '北欧神话', '斯堪的纳维亚'),
  (6, 6,  'Egyptian mythology', '埃及神话', '尼罗河'),
  (7, 7,  'Mesopotamian mythology', '美索不达米亚神话', '两河'),
  (8, 12, 'Maya mythology', '玛雅神话', '尤卡坦');

INSERT INTO mythologies (region_id, name_en, name_zh, culture)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 12
)
SELECT
  1 + (i % 12),
  CONCAT('Mythologia ', i + 8),
  CONCAT('神话', i + 8),
  CONCAT('Cultura ', i + 8)
FROM seq
WHERE i <= 12;

INSERT INTO deities (mythology_id, name_en, name_zh, name_ja, name_ru, name_la, domains, worship_index, attributes) VALUES
  (2,  'Amaterasu', '天照大神', '天照大御神', 'Аматэрасу', 'Amaterasu', 'sun', 0.95,
    JSON_OBJECT('beast', '三足乌', 'role', '太阳女神')),
  (2,  'Susanoo', '须佐之男', '須佐之男命', 'Сусаноо', 'Susanus', 'thunder,sea', 0.8,
    JSON_OBJECT('beast', '八岐大蛇', 'role', '风暴神')),
  (5,  'Odin', '奥丁', 'オーディン', 'Один', 'Odinus', 'war,wisdom', 0.9,
    JSON_OBJECT('beast', '八足神骏斯莱普尼尔', 'role', '众神之父')),
  (5,  'Thor', '托尔', 'トール', 'Тор', 'Thor', 'thunder', 0.85,
    JSON_OBJECT('beast', '山羊坦格里斯尼尔', 'role', '雷神')),
  (5,  'Loki', '洛基', 'ロキ', 'Локи', 'Locius', 'sky', 0.75,
    JSON_OBJECT('beast', '巨狼芬里厄之父', 'role', '诡计之神')),
  (6,  'Ra', '拉', 'ラー', 'Ра', 'Ra', 'sun', 0.9,
    JSON_OBJECT('beast', '圣甲虫', 'role', '太阳神')),
  (6,  'Anubis', '阿努比斯', 'アヌビス', 'Анубис', 'Anubis', 'death,underworld', 0.8,
    JSON_OBJECT('beast', '胡狼', 'role', '冥界引渡')),
  (3,  'Zeus', '宙斯', 'ゼウス', 'Зевс', 'Iuppiter', 'sky,thunder', 1.0,
    JSON_OBJECT('beast', '雄鹰', 'role', '众神之王')),
  (3,  'Poseidon', '波塞冬', 'ポセイドン', 'Посейдон', 'Neptunus', 'sea', 0.85,
    JSON_OBJECT('beast', '海豚', 'role', '海神')),
  (3,  'Apollo', '阿波罗', 'アポロン', 'Аполлон', 'Apollo', 'wisdom,sun', 0.88,
    JSON_OBJECT('beast', '渡鸦', 'role', '光明与艺术之神')),
  (1,  'Jade Emperor', '玉皇大帝', '玉皇大帝', 'Юйхуан', 'Imperator Iaspi', 'sky', 0.92,
    JSON_OBJECT('beast', '龙', 'role', '天庭主宰')),
  (1,  'Fu Xi', '伏羲', '伏羲', 'Фуси', 'Fu Xi', 'nature', 0.78,
    JSON_OBJECT('beast', '龟', 'role', '人文始祖'));

INSERT INTO deities (mythology_id, name_en, name_zh, name_ja, name_ru, name_la, domains, worship_index, attributes)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 88
)
SELECT
  1 + (i % 20),
  CONCAT('Deus ', i + 12),
  CONCAT('神灵', i + 12),
  CONCAT('神', i + 12),
  CONCAT('Бог ', i + 12),
  CONCAT('Divinitas ', i + 12),
  ELT(1 + (i % 6), 'sky', 'war', 'wisdom', 'death', 'sea', 'nature'),
  ROUND(0.3 + (i % 6) * 0.1, 2),
  JSON_OBJECT('code', i + 12)
FROM seq
WHERE i <= 88;

-- ---------- 遗址 / 文物 / 博物馆 ----------

INSERT INTO archaeological_sites
  (id, region_id, name_en, name_zh, name_ja, coord, found_year, excavator, description) VALUES
  (1, 1,  'Mausoleum of the First Qin Emperor', '秦始皇帝陵（兵马俑）', '秦始皇帝陵', POINT(109.27, 34.38), 1974, '赵康民', '八千陶俑守卫。'),
  (2, 1,  'Yinxu', '殷墟', '殷墟', POINT(114.31, 36.07), 1899, '王懿荣', '甲骨文出土地。'),
  (3, 1,  'Sanxingdui', '三星堆', '三星堆', POINT(104.19, 30.99), 1929, '广汉农民', '古蜀文明青铜重器。'),
  (4, 9,  'Pompeii', '庞贝古城', 'ポンペイ', POINT(14.48, 40.75), 1748, 'Rocco Gioacchino de Alcubierre', '火山灰封存。'),
  (5, 8,  'Troy', '特洛伊', 'トロイ', POINT(26.24, 39.96), 1871, 'Heinrich Schliemann', '荷马史诗之城。'),
  (6, 7,  'Petra', '佩特拉', 'ペトラ', POINT(35.44, 30.33), 1812, 'Johann Ludwig Burckhardt', '岩石之城。'),
  (7, 4,  'Angkor Wat', '吴哥窟', 'アンコール・ワット', POINT(103.87, 13.41), 1860, 'Henri Mouhot', '高棉帝国神庙。'),
  (8, 12, 'Machu Picchu', '马丘比丘', 'マチュ・ピチュ', POINT(-72.53, -13.16), 1911, 'Hiram Bingham', '天空之城。'),
  (9, 10, 'Stonehenge', '巨石阵', 'ストーンヘンジ', POINT(-1.83, 51.18), 1620, 'Inigo Jones', '史前巨石。'),
  (10, 6, 'Tomb of Tutankhamun', '图坦卡蒙墓', 'ツタンカーメンの墓', POINT(32.60, 25.74), 1922, 'Howard Carter', '法老金棺。');

INSERT INTO archaeological_sites (region_id, name_en, name_zh, name_ja, coord, found_year, excavator, description)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 50
)
SELECT
  1 + (i % 12),
  CONCAT('Situs ', i + 10),
  CONCAT('遗址', i + 10),
  CONCAT('遺跡', i + 10),
  POINT(60 + (i % 100), 0 + (i % 60)),
  1800 + (i % 200),
  CONCAT('Excavator ', i),
  CONCAT('演示遗址 #', i + 10)
FROM seq
WHERE i <= 50;

INSERT INTO relics
  (id, dynasty_id, discovered_site_id, name_en, name_zh, name_ja, material, geodata, excavated_year, appraisal, description) VALUES
  (1,  NULL, 2, 'Houmuwu Ding', '司母戊鼎', '后母戊鼎', 'bronze', UNHEX(REPEAT('AA', 16)), 1939, 10000000.00, '商代最大青铜鼎。'),
  (2,  NULL, 2, 'Sword of Goujian', '越王勾践剑', '越王勾践剣', 'bronze', UNHEX(REPEAT('BB', 16)), 1965, 20000000.00, '两千五百年不锈。'),
  (3,  2, NULL, 'Plain Gauze Gown of Mawangdui', '马王堆素纱襌衣', '長沙馬王堆の素紗禅衣', 'silk', UNHEX(REPEAT('CC', 16)), 1972, 50000000.00, '不足一两。'),
  (4,  NULL, 2, 'Zenghouyi Bianzhong', '曾侯乙编钟', '曾侯乙編鐘', 'bronze', UNHEX(REPEAT('DD', 16)), 1978, 150000000.00, '一钟双音。'),
  (5,  NULL, NULL, 'Rosetta Stone', '罗塞塔石碑', 'ロゼッタストーン', 'stone', UNHEX(REPEAT('EE', 16)), 1799, 500000000.00, '破译古埃及文。'),
  (6,  NULL, 10, 'Tutankhamun''s Golden Mask', '图坦卡蒙黄金面具', 'ツタンカーメンの黄金のマスク', 'gold', UNHEX(REPEAT('FF', 16)), 1922, 800000000.00, '埃及镇国之宝。'),
  (7,  NULL, NULL, 'Stele of Hammurabi', '汉谟拉比法典石碑', 'ハンムラビ法典碑', 'stone', UNHEX(REPEAT('11', 16)), 1901, 100000000.00, '竖起2800年。'),
  (8,  1, 1, 'Bronze Chariots of the Qin', '秦陵铜车马', '秦の銅車馬', 'bronze', UNHEX(REPEAT('22', 16)), 1980, 200000000.00, '半米见方精致如真。'),
  (9,  NULL, NULL, 'Liangzhu Jade Cong', '良渚玉琮', '良渚玉琮', 'jade', UNHEX(REPEAT('33', 16)), 1987, 30000000.00, '神人兽面纹。'),
  (10, NULL, 2, 'He Zun (' 'zhongguo' ' vessel)', '何尊（最早“中国”）', '何尊', 'bronze', UNHEX(REPEAT('44', 16)), 1963, 120000000.00, '铭文有“宅兹中国”。');

INSERT INTO relics (dynasty_id, discovered_site_id, name_en, name_zh, name_ja, material, geodata, excavated_year, appraisal, description)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 90
)
SELECT
  CASE WHEN i % 4 = 0 THEN 1 + (i % 40) ELSE NULL END,
  CASE WHEN i % 3 = 0 THEN 1 + (i % 60) ELSE NULL END,
  CONCAT('Reliquia ', i + 10),
  CONCAT('文物', i + 10),
  CONCAT('遺物', i + 10),
  ELT(1 + (i % 5), 'bronze', 'jade', 'gold', 'pottery', 'stone'),
  UNHEX(LPAD(HEX(i + 10), 32, '0')),
  1950 + (i % 70),
  ROUND((i % 90 + 1) * 10000.0, 2),
  CONCAT('演示文物 #', i + 10)
FROM seq
WHERE i <= 90;

INSERT INTO museums (id, region_id, name_en, name_zh, city, established, admission, url) VALUES
  (1, 1,  'Palace Museum (Forbidden City)', '故宫博物院', '北京', 1925, 60.00, 'https://www.dpm.org.cn'),
  (2, 1,  'National Museum of China', '中国国家博物馆', '北京', 2003, 0.00, 'https://www.chnmuseum.cn'),
  (3, 1,  'Shanghai Museum', '上海博物馆', '上海', 1952, 0.00, 'https://www.shanghaimuseum.net'),
  (4, 10, 'Louvre', '卢浮宫', '巴黎', 1793, 22.00, 'https://www.louvre.fr'),
  (5, 10, 'British Museum', '大英博物馆', '伦敦', 1753, 0.00, 'https://www.britishmuseum.org'),
  (6, 10, 'Metropolitan Museum of Art', '大都会艺术博物馆', '纽约', 1870, 30.00, 'https://www.metmuseum.org'),
  (7, 2,  'Tokyo National Museum', '东京国立博物馆', '东京', 1872, 1000.00, 'https://www.tnm.jp'),
  (8, 6,  'Egyptian Museum', '埃及博物馆', '开罗', 1902, 6.00, 'https://www.egyptianmuseum.org');

INSERT INTO museums (region_id, name_en, name_zh, city, established, admission, url)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 42
)
SELECT
  1 + (i % 12),
  CONCAT('Museum ', i + 8),
  CONCAT('博物馆', i + 8),
  CONCAT('Museum City ', i),
  1800 + (i % 200),
  ROUND((i % 50), 2),
  CONCAT('https://museum.example/', i + 8)
FROM seq
WHERE i <= 42;

INSERT INTO museum_holdings (museum_id, relic_id, acquired, collection)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 100
)
SELECT
  1 + (i % 50),
  1 + (i % 100),
  DATE_ADD('1900-01-01', INTERVAL (i * 137) DAY),
  CONCAT('Collection ', 1 + (i % 8))
FROM seq
WHERE i <= 100;

-- ---------- 货币 / 建筑 ----------

INSERT INTO currencies (id, region_id, dynasty_id, name_en, name_zh, code, introduced, demonetized, subdivision) VALUES
  (1, 1, 1,  'Banliang', '秦半两', 'QBL', -221, -118, '两'),
  (2, 1, 2,  'Wuzhu', '五铢钱', 'WZC', -118, 621, '铢'),
  (3, 1, 3,  'Kaiyuan Tongbao', '开元通宝', 'KYT', 621, 907, '文'),
  (4, 1, 4,  'Jiaozi', '交子（纸币）', 'JZI', 1023, 1279, '贯'),
  (5, 1, 6,  'Da Ming Baochao', '大明宝钞', 'DMB', 1375, 1450, '贯'),
  (6, 8, NULL, 'Drachma', '德拉克马', 'DRC', -550, -30, '奥波勒斯'),
  (7, 9, 8,  'Aureus', '奥雷（金币）', 'AUR', -27, 294, '第纳里乌斯'),
  (8, 7, NULL, 'Dinar', '第纳尔', 'DNR', 696, 1200, '迪拉姆');

INSERT INTO currencies (region_id, dynasty_id, name_en, name_zh, code, introduced, demonetized, subdivision)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 32
)
SELECT
  1 + (i % 12),
  CASE WHEN i % 4 = 0 THEN 1 + (i % 40) ELSE NULL END,
  CONCAT('Nummus ', i + 8),
  CONCAT('钱币', i + 8),
  ELT(1 + (i % 5), 'CNY', 'JRY', 'RUB', 'EUR', 'AUR'),
  1800 + (i % 200),
  NULL,
  CONCAT('Sub ', i)
FROM seq
WHERE i <= 32;

INSERT INTO buildings (region_id, dynasty_id, name_en, name_zh, name_ja, built_year, style, lat, lng, height_m) VALUES
  (1, NULL, 'Great Wall (Ming sections)', '长城（明长城）', '万里の長城', NULL, 'ming', 40.43, 116.57, 8.0),
  (1, 1,  'Epang Palace (site)', '阿房宫', '阿房宮', -212, 'han', 34.26, 108.72, NULL),
  (1, 6,  'Forbidden City', '紫禁城', '紫禁城', 1420, 'ming', 39.91, 116.39, 35.5),
  (1, NULL, 'Dujiangyan Irrigation System', '都江堰', '都江堰', -256, 'other', 31.00, 103.61, NULL),
  (8, NULL, 'Parthenon', '帕特农神庙', 'パルテノン神殿', -432, 'classical', 37.97, 23.72, 13.7),
  (9, 8,  'Colosseum', '罗马斗兽场', 'コロッセオ', 80, 'classical', 41.89, 12.49, 48.0),
  (9, 10, 'Hagia Sophia', '圣索菲亚大教堂', 'アヤソフィア', 532, 'other', 41.01, 28.98, 55.6),
  (4, NULL, 'Taj Mahal', '泰姬陵', 'タージ・マハル', 1648, 'other', 27.17, 78.04, 73.0);

INSERT INTO buildings (region_id, dynasty_id, name_en, name_zh, name_ja, built_year, style, lat, lng, height_m)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 42
)
SELECT
  1 + (i % 12),
  CASE WHEN i % 5 = 0 THEN 1 + (i % 40) ELSE NULL END,
  CONCAT('Aedificium ', i + 8),
  CONCAT('建筑', i + 8),
  CONCAT('建築', i + 8),
  -500 + i * 71,
  ELT(1 + (i % 7), 'gothic', 'baroque', 'classical', 'han', 'tang', 'ming', 'modern'),
  ROUND(-30 + (i % 80) + i * 0.05, 2),
  ROUND(20 + (i % 100) + i * 0.05, 2),
  ROUND(10 + (i % 80), 2)
FROM seq
WHERE i <= 42;

-- ---------- 远征与发现，地图 ----------

INSERT INTO expeditions (id, leader_figure_id, region_id, name_en, name_zh, name_ja, start_year, end_year,
                         departure, ships_count, crew_count, route_desc) VALUES
  (1, 12, 1, 'Zheng He''s Treasure Voyages', '郑和下西洋', '鄭和の南海遠征', 1405, 1433, POINT(118.80, 32.06), 62, 27000, '南京-东南亚-印度洋-东非'),
  (2, 24, 10, 'First Voyage of Columbus', '哥伦布首航', 'コロンブス第一回航海', 1492, 1493, POINT(-6.26, 36.83), 3, 90, '帕洛斯-加勒比海'),
  (3, 25, 10, 'Magellan Expedition', '麦哲伦环球', 'マゼラン世界周航', 1519, 1522, POINT(-6.26, 36.83), 5, 270, '大西洋-麦哲伦海峡-太平洋'),
  (4, NULL, 10, 'Vasco da Gama Route to India', '达伽马印度航线', 'ヴァスコ・ダ・ガマ', 1497, 1499, POINT(-9.14, 38.72), 4, 170, '里斯本-好望角-卡利卡特'),
  (5, 23, 10, 'Cook''s First Pacific Voyage', '库克首次太平洋航行', 'クック第一回航海', 1768, 1771, POINT(-0.13, 51.51), 1, 94, '普利茅斯-塔希提-新西兰'),
  (6, NULL, 1, 'Faxian''s Pilgrimage to India', '法显西行', '法顕の求法', 399, 412, POINT(34.75, 36.18), NULL, 4, '长安-印度-斯里兰卡');

INSERT INTO expeditions (leader_figure_id, region_id, name_en, name_zh, name_ja, start_year, end_year,
                         departure, ships_count, crew_count, route_desc)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 24
)
SELECT
  CASE WHEN i % 4 = 0 THEN 1 + (i % 48) ELSE NULL END,
  1 + (i % 12),
  CONCAT('Expeditio ', i + 6),
  CONCAT('远征', i + 6),
  CONCAT('遠征', i + 6),
  1000 + i * 29,
  1000 + i * 29 + 3,
  POINT(100 + (i % 50), 30 + (i % 30)),
  1 + (i % 12),
  50 + (i * 37 % 500),
  CONCAT('Demo route #', i + 6)
FROM seq
WHERE i <= 24;

INSERT INTO discoveries (expedition_id, region_id, name_en, name_zh, year, field, note) VALUES
  (2, 12, 'American continent (for Europe)', '美洲大陆', 1492, 'geography', '大航海新大陆。'),
  (3, 11, 'Earth confirmed spherical by voyage', '环球航行证实地圆', 1522, 'geography', '麦哲伦船队完成环球。'),
  (NULL, 10, 'Universal gravitation', '万有引力', 1687, 'physics', '牛顿定律集大成。'),
  (NULL, 10, 'Galilean astronomical observations', '伽利略天文观测', 1610, 'astronomy', '木星卫星与月面。'),
  (NULL, 10, 'Penicillin', '青霉素', 1928, 'medicine', '细菌学转折。'),
  (NULL, 1, 'Oracle bone script identified', '甲骨文辨识', 1899, 'archaeology', '王懿荣发现。'),
  (2, 12, 'Maize introduction to Eurasia', '玉米引入欧亚', 1520, 'geography', '美洲作物全球传播。'),
  (NULL, 6, 'Rosetta Stone deciphered', '罗塞塔石碑破译', 1822, 'archaeology', '商博良释读圣书字。');

INSERT INTO discoveries (expedition_id, region_id, name_en, name_zh, year, field, note)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 42
)
SELECT
  CASE WHEN i % 3 = 0 THEN 1 + (i % 30) ELSE NULL END,
  1 + (i % 12),
  CONCAT('Inventio Nova ', i + 8),
  CONCAT('发现', i + 8),
  1000 + i * 25,
  ELT(1 + (i % 8), 'geography', 'biology', 'astronomy', 'physics', 'chemistry', 'archaeology', 'medicine', 'cartography'),
  CONCAT('演示发现 #', i + 8)
FROM seq
WHERE i <= 42;

INSERT INTO maps (region_id, cartographer_id, title_en, title_zh, produced_year, projection, source_hid) VALUES
  (1, NULL, 'Yu Gong Nine Provinces Map', '《禹贡》九州图', -500, 'azimuthal', UNHEX(REPEAT('77', 16))),
  (1, NULL, 'Zheng He Nautical Chart', '郑和航海图', 1405, 'hybrid', UNHEX(REPEAT('88', 16))),
  (9, NULL, 'Ptolemy''s Geography', '托勒密《地理学》', 150, 'conical', UNHEX(REPEAT('99', 16))),
  (10, NULL, 'Mercator World Map', '墨卡托世界地图', 1569, 'mercator', UNHEX(REPEAT('AA', 16))),
  (1, NULL, 'Kunyu Wanguo Quantu', '坤舆万国全图', 1602, 'equirectangular', UNHEX(REPEAT('BB', 16))),
  (5, NULL, 'Piri Reis Map', '皮里·雷斯地图', 1513, 'hybrid', UNHEX(REPEAT('CC', 16)));

INSERT INTO maps (region_id, cartographer_id, title_en, title_zh, produced_year, projection, source_hid)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 44
)
SELECT
  1 + (i % 12),
  CASE WHEN i % 5 = 0 THEN 1 + (i % 48) ELSE NULL END,
  CONCAT('Mappa ', i + 6),
  CONCAT('地图', i + 6),
  1000 + i * 22,
  ELT(1 + (i % 5), 'mercator', 'conical', 'equirectangular', 'azimuthal', 'hybrid'),
  UNHEX(LPAD(HEX(i + 6), 32, '0'))
FROM seq
WHERE i <= 44;

-- ---------- 大表：时间线 / 名言 / 照片 ----------

-- 时间线事件（2000 行：100 × 20）
INSERT INTO timeline_events (region_id, era_id, event_year, title_en, title_zh, title_ja, title_ru, kind, detail)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 100
),
ps (j) AS (
    SELECT 1 UNION ALL SELECT j + 1 FROM ps WHERE j < 20
)
SELECT
  1 + (((a.i - 1) * 20 + b.j) % 35),
  1 + (((a.i - 1) * 20 + b.j) % 26),
  -1800 + (a.i - 1) * 20 + b.j,
  CONCAT('Timeline entry ', (a.i - 1) * 20 + b.j),
  CONCAT('时间线事件 ', (a.i - 1) * 20 + b.j),
  CONCAT('年表の出来事 ', (a.i - 1) * 20 + b.j),
  CONCAT('Событие хроники ', (a.i - 1) * 20 + b.j),
  ELT(1 + (((a.i - 1) * 20 + b.j) % 8), 'war', 'politics', 'culture', 'science', 'economy', 'religion', 'disaster', 'misc'),
  CONCAT('Demonstration timeline detail #', (a.i - 1) * 20 + b.j,
         '. 中文细节。Detalje Latinum.')
FROM seq a
CROSS JOIN ps b;

-- 名言引用（918 行：8 手写 + 910 批量）
INSERT INTO citations (figure_id, source_work_id, quote_en, quote_zh, quote_ja, quote_ru, quote_la, lang, page_no) VALUES
  (15, 12, 'Learning without thinking is labour lost; thinking without learning is perilous.',
          '学而不思则罔，思而不学则殆。', '学びて思わざれば則ち罔し。', 'Учение без размышления бесполезно.', 'Discentia sine cogitatione vana est.', 'zh', 3),
  (34, 3,  'A man may die, but to die for the right cause is heavier than Mount Tai.',
          '人固有一死，或重于泰山，或轻于鸿毛。', '人は必ず死す。', 'Смерть одна извечна.', 'Omnes homines moriuntur.', 'zh', 1),
  (11, NULL, 'Serve the country with utmost loyalty.',
          '精忠报国。', '赤誠の忠を国に尽くす。', 'Служить родине с верностью.', 'Fide absoluta patriam servare.', 'zh', NULL),
  (22, 10, 'Abandon all hope, ye who enter here.',
          '入此门者，放弃一切希望。', 'この門を入る者は一切の望みを捨てよ。', 'Оставь надежду всяк сюда входящий.', 'Lasciate ogni speranza.', 'la', 3),
  (8,  NULL,  'The die is cast.',
          '骰子已经掷下。', '賽は投げられた。', 'Жребий брошен.', 'Alea iacta est.', 'la', NULL),
  (7,  NULL,  'An army marches on its stomach.',
          '兵马未动，粮草先行。', '兵は食と共に進む。', 'Армия марширует на желудок.', 'Exercitus ventre ducitur.', 'fr', NULL),
  (37, NULL, 'A straw sandal is lighter than a horse, how carefree I am.',
          '竹杖芒鞋轻胜马，谁怕？一蓑烟雨任平生。', '竹の杖に藁の鞋。', 'Бамбуковая клюка.', 'Solea stramenta equo leviores.', 'zh', NULL),
  (45, NULL, 'Improvement freezes at the edges of the known.',
          '已知的边界以外，改进会冻结。', '既知の縁に改善は凍れる。', 'Улучшение замирает на краю известного.', 'Emendatio in finibus notorum rigescit.', 'en', NULL);

INSERT INTO citations (figure_id, source_work_id, quote_en, quote_zh, quote_ja, quote_ru, quote_la, lang, page_no)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 910
)
SELECT
  1 + (i % 504),
  CASE WHEN i % 2 = 0 THEN 1 + (i % 100) ELSE NULL END,
  CONCAT('Very famous quotation #', i + 8, '.'),
  CONCAT('千古名言第 ', i + 8, ' 句。'),
  CONCAT('名言', i + 8),
  CONCAT('Цитата №', i + 8),
  CONCAT('Sententia ', i + 8),
  ELT(1 + (i % 5), 'zh', 'en', 'ja', 'ru', 'la'),
  1 + (i % 260)
FROM seq
WHERE i <= 910;

-- 历史照片（350 行）
INSERT INTO historical_photos (figure_id, site_id, relic_id, title_en, title_zh, filename, year, format, image) VALUES
  (1,  1, NULL, 'Terracotta Army overview', '兵马俑全景', 'terracotta-army.jpg', 1975, 'jpg', NULL),
  (8,  NULL, NULL, 'Bust of Julius Caesar', '凯撒半身像', 'caesar-bust.jpg', 1910, 'tiff', NULL),
  (12, NULL, NULL, 'Zheng He statue in Nanjing', '南京郑和雕像', 'zhenghe-statue.jpg', 1985, 'jpg', NULL),
  (NULL, 4, 6, 'Tutankhamun gold mask closeup', '图坦卡蒙面具特写', 'tutankhamun-mask.jpg', 1923, 'png', NULL);

INSERT INTO historical_photos (figure_id, site_id, relic_id, title_en, title_zh, filename, year, format, image)
WITH RECURSIVE seq (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 346
)
SELECT
  CASE WHEN i % 3 = 0 THEN 1 + (i % 504) ELSE NULL END,
  CASE WHEN i % 3 = 1 THEN 1 + (i % 60) ELSE NULL END,
  CASE WHEN i % 3 = 2 THEN 1 + (i % 100) ELSE NULL END,
  CONCAT('Photograph ', i + 4),
  CONCAT('历史照片 ', i + 4),
  CONCAT('photo_', i + 4, '.jpg'),
  1850 + (i % 170),
  ELT(1 + (i % 3), 'jpg', 'png', 'tiff'),
  NULL
FROM seq
WHERE i <= 346;
