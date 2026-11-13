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
      findings = [{ 'severity' => 'blocking', 'code' => 'hardware_check_incomplete',
                    'message' => 'Hardware compatibility has not been fully checked; installation is disabled.' }]
      if arch.nil? || arch.empty?
        findings << { 'severity' => 'blocking', 'code' => 'architecture_unavailable',
                      'message' => 'CPU architecture could not be read.' }
      elsif arch != 'x86_64'
        findings << { 'severity' => 'blocking', 'code' => 'unsupported_architecture',
                      'message' => "Architecture #{arch} is not supported by this installer." }
      end
      if memory.nil?
        findings << { 'severity' => 'blocking', 'code' => 'memory_unavailable',
                      'message' => 'Physical memory could not be read.' }
      end
      { 'verdict' => 'not supported', 'complete' => false,
        'observations' => { 'architecture' => arch, 'cpu_model' => model,
                            'physical_memory_bytes' => memory, 'boot_evidence' => boot_evidence },
        'findings' => findings }
    end

    private

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
