-- Vanguard Bank - placed branches and ATMs. Every money action is checked against these.

Places = {}

local ANY = { branch = true, atm = true }
local BRANCH = { branch = true }
local ATM = { atm = true }
local KINDS = { branch = true, atm = true }
local PLACE_REACH = 25.0 -- an admin places within this distance of themselves
local SAME_SPOT = 1.0    -- a second branch / ATM this close to one counts as the same one
local places = {}       -- id -> { id, kind, label, x, y, z, heading }

function Places.list()
    local list = {}
    for _, place in pairs(places) do list[#list + 1] = place end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function Places.add(kind, label, coords, heading)
    local id = MySQL.insert.await('INSERT INTO vbank_places (kind, label, x, y, z, heading) VALUES (?, ?, ?, ?, ?, ?)',
        { kind, label, coords.x, coords.y, coords.z, heading or 0.0 })
    if not id then return nil end
    places[id] = { id = id, kind = kind, label = label, x = coords.x, y = coords.y, z = coords.z, heading = heading or 0.0 }
    return places[id]
end

function Places.remove(id)
    MySQL.update.await('DELETE FROM vbank_places WHERE id = ?', { id })
    places[id] = nil
end

--- Loads places; the very first time (no places, never seeded) adds Config.DefaultBranches.
function Places.load()
    places = {}
    for _, row in ipairs(MySQL.query.await('SELECT * FROM vbank_places') or {}) do places[row.id] = row end
    if next(places) == nil and not Db.meta('defaults_added') then
        for _, branch in ipairs(Config.DefaultBranches) do Places.add('branch', branch.label, branch.coords, 0.0) end
    end
    Db.setMeta('defaults_added', '1')
end

local function position(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

function Places.at(src, kinds)
    local pos = position(src)
    return pos and Rules.nearestPlace(pos, Places.list(), kinds or ANY, Config.ServerReach) or nil
end

--- The branch / ATM the player stands at, if it allows action; else nil + message.
--- A branch in reach always wins, so an ATM placed next to a counter never blocks banking there.
function Places.require(src, action)
    local branch = Places.at(src, BRANCH)
    if branch then return branch end
    local atm = Places.at(src, ATM)
    if not atm then return nil, 'Go to a bank branch or ATM' end
    if not Rules.allowedAt('atm', action) then return nil, 'Go to a bank branch for that' end
    return atm
end

function Places.broadcast(target)
    TriggerClientEvent('vanguard-bank:places', target or -1, Places.list())
end

local function isAdmin(src)
    return IsPlayerAceAllowed(src, Config.AdminAce)
end

RegisterCommand(Config.AdminCommand, function(src)
    if src == 0 or not isAdmin(src) then return end
    TriggerClientEvent('vanguard-bank:placement', src)
end, false)

Router.on('placeAdd', function(src, data)
    if not isAdmin(src) then return Router.fail('Admins only') end
    local kind = KINDS[data.kind] and data.kind or nil
    local coords = Rules.coords(data.coords)
    if not kind or not coords then return Router.fail('Aim at a spot first') end
    local here = position(src)
    if not here or #(vector3(here.x, here.y, here.z) - vector3(coords.x, coords.y, coords.z)) > PLACE_REACH then
        return Router.fail('Stand closer to the spot')
    end
    if Rules.nearestPlace(coords, Places.list(), { [kind] = true }, SAME_SPOT) then
        return Router.fail(kind == 'atm' and 'There is already an ATM here' or 'There is already a branch here')
    end
    local label = kind == 'atm' and 'ATM' or Rules.cleanText(data.label, 30)
    if not label then return Router.fail('Give the branch a name (up to 30 characters)') end
    local place = Places.add(kind, label, coords, Rules.heading(data.heading))
    if not place then return Router.fail('Could not save that spot') end
    Places.broadcast()
    Router.log(src, ('placed %s "%s" (#%d)'):format(kind, label, place.id))
    return Router.ok(('%s placed'):format(kind == 'atm' and 'ATM' or label))
end)

Router.on('placeRemove', function(src, data)
    if not isAdmin(src) then return Router.fail('Admins only') end
    local place = type(data.id) == 'number' and places[data.id] or nil
    if not place then return Router.fail('Nothing to remove there') end
    Places.remove(place.id)
    Places.broadcast()
    Router.log(src, ('removed %s "%s" (#%d)'):format(place.kind, place.label, place.id))
    return Router.ok(('%s removed'):format(place.kind == 'atm' and 'ATM' or place.label))
end)
