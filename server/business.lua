-- Vanguard Bank - exports for Vanguard Business. Its money lives in a Business account here;
-- Vanguard Business logs its own side, so these do not call back into it.

local function businessAccount(id, name)
    if type(id) ~= 'number' then return nil end
    return Accounts.ensureRef('business', id, type(name) == 'string' and name or nil)
end

exports('getBusinessBalance', function(id)
    local account = type(id) == 'number' and Accounts.byRef('business', id) or nil
    return account and account.balance or 0
end)

exports('adjustBusiness', function(id, delta, kind, actor, note, name)
    if type(delta) ~= 'number' or delta == 0 or delta % 1 ~= 0 then return false end
    local account = businessAccount(id, name)
    if not account or not Accounts.adjust(account.id, delta) then return false end
    Ledger.add(account.number, kind or (delta > 0 and 'income' or 'payment'), delta, actor or 'Vanguard Business', note)
    return true
end)

exports('businessAccountNumber', function(id, name)
    local account = businessAccount(id, name)
    return account and account.number or nil
end)
