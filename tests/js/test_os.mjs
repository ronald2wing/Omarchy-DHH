// js/os.mjs: file URLs as paths and UTF-8 byte lengths.
import assert from "node:assert/strict"
import * as Os from "../../js/os.mjs"

// utf8ByteLength counts bytes, not UTF-16 units; a missing value is 0 bytes.
assert(Os.utf8ByteLength("") === 0 && Os.utf8ByteLength("abc") === 3, "utf8ByteLength ASCII")
assert(Os.utf8ByteLength("é") === 2 && Os.utf8ByteLength("€") === 3 && Os.utf8ByteLength("💡") === 4, "utf8ByteLength multibyte")
assert(Os.utf8ByteLength("aé€💡") === 10, "utf8ByteLength mixed")
assert(Os.utf8ByteLength(null) === 0 && Os.utf8ByteLength(undefined) === 0, "utf8ByteLength null and undefined are empty")
// The cap comparison callers make: inclusive at the limit.
assert(!(Os.utf8ByteLength("é") > 2) && Os.utf8ByteLength("é") > 1, "utf8ByteLength cap comparison")
assert(!(Os.utf8ByteLength("💡") > 4) && Os.utf8ByteLength("💡") > 3, "utf8ByteLength cap comparison, emoji")

// fileUrlToPath
assert(Os.fileUrlToPath("file:///tmp/a%20b") === "/tmp/a b", "fileUrlToPath decodes")
assert(Os.fileUrlToPath("file:///tmp/a%b") === "/tmp/a%b", "fileUrlToPath keeps a malformed escape")
assert(Os.fileUrlToPath("/tmp/plain") === "/tmp/plain", "fileUrlToPath passthrough")
assert(Os.fileUrlToPath("file://relative/x") === "/relative/x", "fileUrlToPath roots a scheme-relative path")
assert(Os.fileUrlToPath(undefined) === "", "fileUrlToPath undefined")

console.log("test_os.mjs: all assertions passed")
