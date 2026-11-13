# frozen_string_literal: true

require_relative '../lib/foxyn_installer/disks'

def check(value, message)
  raise message unless value
end

calls = []
run = lambda do |*argv|
  calls << argv
  case argv
  when ['/usr/bin/uname', '-s'] then ["DragonFly\n", true]
  when ['/sbin/sysctl', '-n', 'kern.disks'] then ["vbd0 vbd1 md0 vn0\n", true]
  when ['/sbin/diskinfo', '/dev/vbd0'] then ["/dev/vbd0 blksize=512 offset=0x0000 size=0x20000000 512 MB\n", true]
  when ['/sbin/diskinfo', '/dev/vbd1'] then ["/dev/vbd1 Permission denied\n", true]
  else raise "unexpected command #{argv.inspect}"
  end
end
serials = ->(device) { device == '/dev/vbd0' ? ['test-serial'] : [] }
result = FoxynInstaller::Disks.new(run: run, serials: serials).list
check(result['target_safety_checked'] == false, 'must not assert target safety')
check(result['disks'].length == 4, 'missing devices')
check(result['disks'][0]['size_bytes'] == 536_870_912, 'incorrect size')
check(result['disks'][0]['serial'] == 'test-serial', 'incorrect serial')
check(result['disks'][1]['size_bytes'].nil?, 'diskinfo error must not become a size')
check(calls.none? { |c| c.last == '/dev/md0' || c.last == '/dev/vn0' }, 'virtual devices must not be probed')
check(result['disks'].all? { |d| d['information_complete'] == false }, 'inventory must be marked incomplete')

ambiguous = FoxynInstaller::Disks.new(run: run, serials: ->(_device) { %w[a b] }).list
check(ambiguous['disks'][0]['serial'].nil?, 'ambiguous serial must be omitted')
check(ambiguous['disks'][0]['warnings'].any? { |w| w.include?('ambiguous') }, 'missing ambiguity warning')

bad_name = ->(*argv) { argv.first == '/usr/bin/uname' ? ["DragonFly\n", true] : ["vbd0;reboot\n", true] }
begin
  FoxynInstaller::Disks.new(run: bad_name).list
  raise 'invalid device name accepted'
rescue RuntimeError => e
  raise unless e.message.include?('Invalid device name')
end

unsupported = ->(*_argv) { ["Linux\n", true] }
begin
  FoxynInstaller::Disks.new(run: unsupported).list
  raise 'unsupported OS accepted'
rescue RuntimeError => e
  raise unless e.message.include?('requires DragonFly')
end
puts 'Disk discovery tests passed'
