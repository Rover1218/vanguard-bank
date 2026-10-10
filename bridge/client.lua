-- Vanguard Bank - client bridge (QBCore today): notifications and 3D text.

ClientBridge = {}

local QBCore = exports['qb-core']:GetCoreObject()

function ClientBridge.notify(message, kind)
    if message then QBCore.Functions.Notify(message, kind or 'primary', 5000) end
end

function ClientBridge.drawText3d(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 235)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() TriggerServerEvent('vanguard-bank:hello') end)
