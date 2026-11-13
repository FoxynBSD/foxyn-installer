# frozen_string_literal: true

require 'open3'

module FoxynInstaller
  # Observations are deliberately separate from compatibility decisions.
  class Hardware
    def initialize(run: nil)
      @run = run || method(:run_command)
    end

    def check
      os = read('/usr/bin/uname', '-s')
      return unavailable('Running system is not DragonFly BSD.') unless os == 'DragonFly'

      arch = read('/sbin/sysctl', '-n', 'hw.machine')
      model = read('/sbin/sysctl', '-n', 'hw.model')
      memory_text = read('/sbin/sysctl', '-n', 'hw.physmem')
      efi_map, efi_ok = @run.call('/sbin/sysctl', '-b', 'machdep.efi_map')
      boot_evidence = efi_ok && !efi_map.empty? ? 'efi_memory_map_present' : 'unknown'
      memory = memory_text&.match?(/\A[1-9]\d*\z/) ? memory_text.to_i : nil
      pci_output, pci_ok = @run.call('/usr/sbin/pciconf', '-l')
      pci_unattached, pci_malformed = unattached_pci(pci_ok ? pci_output : nil)
      interfaces, network_errors = network_interfaces
      findings = [{ 'severity' => 'blocking', 'code' => 'hardware_check_incomplete',
                    'message' => 'Hardware compatibility has not been fully checked; installation is disabled.' }]
      if arch.nil? || arch.empty?
        findings << { 'severity' => 'blocking', 'code' => 'architecture_unavailable',
                      'message' => 'CPU architecture could not be read.' }
      elsif arch != 'x86_64'
        findings << { 'severity' => 'blocking', 'code' => 'unsupported_architecture',
                      'message' => "Architecture #{arch} is not supported by this installer." }
      end
      network_errors.each do |message|
        findings << { 'severity' => 'blocking', 'code' => 'network_inventory_unavailable',
                      'message' => message }
      end
      unless pci_ok
        findings << { 'severity' => 'blocking', 'code' => 'pci_inventory_unavailable',
                      'message' => 'PCI device inventory could not be read.' }
      end
      if pci_malformed
        findings << { 'severity' => 'blocking', 'code' => 'pci_inventory_unparsed',
                      'message' => 'An unattached PCI device could not be identified.' }
      end
      pci_unattached.each do |device|
        findings << { 'severity' => 'warning', 'code' => 'pci_driver_missing',
                      'message' => "No driver is attached to #{device['location']} " \
                                   "(#{device['vendor_id']}:#{device['device_id']})." }
      end
      if memory.nil?
        findings << { 'severity' => 'blocking', 'code' => 'memory_unavailable',
                      'message' => 'Physical memory could not be read.' }
      end
      { 'verdict' => 'not supported', 'complete' => false,
        'observations' => { 'architecture' => arch, 'cpu_model' => model,
                            'physical_memory_bytes' => memory, 'boot_evidence' => boot_evidence,
                            'unattached_pci' => pci_ok ? pci_unattached : nil, 'network_interfaces' => interfaces },
        'findings' => findings }
    end

    private

    def network_interfaces
      names, ok = @run.call('/sbin/ifconfig', '-l')
      return [nil, ['Network interface inventory could not be read.']] unless ok

      errors = []
      interfaces = names.split.filter_map do |name|
        unless name.match?(/\A[a-zA-Z][a-zA-Z0-9_.-]*\z/)
          errors << 'An invalid network interface name was reported.'
          next
        end
        output, success = @run.call('/sbin/ifconfig', name)
        header = success && output.lines.first&.match(/\A#{Regexp.escape(name)}: flags=[0-9a-fA-F]+<([^>]*)>/)
        unless header
          errors << "Network interface #{name} could not be inspected."
          next
        end
        flags = header[1].split(',')
        status_line = output.lines.find { |line| line.match?(/\A\s+status:\s/) }
        status = status_line&.strip&.sub(/\Astatus:\s*/, '')
        { 'name' => name, 'loopback' => flags.include?('LOOPBACK'),
          'up' => flags.include?('UP'), 'running' => flags.include?('RUNNING'),
          'link_status' => status.nil? || status.empty? ? nil : status }
      end
      [interfaces, errors]
    end

    def unattached_pci(output)
      return [[], false] unless output

      malformed = false
      devices = output.lines.filter_map do |line|
        next unless line.match?(/\Anone\d*@pci/)

        match = line.match(/\Anone\d*@(pci\d+:\d+:\d+:\d+):\s+.*\bchip=0x([0-9a-fA-F]{8})\b/)
        unless match
          malformed = true
          next
        end
        chip = match[2].downcase
        { 'location' => match[1], 'vendor_id' => chip[4, 4], 'device_id' => chip[0, 4] }
      end
      [devices, malformed]
    end

    def unavailable(reason)
      { 'verdict' => 'not supported', 'complete' => false, 'observations' => {},
        'findings' => [{ 'severity' => 'blocking', 'code' => 'hardware_check_unavailable', 'message' => reason }] }
    end

    def read(*argv)
      output, ok = @run.call(*argv)
      ok ? output.strip : nil
    end

    def run_command(*argv)
      output, _error, status = Open3.capture3(*argv)
      [output, status.success?]
    rescue SystemCallError
      ['', false]
    end
  end
end
