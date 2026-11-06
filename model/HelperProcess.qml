pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../js/os.mjs" as Os

// Runs one helper from helpers/ with a deadline, kill grace and stdout cap; no signal after cancel().
Item {
  id: root

  // The helper's file name under helpers/, e.g. "fetch-avatars".
  required property string helper
  // Defence in depth on the helper's own caps: output above this many UTF-8
  // bytes is a failure, so a misbehaving helper cannot make the caller parse
  // an unbounded string. 0 means unbounded.
  property int maxStdoutBytes: 0
  // True from run() until its outcome is reported, including the moment
  // before the process has started; false straight after cancel().
  readonly property bool running: internal.queued !== null || (internal.live && !internal.canceled)

  // Both streams are collected whole, and exactly one of succeeded / failed
  // fires once the process has exited and both streams have ended (or once
  // its launch has failed), unless cancel() came first: after cancel()
  // nothing fires for that run.
  // Exit 0, within the deadline and within maxStdoutBytes.
  signal succeeded(string stdout)
  // "timed out" once the deadline fired (stderr after a SIGTERM diagnoses
  // nothing); otherwise stderr's last non-empty line for a non-zero exit, else
  // "exited with <N>"; "output exceeded <N> bytes" for a clean exit over the
  // cap; "failed to start" when the helper could not be launched at all.
  signal failed(string reason)

  // One helper runs at a time: run() while one is still in flight (or still
  // exiting after cancel()) cancels it and starts the new one once it has
  // exited.
  function run(args) {
    const command = [internal.helperPath].concat(args || [])
    if (internal.live) {
      root.cancel()
      internal.queued = command
      return
    }
    internal.start(command)
  }

  // Stop the timers and SIGKILL the helper (as soon as it has started, if it
  // has not yet). Its exit is swallowed, so a caller never sees a result for
  // a run it canceled.
  function cancel() {
    internal.canceled = true
    internal.queued = null
    termTimer.stop()
    killTimer.stop()
    if (process.running) process.signal(internal.sigkill)
  }

  // An owner going away takes its helper with it.
  Component.onDestruction: root.cancel()

  QtObject {
    id: internal
    readonly property string helperPath: Os.fileUrlToPath(Qt.resolvedUrl("../helpers/" + root.helper))
    // The QML-side backstop behind the helpers' own bounds (fetch-avatars'
    // 8 s batch deadline, fetch-post-count's 5 s hop timeout): SIGTERM at
    // `deadline`, SIGKILL `killGrace` later.
    readonly property int deadline: 15000
    readonly property int killGrace: 2000
    readonly property int sigterm: 15
    readonly property int sigkill: 9
    // A process was launched and its exit (or failed launch) has not been
    // handled yet. Process.running cannot stand in for it: exec() on a
    // Process whose last child is still exiting only queues the new child,
    // and the old child's exit is then reported as the new run's.
    property bool live: false
    // The launched process has started. A launch that fails (a missing or
    // non-executable helper) reports neither started nor exited, only
    // running turning false, so this tells that failure from a normal exit.
    property bool started: false
    property bool canceled: false
    // Set once the deadline fires; reported when the process exits.
    property bool timedOut: false
    // The command run() was given while a canceled process was still
    // exiting; launched by that exit.
    property var queued: null

    function start(command) {
      internal.queued = null
      internal.canceled = false
      internal.timedOut = false
      internal.started = false
      internal.live = true
      termTimer.restart()
      process.exec(command)
    }

    // The launched process is gone: stop the timers, then launch the command
    // queued behind a canceled run, or report unless canceled.
    function ended(report) {
      termTimer.stop()
      killTimer.stop()
      internal.live = false
      if (internal.canceled) {
        if (internal.queued !== null) internal.start(internal.queued)
        return
      }
      report()
    }

    function lastLine(text) {
      const lines = String(text || "").split("\n").map(line => line.trim()).filter(line => line !== "")
      return lines.length > 0 ? lines[lines.length - 1] : ""
    }

    function exited(exitCode, stdout, stderr) {
      if (internal.timedOut) { root.failed("timed out"); return }
      if (exitCode !== 0) { root.failed(internal.lastLine(stderr) || "exited with " + exitCode); return }
      if (root.maxStdoutBytes > 0 && Os.utf8ByteLength(stdout) > root.maxStdoutBytes) {
        root.failed("output exceeded " + root.maxStdoutBytes + " bytes")
        return
      }
      root.succeeded(stdout)
    }
  }

  Process {
    id: process
    stdout: StdioCollector { id: stdoutCollector; waitForEnd: true }
    stderr: StdioCollector { id: stderrCollector; waitForEnd: true }
    onStarted: {
      internal.started = true
      if (internal.canceled) process.signal(internal.sigkill)
    }
    onExited: (exitCode) => {
      internal.ended(() => internal.exited(exitCode, stdoutCollector.text, stderrCollector.text))
    }
    // Without this, a failed launch would leave the helper `running` forever
    // and every later run() queued behind it. A launch made from inside
    // onExited reads running as true here, so it is never mistaken for one.
    onRunningChanged: {
      if (process.running || !internal.live || internal.started) return
      internal.ended(() => root.failed("failed to start"))
    }
  }

  // Process exposes only signal(int), so killing a helper's process group is
  // the helper's own job.
  Timer {
    id: termTimer
    interval: internal.deadline
    onTriggered: {
      internal.timedOut = true
      if (process.running) process.signal(internal.sigterm)
      killTimer.restart()
    }
  }

  Timer {
    id: killTimer
    interval: internal.killGrace
    onTriggered: { if (process.running) process.signal(internal.sigkill) }
  }
}
