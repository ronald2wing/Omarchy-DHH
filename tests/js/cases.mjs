// The shared case runner: a table of { export name: [{ args, expected }] } run against a module.
import assert from "node:assert/strict"

// Run every case in `table` against `module`'s exports. Each listed export
// must exist and have cases. Results go through JSON, so they compare as the
// plain data the tables hold. `label` names the module in failures.
export function assertCases(module, table, label) {
  for (const [name, cases] of Object.entries(table)) {
    assert(typeof module[name] === "function", label + ": " + name + " is an exported function")
    assert(cases.length > 0, label + ": " + name + " has cases")
    for (const { args, expected } of cases) {
      const actual = JSON.parse(JSON.stringify(module[name](...args)))
      try {
        assert.deepEqual(actual, expected)
      } catch (e) {
        throw new Error("FAIL: " + label + ": " + name + "(" + JSON.stringify(args) + ")\n  expected " + JSON.stringify(expected) + "\n  actual   " + JSON.stringify(actual))
      }
    }
  }
}
