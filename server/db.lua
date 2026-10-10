-- Vanguard Bank - tables (created automatically) and one-time flags.

Db = {}

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS vbank_accounts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        number VARCHAR(12) NOT NULL UNIQUE,
        type VARCHAR(10) NOT NULL,
        name VARCHAR(40) NOT NULL,
        owner VARCHAR(60) NULL,
        ref VARCHAR(60) NULL,
        balance BIGINT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_owner (owner),
        UNIQUE KEY uniq_ref (type, ref)
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_personal (
        citizenid VARCHAR(60) PRIMARY KEY,
        number VARCHAR(12) NOT NULL UNIQUE
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_members (
        account_id INT NOT NULL,
        citizenid VARCHAR(60) NOT NULL,
        name VARCHAR(60) NOT NULL,
        role VARCHAR(10) NOT NULL,
        PRIMARY KEY (account_id, citizenid),
        INDEX idx_member (citizenid),
        CONSTRAINT fk_vbank_members FOREIGN KEY (account_id) REFERENCES vbank_accounts (id) ON DELETE CASCADE
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_transactions (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        account VARCHAR(12) NOT NULL,
        kind VARCHAR(16) NOT NULL,
        amount BIGINT NOT NULL,
        actor VARCHAR(60) NULL,
        note VARCHAR(80) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_account (account, id)
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_pending (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(60) NOT NULL,
        amount BIGINT NOT NULL,
        note VARCHAR(80) NULL,
        INDEX idx_pending (citizenid)
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_places (
        id INT AUTO_INCREMENT PRIMARY KEY,
        kind VARCHAR(8) NOT NULL,
        label VARCHAR(40) NOT NULL,
        x DOUBLE NOT NULL,
        y DOUBLE NOT NULL,
        z DOUBLE NOT NULL,
        heading DOUBLE NOT NULL DEFAULT 0
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_meta (
        k VARCHAR(40) PRIMARY KEY,
        v VARCHAR(80) NOT NULL
    )]],
}

function Db.init()
    for _, statement in ipairs(SCHEMA) do MySQL.query.await(statement) end
end

function Db.meta(key)
    return MySQL.scalar.await('SELECT v FROM vbank_meta WHERE k = ?', { key })
end

function Db.setMeta(key, value)
    MySQL.query.await('INSERT INTO vbank_meta (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { key, value })
end
