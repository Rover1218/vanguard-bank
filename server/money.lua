-- Vanguard Bank - moving money in and out of accounts.

Money = { REASON = 'vanguard-bank' }

local BUSINESS = 'vanguard-business'

--- Business accounts: Vanguard Business keeps its own money log too.
local function tellBusiness(account, kind, amount, actor, note)
    if account.type ~= 'business' or GetResourceState(BUSINESS) ~= 'started' then return end
    pcall(function() exports[BUSINESS]:noteBankMovement(tonumber(account.ref), kind, amount, actor, note) end)
end

--- Puts money into an account. Personal: online -> QBCore bank; offline -> paid on next login.
function Money.credit(account, amount, actor, note, kind)
    if account.type == 'personal' then
        local target = Bridge.sourceOf(account.owner)
        if target then
            if not Bridge.addMoney(target, 'bank', amount, Money.REASON) then return false end
        else
            local id = MySQL.insert.await('INSERT INTO vbank_pending (citizenid, amount, note) VALUES (?, ?, ?)',
                { account.owner, amount, note })
            if not id then return false end
        end
    elseif not Accounts.adjust(account.id, amount) then
        return false
    end
    Ledger.add(account.number, kind, amount, actor, note)
    tellBusiness(account, kind, amount, actor, note)
    return true
end

--- Takes money from an account the caller (src) may use. Never below zero.
function Money.debit(src, account, amount, actor, note, kind)
    if account.type == 'personal' then
        if not Bridge.removeMoney(src, 'bank', amount, Money.REASON) then return false end
    elseif not Accounts.adjust(account.id, -amount) then
        return false
    end
    Ledger.add(account.number, kind, -amount, actor, note)
    tellBusiness(account, kind, -amount, actor, note)
    return true
end

local function amountFrom(data)
    return Rules.wholeAmount(data.amount, Config.MaxAmount)
end

local function badAmount()
    return Router.fail(('Enter an amount from $1 to %s'):format(Rules.money(Config.MaxAmount)))
end

Router.on('deposit', function(src, data)
    local place, where = Places.require(src, 'deposit')
    if not place then return Router.fail(where) end
    local amount = amountFrom(data)
    if not amount then return badAmount() end
    local account, problem = Access.check(src, data.number, 'deposit')
    if not account then return Router.fail(problem) end
    if not Bridge.removeMoney(src, 'cash', amount, Money.REASON) then return Router.fail('You don\'t have that much cash') end
    if not Money.credit(account, amount, Bridge.name(src), place.label, 'deposit') then
        Bridge.addMoney(src, 'cash', amount, Money.REASON)
        return Router.fail('The deposit failed - your cash was returned')
    end
    return Router.ok(('Deposited %s'):format(Rules.money(amount)))
end)

Router.on('withdraw', function(src, data)
    local place, where = Places.require(src, 'withdraw')
    if not place then return Router.fail(where) end
    local amount = amountFrom(data)
    if not amount then return badAmount() end
    local account, problem = Access.check(src, data.number, 'withdraw')
    if not account then return Router.fail(problem) end
    local actor = Bridge.name(src)
    if not Money.debit(src, account, amount, actor, place.label, 'withdraw') then return Router.fail('Not enough money in that account') end
    if not Bridge.addMoney(src, 'cash', amount, Money.REASON) then
        Money.credit(account, amount, actor, 'Withdrawal failed - returned', 'refund')
        return Router.fail('The withdrawal failed - the money stays in the account')
    end
    return Router.ok(('Withdrew %s'):format(Rules.money(amount)))
end)

--- Transfers sent while this character was offline. Each row is deleted before paying, so it pays once.
function Money.payPending(src)
    local citizenid = Bridge.citizenid(src)
    if not citizenid then return end
    for _, row in ipairs(MySQL.query.await('SELECT id, amount, note FROM vbank_pending WHERE citizenid = ?', { citizenid }) or {}) do
        if MySQL.update.await('DELETE FROM vbank_pending WHERE id = ?', { row.id }) == 1 then
            local amount = tonumber(row.amount) or 0
            if Bridge.addMoney(src, 'bank', amount, Money.REASON) then
                Bridge.notify(src, ('Vanguard Bank: %s arrived while you were away'):format(Rules.money(amount)), 'success')
            else
                MySQL.insert.await('INSERT INTO vbank_pending (citizenid, amount, note) VALUES (?, ?, ?)', { citizenid, amount, row.note })
            end
        end
    end
end

Bridge.onPlayerLoaded(Money.payPending)

-- Personal history also shows bank money that other scripts move (paychecks, jobs, shops).
AddEventHandler('QBCore:Server:OnMoneyChange', function(src, moneyType, amount, operation, reason)
    if moneyType ~= 'bank' or (operation ~= 'add' and operation ~= 'remove') then return end
    if type(reason) == 'string' and reason:sub(1, #Money.REASON) == Money.REASON then return end
    local citizenid = Bridge.citizenid(src)
    if not citizenid or type(amount) ~= 'number' then return end
    local signed = operation == 'add' and amount or -amount
    Ledger.add(Accounts.personalNumber(citizenid), operation == 'add' and 'income' or 'payment', signed, nil, reason)
end)
