-- @connection my-blog
-- @database superheroes
-- 创建数据库
CREATE DATABASE superheroes;

-- 创建人物表
CREATE TABLE characters (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    alias VARCHAR(100),
    universe ENUM('Marvel', 'DC') NOT NULL,
    first_appearance_year INT,
    biography TEXT
);

-- 创建能力表
CREATE TABLE abilities (
    id INT AUTO_INCREMENT PRIMARY KEY,
    character_id INT,
    ability_name VARCHAR(100) NOT NULL,
    description TEXT,
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

-- 创建团队表
CREATE TABLE teams (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    universe ENUM('Marvel', 'DC') NOT NULL,
    description TEXT
);

-- 创建人物与团队关系表
CREATE TABLE character_team (
    character_id INT,
    team_id INT,
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
    FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE,
    PRIMARY KEY (character_id, team_id)
);

