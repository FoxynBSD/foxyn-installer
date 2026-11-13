# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../lib/foxyn_installer/boot_configuration'

def assert(value, message)
  raise message unless value
end

def rejected
  yield
  raise 'invalid configuration accepted'
rescue ArgumentError
end

root = 'A1111111-2222-3333-4444-555555555555'
esp = 'b1111111-2222-3333-4444-555555555555'
Dir.mktmpdir('foxyn-boot-config') do |target|
  FileUtils.mkdir_p(File.join(target, 'etc'))
  FileUtils.mkdir_p(File.join(target, 'boot/efi/boot'))
  rc = File.join(target, 'etc/rc.conf')
  File.write(rc, "# example\nroot_rw_mount=YES\nsshd_enable=YES\n")
  File.chmod(0o600, rc)
  config = FoxynInstaller::BootConfiguration.new
  result = config.write(target: target, root_uuid: root, esp_uuid: esp, filesystem: 'ufs', console: 'comconsole')
  fstab = File.read(File.join(target, 'etc/fstab'))
  loader = File.read(File.join(target, 'boot/loader.conf'))
  assert(result['root_device'] == "slice-by-uuid/#{root.downcase}", 'root UUID not normalized')
  assert(fstab.include?("/dev/slice-by-uuid/#{root.downcase}\t/\tufs\trw\t1\t1"), 'UFS root missing')
  assert(fstab.include?("/dev/slice-by-uuid/#{esp}\t/boot/efi\tmsdos"), 'ESP missing')
  assert(loader.include?('boot_serial="YES"') && loader.include?("ufs:slice-by-uuid/#{root.downcase}"), 'loader configuration wrong')
  assert(loader == File.read(File.join(target, 'boot/efi/boot/loader.conf')), 'loader copies differ')
  assert(File.read(rc) == "# example\nsshd_enable=YES\n", 'live root setting not removed safely')
  assert((File.stat(rc).mode & 0o777) == 0o600, 'configuration mode widened')
  result = config.write(target: target, root_uuid: root, esp_uuid: esp, filesystem: 'hammer2', console: 'efi')
  assert(File.read(File.join(target, 'etc/fstab')).include?("hammer2\trw\t0\t0"), 'HAMMER2 fsck fields wrong')
  assert(!File.read(File.join(target, 'boot/loader.conf')).include?('boot_serial='), 'serial flag leaked')
  rejected { config.write(target: target, root_uuid: "#{root}\nBAD", esp_uuid: esp, filesystem: 'ufs', console: 'efi') }
  rejected { config.write(target: target, root_uuid: root, esp_uuid: root.downcase, filesystem: 'ufs', console: 'efi') }
  rejected { config.write(target: target, root_uuid: root, esp_uuid: esp, filesystem: 'ext4', console: 'efi') }
  rejected { config.write(target: target, root_uuid: root, esp_uuid: esp, filesystem: 'ufs', console: 'efi\nBAD') }
  rejected { config.write(target: '/', root_uuid: root, esp_uuid: esp, filesystem: 'ufs', console: 'efi') }
  loader_path = File.join(target, 'boot/loader.conf')
  File.unlink(loader_path)
  File.symlink('/tmp/foxyn-should-not-exist', loader_path)
  rejected { config.write(target: target, root_uuid: root, esp_uuid: esp, filesystem: 'ufs', console: 'efi') }
  assert(File.symlink?(loader_path), 'unsafe symlink changed')
end
puts 'Boot configuration tests passed'
