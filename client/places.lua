-- Vanguard Bank - map icons for branches and [E] prompts at placed branches / ATMs.

Places = { list = {}, blips = {} }

local PROMPT_KEY = 38
local NEAR = 15.0

local function clearBlips()
    for _, blip in ipairs(Places.blips) do RemoveBlip(blip) end
    Places.blips = {}
end

local function makeBlips()
    clearBlips()
    for _, place in ipairs(Places.list) do
        if place.kind == 'branch' then
            local blip = AddBlipForCoord(place.x, place.y, place.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, Config.Blip.colour)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(Config.Blip.label)
            EndTextCommandSetBlipName(blip)
            Places.blips[#Places.blips + 1] = blip
        end
    end
end

RegisterNetEvent('vanguard-bank:places', function(list)
    Places.list = type(list) == 'table' and list or {}
    makeBlips()
end)

local function placing()
    return Placement ~= nil and Placement.active -- Placement is defined in client/placement.lua (loaded after this file)
end

CreateThread(function()
    while true do
        local sleep = 750
        if not Client.isOpen and not placing() then
            local pos = GetEntityCoords(PlayerPedId())
            local best, bestDistance
            for _, place in ipairs(Places.list) do
                local distance = #(pos - vector3(place.x, place.y, place.z))
                if distance < NEAR then sleep = 0 end
                if distance <= Config.InteractDistance and (not bestDistance or distance < bestDistance) then
                    best, bestDistance = place, distance
                end
            end
            if best then
                local label = best.kind == 'atm' and '[E] ATM' or ('[E] %s'):format(best.label)
                ClientBridge.drawText3d(vector3(best.x, best.y, best.z + (best.kind == 'atm' and 1.2 or 0.5)), label)
                if IsControlJustReleased(0, PROMPT_KEY) then Client.open() end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then clearBlips() end
end)
