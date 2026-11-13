# frozen_string_literal: true

require_relative '../lib/foxyn_installer/hardware'

def check(value, message)
  raise message unless value
end

def run_with(values)
  ->(*args) { values.fetch(args, ['', false]) }
end

base = {
  ['/usr/bin/uname', '-s'] => ["DragonFly\n", true],
  ['/sbin/sysctl', '-n', 'hw.machine'] => ["x86_64\n", true],
  ['/sbin/sysctl', '-n', 'hw.model'] => ["QEMU CPU\n", true],
  ['/sbin/sysctl', '-n', 'hw.physmem'] => ["4294967296\n", true],
  ['/sbin/sysctl', '-b', 'machdep.efi_map'] => ["\x00\x01".b, true],
  ['/usr/sbin/pciconf', '-l'] => ["none0@pci0:0:31:3: class=0x0c0500 chip=0x29308086 rev=0x00\n", true]
}
result = FoxynInstaller::Hardware.new(run: run_with(base)).check
check(result['observations']['physical_memory_bytes'] == 4_294_967_296, 'bad memory')
check(result['observations']['architecture'] == 'x86_64', 'bad architecture')
check(result['observations']['boot_evidence'] == 'efi_memory_map_present', 'EFI map evidence missing')
check(result['observations']['unattached_pci'].first['vendor_id'] == '8086', 'PCI vendor decoded incorrectly')
check(result['observations']['unattached_pci'].first['device_id'] == '2930', 'PCI device decoded incorrectly')
check(result['findings'].any? { |f| f['code'] == 'pci_driver_missing' }, 'missing PCI warning')
check(result['complete'] == false && result['verdict'] == 'not supported', 'must fail closed')
check(result['findings'].any? { |f| f['severity'] == 'blocking' }, 'missing blocker')

bad = base.merge(['/sbin/sysctl', '-n', 'hw.machine'] => ["arm64\n", true],
                 ['/sbin/sysctl', '-n', 'hw.physmem'] => ["garbage\n", true])
result = FoxynInstaller::Hardware.new(run: run_with(bad)).check
codes = result['findings'].map { |finding| finding['code'] }
check(codes.include?('unsupported_architecture'), 'unsupported architecture accepted')
check(codes.include?('memory_unavailable'), 'invalid memory accepted')
check(result['observations']['physical_memory_bytes'].nil?, 'invalid memory returned')

missing = base.merge(['/sbin/sysctl', '-n', 'hw.machine'] => ['', false])
result = FoxynInstaller::Hardware.new(run: run_with(missing)).check
check(result['findings'].any? { |f| f['code'] == 'architecture_unavailable' }, 'missing architecture accepted')

empty_map = base.merge(['/sbin/sysctl', '-b', 'machdep.efi_map'] => ['', true])
result = FoxynInstaller::Hardware.new(run: run_with(empty_map)).check
check(result['observations']['boot_evidence'] == 'unknown', 'missing EFI map must remain unknown')

broken_pci = base.merge(['/usr/sbin/pciconf', '-l'] => ["none0@pci0:0:31:3: malformed\n", true])
result = FoxynInstaller::Hardware.new(run: run_with(broken_pci)).check
check(result['findings'].any? { |f| f['code'] == 'pci_inventory_unparsed' }, 'unparsed device ignored')

no_pci = base.merge(['/usr/sbin/pciconf', '-l'] => ['', false])
result = FoxynInstaller::Hardware.new(run: run_with(no_pci)).check
check(result['observations']['unattached_pci'].nil?, 'failed PCI inventory mistaken for empty')
check(result['findings'].any? { |f| f['code'] == 'pci_inventory_unavailable' }, 'PCI failure ignored')

linux = base.merge(['/usr/bin/uname', '-s'] => ["Linux\n", true])
result = FoxynInstaller::Hardware.new(run: run_with(linux)).check
check(result['findings'].first['code'] == 'hardware_check_unavailable', 'wrong OS accepted')
puts 'Hardware observation tests passed'
