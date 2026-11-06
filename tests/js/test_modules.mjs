// Import-graph rules for js/: no Map/Set the worker reaches, imports stay in js/, no unused module.
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..")
const JS = path.join(ROOT, "js")
const WORKER = path.join(JS, "dataset-worker.mjs")

// Comments removed; a block comment keeps its newlines so lines stay aligned.
function stripComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, c => c.replace(/[^\n]/g, "")).replace(/\/\/.*$/gm, "")
}

// The specifiers of every static `import … from "x"`, bare `import "x"` and
// re-export `export … from "x"`.
function importSpecifiers(src) {
  const specs = []
  const re = /^\s*(?:import\s+(?:[^"';]*?\s+from\s+)?|export\s+(?:\*(?:\s+as\s+[\w$]+)?|\{[^}]*\})\s*from\s+)["']([^"']+)["']/gm
  let m
  while ((m = re.exec(src)) !== null) specs.push(m[1])
  return specs
}

// Walk the import graph from each root. `workerReached` holds what the worker
// loads, which is held to the Map/Set rule; `reached` holds every module the
// worker or QML loads, directly or transitively.
const workerReached = Object.create(null)
const reached = Object.create(null)
const queue = [{ file: WORKER, worker: true }]

// Modules QML imports, resolved against each .qml file's directory.
const qmlFiles = execFileSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.qml"], { cwd: ROOT, encoding: "utf8" })
  .split("\n").filter(Boolean)
for (const qml of qmlFiles) {
  const src = fs.readFileSync(path.join(ROOT, qml), "utf8")
  const re = /^\s*import\s+"([^"]+\.mjs)"/gm
  let m
  while ((m = re.exec(src)) !== null) {
    const target = path.resolve(ROOT, path.dirname(qml), m[1])
    assert(fs.existsSync(target), qml + ": import " + m[1] + " exists")
    assert(path.dirname(target) === JS, qml + ": import " + m[1] + " resolves inside js/")
    queue.push({ file: target, worker: false })
  }
}

while (queue.length > 0) {
  const { file, worker } = queue.shift()
  if (worker ? workerReached[file] : reached[file]) continue
  reached[file] = true
  if (worker) workerReached[file] = true
  const rel = path.relative(ROOT, file)
  const src = stripComments(fs.readFileSync(file, "utf8"))
  // V4 implements Map/Set lookups as linear scans: a Map term dictionary made
  // the index build take ~8 s in the shell, 60 ms in node.
  if (worker) assert(!/\bnew\s+(Map|Set|WeakMap|WeakSet)\b/.test(src), rel + ": no Map/Set in code the worker reaches (linear in Qt V4)")
  for (const spec of importSpecifiers(src)) {
    assert(spec.startsWith("./") || spec.startsWith("../"), rel + ": import " + spec + " is relative")
    const target = path.resolve(path.dirname(file), spec)
    assert(path.dirname(target) === JS, rel + ": import " + spec + " resolves inside js/")
    assert(fs.existsSync(target), rel + ": import " + spec + " exists")
    queue.push({ file: target, worker: worker })
  }
}

const modules = fs.readdirSync(JS).filter(name => name.endsWith(".mjs"))
assert(modules.length > 0, "js/ holds modules")
for (const name of modules) {
  const file = path.join(JS, name)
  assert(reached[file], "js/" + name + " is loaded by the worker or by QML, directly or through another module")
}
assert.deepEqual(fs.readdirSync(JS).filter(name => name.endsWith(".js")), [], "no plain-script js/*.js files")

// Qt logs qt.qml.usedbeforedeclared on every load when code reads a
// module-scope const/let above its declaration, even inside a function that
// only runs later (node and the headless qml runner stay silent). So every
// top-level const/let is declared above its first textual use.
for (const name of modules) {
  const lines = stripComments(fs.readFileSync(path.join(JS, name), "utf8")).split("\n")
  lines.forEach((line, d) => {
    const decl = /^(?:export\s+)?(?:const|let)\s+([A-Za-z_$][\w$]*)/.exec(line)
    if (!decl) return
    const use = new RegExp("(?:^|[^\\w$.])" + decl[1].replace(/\$/g, "\\$") + "(?![\\w$])")
    const early = lines.findIndex((l, i) => i < d && use.test(l))
    assert(early === -1, "js/" + name + ":" + (early + 1) + " reads " + decl[1] + ", declared below at line " + (d + 1))
  })
}

console.log("test_modules.mjs: all assertions passed")
