# frozen_string_literal: true

require 'rbconfig'
require_relative '../lib/foxyn_installer/command'

def assert(value, message)
  raise message unless value
end

runner = FoxynInstaller::Command.new(timeout: 1.5, max_output: 4096)
ruby = RbConfig.ruby
output, ok = runner.call(ruby, '-e', 'STDOUT.write("ok")')
assert(ok && output == 'ok', 'successful command failed')
_, ok = runner.call(ruby, '-e', 'exit 3')
assert(!ok, 'failed exit accepted')
_, ok = runner.call('/nonexistent/foxyn-command')
assert(!ok, 'missing command accepted')
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
_, ok = runner.call(ruby, '-e', 'sleep 30')
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
assert(!ok && elapsed < 5, "timeout failed (#{elapsed}s)")
_, ok = runner.call(ruby, '-e', 'STDOUT.write("x" * 10000)')
assert(!ok, 'oversized output accepted')
puts 'Command execution tests passed'
