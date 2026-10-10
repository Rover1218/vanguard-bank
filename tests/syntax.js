// Syntax-checks every shipped Lua file (luaparse) and the NUI script (node --check). Usage: npm run lint
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const luaparse = require('luaparse');

const ROOT = path.resolve(__dirname, '..');
const SKIP = new Set(['node_modules', '.git', 'docs']);

function luaFiles(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        if (SKIP.has(entry.name)) return [];
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return luaFiles(full);
        return entry.name.endsWith('.lua') ? [full] : [];
    });
}

let failed = 0;
for (const file of luaFiles(ROOT)) {
    // install/ox_inventory_items.lua is pasted into ox_inventory and uses CfxLua backtick hashes.
    const source = fs.readFileSync(file, 'utf8').replace(/`([^`\n]*)`/g, '"$1"');
    try {
        luaparse.parse(source, { luaVersion: '5.3' });
    } catch (error) {
        failed += 1;
        console.error(`FAIL ${path.relative(ROOT, file)}: ${error.message}`);
    }
}

try {
    execFileSync(process.execPath, ['--check', path.join(ROOT, 'html', 'app.js')], { stdio: 'inherit' });
} catch {
    failed += 1;
}

console.log(failed ? `${failed} file(s) failed` : 'syntax ok');
process.exit(failed ? 1 : 0);
