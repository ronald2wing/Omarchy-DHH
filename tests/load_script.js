"use strict"
// Shared helpers for the Node test suite only (tests/test_search.js,
// tests/test_format.js, tests/test_state.js). The runtime render/add-entry
// scripts are now Ruby (bin/dhh_helpers.rb) and no longer require this file.
// search.js, format.js, and state.js are Qt-free with no module.exports, so
// they are loaded into a vm sandbox whose top-level functions become sandbox
// properties. CommonJS only (require) — the callers are plain node scripts,
// not ES modules.
const fs = require("fs")
const vm = require("vm")

// Load a Qt-free script file into a fresh vm sandbox and return the sandbox
// object (the script's top-level functions become its properties). The sandbox
// gets the real global console; `contextName` only labels the context in stack
// traces (defaults to the file path).
function loadScript(filePath, contextName) {
  const ctx = { console }
  vm.createContext(ctx, { name: contextName || filePath })
  vm.runInContext(fs.readFileSync(filePath, "utf8"), ctx)
  return ctx
}

module.exports = { loadScript }
