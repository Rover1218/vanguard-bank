-- Vanguard Bank - server bridge (QBCore). The only server file that knows the framework.

Bridge = { ready = false }

local QBCore = exports['qb-core']:GetCoreObject()

local function player(src) return QBCore.Functions.GetPlayer(src) end

function Bridge.loaded(src) return player(src) ~= nil end

function Bridge.citizenid(src)
    local p = player(src)
    return p and p.PlayerData.citizenid or nil
end

local function fullName(info)
    if type(info) ~= 'table' then return nil end
    local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$')
    return name ~= '' and name or nil
end

function Bridge.name(src)
    local p = player(src)
    return (p and fullName(p.PlayerData.charinfo)) or GetPlayerName(src) or 'Unknown'
end

--- Character name for a citizenid, online or not (shown before a transfer is confirmed).
function Bridge.nameOf(citizenid)
    local online = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if online then return fullName(online.PlayerData.charinfo) end
    local raw = MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ?', { citizenid })
    local ok, info = pcall(json.decode, raw or '')
    return ok and fullName(info) or nil
end

function Bridge.money(src, account)
    local p = player(src)
    return p and (p.PlayerData.money[account] or 0) or 0
end

function Bridge.addMoney(src, account, amount, reason)
    local p = player(src)
    if not p then return false end
    return p.Functions.AddMoney(account, amount, reason) ~= false
end

--- QBCore lets 'bank' go below zero; the bank never does. Check and remove happen in one tick.
function Bridge.removeMoney(src, account, amount, reason)
    local p = player(src)
    if not p or (p.PlayerData.money[account] or 0) < amount then return false end
    return p.Functions.RemoveMoney(account, amount, reason) ~= false
end

function Bridge.sourceOf(citizenid)
    local p = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    return p and p.PlayerData.source or nil
end

local function group(src, key)
    local p = player(src)
    local data = p and p.PlayerData[key]
    if not data then return nil end
    return { name = data.name, label = data.label, isBoss = data.isboss == true }
end

function Bridge.job(src) return group(src, 'job') end
function Bridge.gang(src) return group(src, 'gang') end
function Bridge.isJob(name) return QBCore.Shared.Jobs[name] ~= nil end
function Bridge.isGang(name) return QBCore.Shared.Gangs[name] ~= nil end
function Bridge.jobLabel(name) return QBCore.Shared.Jobs[name] and QBCore.Shared.Jobs[name].label or nil end
function Bridge.gangLabel(name) return QBCore.Shared.Gangs[name] and QBCore.Shared.Gangs[name].label or nil end

function Bridge.notify(src, message, kind)
    TriggerClientEvent('QBCore:Notify', src, message, kind or 'primary', 5000)
end

function Bridge.onPlayerLoaded(handler)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(p) handler(p.PlayerData.source) end)
end
