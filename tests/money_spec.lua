local T = require('tests.lib.t')
dofile(ROOT .. '/shared/rules.lua')

-- FiveM / database stand-ins: the database is down.
Config = Config or {}
Config.MaxAmount = 10000000
Router = { on = function() end }
Bridge = { onPlayerLoaded = function() end, sourceOf = function() return nil end }
AddEventHandler = function() end
GetResourceState = function() return 'missing' end
Ledger = { add = function() end }
Accounts = {}
MySQL = { insert = { await = function() error('database is down') end } }
dofile(ROOT .. '/server/money.lua')

T.describe('Money.credit', function()
    T.it('reports failure instead of throwing when a credit for an offline player cannot be saved', function()
        local offline = { type = 'personal', owner = 'ABC123', number = 'VB-0000-0002' }
        local ok, credited = pcall(Money.credit, offline, 100, 'Rover Dev', 'From VB-0000-0001', 'transfer_in')
        T.eq(ok, true, 'no error escapes (the caller refunds the sender)')
        T.eq(credited, false)
    end)
end)
