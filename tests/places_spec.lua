local T = require('tests.lib.t')
dofile(ROOT .. '/shared/rules.lua')

-- FiveM / database stand-ins.
Config = Config or {}
Config.ServerReach = 4.0
Config.DefaultBranches = {}
Config.AdminCommand = 'bankadmin'
Config.AdminAce = 'vanguard.bank.admin'
local nextId = 0
MySQL = {
    insert = { await = function() nextId = nextId + 1; return nextId end },
    query = { await = function() return {} end },
    update = { await = function() return 1 end },
}
Db = { meta = function() return '1' end, setMeta = function() end }
local handlers = {}
Router = {
    on = function(name, fn) handlers[name] = fn end,
    ok = function(message) return { ok = true, message = message } end,
    fail = function(message) return { ok = false, message = message } end,
    log = function() end,
}
RegisterCommand = function() end
TriggerClientEvent = function() end
IsPlayerAceAllowed = function() return true end
local V = {}
V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
vector3 = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
local playerPos = { x = 0, y = 0, z = 0 }
GetPlayerPed = function() return 1 end
GetEntityCoords = function() return playerPos end
dofile(ROOT .. '/server/places.lua')

Places.load()
local branch = Places.add('branch', 'Fleeca', { x = 0, y = 0, z = 0 }, 0)
Places.add('atm', 'ATM', { x = 1.5, y = 0, z = 0 }, 0)
Places.add('atm', 'ATM', { x = 60, y = 0, z = 0 }, 0)

T.describe('Places.require', function()
    T.it('uses the branch when an ATM stands next to the counter', function()
        playerPos = { x = 1.2, y = 0, z = 0 } -- closer to the ATM than to the counter
        T.eq(Places.require(1, 'transfer'), branch)
        T.eq(Places.require(1, 'open'), branch)
    end)
    T.it('lets an ATM on its own do cash only', function()
        playerPos = { x = 60.5, y = 0, z = 0 }
        T.eq(Places.require(1, 'withdraw').kind, 'atm')
        local place, message = Places.require(1, 'transfer')
        T.eq(place, nil)
        T.eq(message, 'Go to a bank branch for that')
    end)
    T.it('refuses away from every branch and ATM', function()
        playerPos = { x = 500, y = 0, z = 0 }
        local place, message = Places.require(1, 'deposit')
        T.eq(place, nil)
        T.eq(message, 'Go to a bank branch or ATM')
    end)
end)

T.describe('placeAdd', function()
    T.it('refuses a second ATM on the same spot (clicking an ATM twice)', function()
        playerPos = { x = 60, y = 1, z = 0 }
        local result = handlers.placeAdd(1, { kind = 'atm', coords = { x = 60.2, y = 0, z = 0 }, heading = 0 })
        T.eq(result.ok, false)
        T.eq(result.message, 'There is already an ATM here')
    end)
    T.it('places another ATM a few metres away', function()
        playerPos = { x = 60, y = 1, z = 0 }
        local result = handlers.placeAdd(1, { kind = 'atm', coords = { x = 63, y = 0, z = 0 }, heading = 0 })
        T.eq(result.ok, true)
    end)
end)
