-- Vanguard Bank - start-up and hello.

local RESOURCE = GetCurrentResourceName()
local HELLO_COOLDOWN_MS = 2000
local lastHello = {}

CreateThread(function()
    Db.init()
    Places.load()
    Migrate.qbBanking()
    Bridge.ready = true
    Places.broadcast()
    for _, id in ipairs(GetPlayers()) do Money.payPending(tonumber(id)) end
    print(('[%s] ready: %d branch / ATM spot(s)'):format(RESOURCE, #Places.list()))
end)

RegisterNetEvent('vanguard-bank:hello', function()
    local src = source
    local now = GetGameTimer()
    if not Bridge.ready or (lastHello[src] and now - lastHello[src] < HELLO_COOLDOWN_MS) then return end
    lastHello[src] = now
    Places.broadcast(src)
end)

AddEventHandler('playerDropped', function() lastHello[source] = nil end)

-- Console check that scripts calling exports['qb-banking'] reach this resource (provide).
RegisterCommand('vbank_selftest', function(src)
    if src ~= 0 then return end
    local ok, result = pcall(function() return exports['qb-banking']:GetAccountBalance('police') end)
    print(('[%s] qb-banking exports %s (police balance: %s)'):format(RESOURCE, ok and 'OK' or 'NOT reachable', tostring(result)))
end, true)
