// Runs Lua 5.3 code on Node (fengari) for tests and build tools. Dev-only, not shipped.
'use strict';

const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const ROOT = path.resolve(__dirname, '..').replace(/\\/g, '/');

function createState() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    run(L, `ROOT = ${JSON.stringify(ROOT)}; package.path = ROOT .. '/?.lua;' .. package.path`, 'setup');
    return L;
}

/** Runs a chunk and returns its first result converted to a JS string (or null). Throws on Lua errors. */
function run(L, code, name) {
    const source = to_luastring(code);
    const top = lua.lua_gettop(L);
    if (lauxlib.luaL_loadbuffer(L, source, source.length, to_luastring(`@${name}`)) !== lua.LUA_OK
        || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
        const message = lua.lua_tojsstring(L, -1);
        lua.lua_settop(L, top);
        throw new Error(message);
    }
    const result = lua.lua_isstring(L, -1) ? lua.lua_tojsstring(L, -1) : null;
    lua.lua_settop(L, top);
    return result;
}

module.exports = { ROOT, createState, run };
