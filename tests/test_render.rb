# Contract tests for bin/omarchy-dhh-render's hardening: run_captured_group kills
# and reaps a process group on deadline. Stdlib only; no network access. The
# render script's `__FILE__` guard keeps `main` (and the TERM trap) from running
# when the file is `load`ed here.

load File.expand_path('../bin/omarchy-dhh-render', __dir__)

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

# run_captured_group: deadline exceeded -> whole group killed and reaped. The shell
# reports its own pid (its process-group id, since pgroup: true makes it the
# leader) on stdout, then execs a long sleep; the group must be gone afterward.
t0 = Time.now
stdout, _stderr, status, killed = run_captured_group(
  ['/bin/sh', '-c', 'echo $$; exec sleep 60'], deadline: 0.3, grace: 0.3
)
pid = stdout.strip.to_i
assert(pid > 0, 'captured the child pid from stdout')
assert(killed, 'run_captured_group reports killed on deadline')
assert(status.signaled?, 'run_captured_group status is signaled')
assert(Time.now - t0 < 3, 'run_captured_group returns under 3 seconds')
begin
  Process.kill(0, -pid)
  raise 'FAIL: process group still alive after kill'
rescue Errno::ESRCH
  # expected: the group is gone
end

# Real-magick trim regression: a synthetic 1200x2400 white PNG whose only
# non-white content is a black bar in the top 240px must trim down to that
# content, not stay at the full 2400px canvas (guards the inverted
# trim_to_content fallback). The bar is inset from the side edges — a bar
# spanning the full width degenerates magick's `%@` trim box. Skipped cleanly
# when magick is unavailable.
if File.executable?(MAGICK)
  Dir.mktmpdir('dhh-trim-test-') do |dir|
    raw = File.join(dir, 'raw.png')
    out = File.join(dir, 'out.png')
    built = system(MAGICK, '-size', '1200x2400', 'xc:white',
                   '-fill', 'black', '-draw', 'rectangle 16,0 583,239', raw,
                   out: File::NULL, err: File::NULL)
    assert(built, 'magick built the synthetic 1200x2400 test PNG')

    trim_to_content(raw, out)
    h = `#{MAGICK} identify -format %h #{out}`.strip.to_i
    assert(h == 240,
           "trim_to_content trimmed to the 240px content region, got #{h}px (full 2400 means the trim regression is back)")
  end
else
  puts 'test_render.rb: skipping trim_to_content regression test (magick unavailable)'
end

# TERM trap path: handle_term must run in trap context without raising
# ThreadError, kill the whole child process group, and exit 1. Each scenario
# forks a subprocess that installs the production handler (install_term_handler)
# and TERMs itself; the parent asserts exit status and that stderr carries no
# ThreadError, and (with a child) that the group is gone — kill(0, -pgid) raises
# ESRCH only when the group has no members left, so this also rules out an
# un-reaped zombie.
def assert_group_gone(pgid)
  deadline = Time.now + 2
  loop do
    begin
      Process.kill(0, -pgid)
    rescue Errno::ESRCH
      return
    end
    raise 'FAIL: process group still alive after TERM trap' if Time.now > deadline
    sleep 0.05
  end
end

# The two outcomes every trap scenario must share: exit 1 and no ThreadError
# (i.e. no illegal Mutex/join in the handler) on stderr.
def assert_trap_exited_cleanly(status, err, label)
  assert(status.exitstatus == 1, "#{label}: TERM trap exits 1, got #{status.exitstatus.inspect}")
  assert(!err.include?('ThreadError'), "#{label}: TERM trap raises no ThreadError")
end

# Forks a subprocess that (optionally) spawns a sleep in its own process group,
# publishes it via $active_child_pgid, installs the production TERM handler, and
# TERMs itself. handle_term runs and calls exit 1 inside the fork; the `sleep 10`
# is reached only if the handler neither exits nor raises. Returns
# [status, stderr, pgid_or_nil].
def run_term_trap_in_fork(spawn_child:)
  err_rd, err_wr = IO.pipe
  pgid_rd, pgid_wr = IO.pipe
  child = fork do
    err_rd.close
    pgid_rd.close
    $stderr.reopen(err_wr)
    err_wr.close
    if spawn_child
      pgid = Process.spawn('sleep', '60', pgroup: true, out: File::NULL, err: File::NULL)
      pgid_wr.write("#{pgid}\n")
      $active_child_pgid = pgid
    else
      $active_child_pgid = nil
    end
    pgid_wr.close
    install_term_handler
    Process.kill('TERM', Process.pid)
    sleep 10 # reached only if the handler is broken
    exit 2
  end
  err_wr.close
  pgid_wr.close
  pgid = spawn_child ? pgid_rd.read.to_i : nil
  pgid_rd.close
  err = err_rd.read
  err_rd.close
  _, status = Process.wait2(child)
  [status, err, pgid]
end

status, err, pgid = run_term_trap_in_fork(spawn_child: true)
assert_trap_exited_cleanly(status, err, 'with child')
assert(pgid > 0, 'captured the sleep pgid from the trap subprocess')
assert_group_gone(pgid)

status, err, = run_term_trap_in_fork(spawn_child: false)
assert_trap_exited_cleanly(status, err, 'no child')

puts 'test_render.rb: all assertions passed'
