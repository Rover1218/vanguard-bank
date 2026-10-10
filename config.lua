Config = {}

Config.Brand = { Title = 'VANGUARD', Subtitle = 'BANK', Accent = '#6366f1' }

Config.AdminAce = 'vanguard.bank.admin'   -- server.cfg: add_ace group.admin vanguard.bank.admin allow
Config.AdminCommand = 'bankadmin'         -- placement tool for branches and ATMs

Config.InteractDistance = 2.0   -- [E] prompt at a placed branch / ATM
Config.ServerReach = 4.0        -- the server's check: player within this many metres of a placed spot
Config.MaxOwnedAccounts = 3     -- savings + shared accounts one character may own
Config.MaxAmount = 10000000     -- largest single deposit / withdraw / transfer
Config.BusinessMinRank = 3      -- Vanguard Business ranks that see the business account (3 Manager, 4 Owner)
Config.HistoryPage = 50
Config.QuickAmounts = { 100, 500, 1000, 5000 }

Config.Blip = { sprite = 108, colour = 2, scale = 0.7, label = 'Bank' }
Config.AtmModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' }

-- Added once, the first time the bank starts with no places (admins can move / delete them).
Config.DefaultBranches = {
    { label = 'Fleeca Legion Square', coords = { x = 149.05, y = -1041.3, z = 29.37 } },
    { label = 'Fleeca Hawick', coords = { x = 313.32, y = -280.03, z = 54.17 } },
    { label = 'Fleeca Burton', coords = { x = -351.94, y = -50.72, z = 49.04 } },
    { label = 'Fleeca Rockford Hills', coords = { x = -1212.68, y = -331.83, z = 37.78 } },
    { label = 'Fleeca Great Ocean', coords = { x = -2961.67, y = 482.31, z = 15.7 } },
    { label = 'Fleeca Harmony', coords = { x = 1175.64, y = 2707.71, z = 38.09 } },
    { label = 'Pacific Standard', coords = { x = 247.65, y = 223.87, z = 106.29 } },
    { label = 'Blaine County Savings', coords = { x = -111.98, y = 6470.56, z = 31.63 } },
}
