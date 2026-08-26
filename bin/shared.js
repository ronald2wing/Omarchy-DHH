"use strict"
// Shared helpers for the standalone Node scripts (bin/omarchy-dhh-render,
// bin/omarchy-add-entry) and the node tests. search.js and format.js are
// Qt-free with no module.exports, so they are loaded into a vm sandbox whose
// top-level functions become sandbox properties; the shared id rule needs the
// same SHA-256 hex digest in every caller. CommonJS only (require) — the
// callers are plain node scripts, not ES modules.
const fs = require("fs")
const vm = require("vm")
const crypto = require("crypto")

// Hex digest of the content, passed to Search.entryId (which stays crypto-free).
function sha256Hex(text) {
  return crypto.createHash("sha256").update(text).digest("hex")
}

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

module.exports = { sha256Hex, loadScript }
