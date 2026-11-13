# frozen_string_literal: true

require_relative '../lib/foxyn_installer/service'

class DiskFixture
  def list
    { 'disks' => [{ 'device' => '/dev/vbd1' }], 'target_safety_checked' => false }
  end
end

class HardwareFixture
  def check
    { 'complete' => false, 'verdict' => 'not supported',
      'findings' => [{ 'severity' => 'blocking', 'message' => 'Not checked.' }] }
  end
end

service = FoxynInstaller::Service.new(disks: DiskFixture.new, hardware: HardwareFixture.new)
def request(service, operation)
  service.call('version' => 1, 'id' => operation, 'operation' => operation)
end
hardware = request(service, 'check-hardware').fetch('result')
disks = request(service, 'list-disks').fetch('result')
install = request(service, 'install').fetch('result')
raise 'hardware check unexpectedly complete' unless hardware['complete'] == false
raise 'disk inventory not routed' unless disks['disks'][0]['device'] == '/dev/vbd1'
raise 'target unexpectedly safe' unless disks['target_safety_checked'] == false
raise 'installation unexpectedly accepted' unless install['accepted'] == false
puts 'Integrated service test passed'
