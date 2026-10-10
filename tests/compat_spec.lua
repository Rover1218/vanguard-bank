local T = require('tests.lib.t')

-- FiveM stand-ins: what compat.lua registers.
local exported, events = {}, {}
exports = function(name, fn) exported[name] = fn end
AddEventHandler = function(name, fn) events[name] = fn end
GetInvokingResource = function() return 'qb-policejob' end
Config = Config or {}
Config.MaxAmount = 10000000
dofile(ROOT .. '/shared/rules.lua')

local police = { id = 1, number = 'VB-0000-0001', type = 'job', balance = 0 }
Accounts = {
    byRef = function(kind, ref) if kind == 'job' and ref == 'police' then return police end end,
    adjust = function(_, delta) police.balance = police.balance + delta; return true end,
}
Ledger = { add = function() end }
Bridge = { isJob = function() return false end, isGang = function() return false end }
dofile(ROOT .. '/server/compat.lua')

local NAMES = { 'AddMoney', 'RemoveMoney', 'GetAccount', 'GetAccountBalance', 'GetBalance', 'CreateJobAccount',
    'CreateGangAccount', 'CreatePlayerAccount', 'CreateBankStatement', 'AddGangMoney', 'RemoveGangMoney', 'GetGangAccount' }

T.describe('qb-banking compatibility', function()
    T.it('answers exports["qb-banking"] calls itself (this FXServer ignores provide for exports)', function()
        for _, name in ipairs(NAMES) do
            T.eq(type(events['__cfx_export_qb-banking_' .. name]), 'function', name)
        end
    end)
    T.it('routes a police fine into the police account', function()
        local fn
        events['__cfx_export_qb-banking_AddMoney'](function(callback) fn = callback end)
        T.eq(fn('police', 500, 'Fine'), true)
        T.eq(police.balance, 500)
        T.eq(exported.AddMoney == fn, true, 'same function as the vanguard-bank export')
    end)
end)
