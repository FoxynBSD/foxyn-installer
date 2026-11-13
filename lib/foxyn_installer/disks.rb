# frozen_string_literal: true

require 'open3'

module FoxynInstaller
  # Inventory only: results do not establish that a disk is safe to erase.
  class Disks
    DEVICE_NAME = /\A[a-zA-Z][a-zA-Z0-9_+-]*\z/

    def initialize(run: nil, serials: nil)
      @run = run || method(:run_command)
      @serials = serials || method(:serial_aliases)
    end

    def list
      os, os_ok = @run.call('/usr/bin/uname', '-s')
      raise 'Disk discovery requires DragonFly BSD.' unless os_ok && os.strip == 'DragonFly'

      names, ok = @run.call('/sbin/sysctl', '-n', 'kern.disks')
      raise 'Could not read kern.disks.' unless ok

      disks = names.split.map do |name|
        raise 'Invalid device name reported by kern.disks.' unless DEVICE_NAME.match?(name)

        device = "/dev/#{name}"
        # Opening unused virtual devices can instantiate them. Report these
        # entries without probing; future disposable-target tests can opt in.
        if name.match?(/\A(?:md|vn)\d+\z/)
          next({ 'device' => device, 'size_bytes' => nil, 'serial' => nil,
                 'model' => nil, 'bus' => nil, 'information_complete' => false,
                 'warnings' => warnings(name, nil, []) })
        end

        output, disk_ok = @run.call('/sbin/diskinfo', device)
        # diskinfo can exit successfully while reporting a per-device error.
        match = disk_ok && output.match(/\A#{Regexp.escape(device)}\s+blksize=\d+\s+offset=0x[0-9a-fA-F]+\s+size=0x([0-9a-fA-F]+)\s/)
        size = match && match[1].to_i(16)
        aliases = @serials.call(device)
        { 'device' => device, 'size_bytes' => size,
          'serial' => aliases.length == 1 ? aliases.first : nil,
          'model' => nil, 'bus' => nil,
          'information_complete' => false,
          'warnings' => warnings(name, size, aliases) }
      end
      { 'disks' => disks, 'target_safety_checked' => false }
    end

    private

    def warnings(name, size, aliases)
      warnings = ['Model and bus are unavailable.', 'Mounted, live and busy devices have not been identified.']
      warnings << 'Disk size is unavailable.' unless size && size.positive?
      warnings << (aliases.empty? ? 'Serial number is unavailable.' : 'Serial number is ambiguous.') unless aliases.length == 1
      warnings << 'Memory or virtual device; not assessed as an installation target.' if name.match?(/\A(?:md|vn)\d+\z/)
      warnings
    end

    def run_command(*argv)
      out, _err, status = Open3.capture3(*argv)
      [out, status.success?]
    rescue SystemCallError
      ['', false]
    end

    def serial_aliases(device)
      target = File.stat(device)
      return [] unless target.chardev?

      Dir.children('/dev/serno').filter_map do |name|
        next if name.match?(/\.s\d+(?:[a-z])?\z/)

        candidate = File.stat(File.join('/dev/serno', name))
        name if candidate.chardev? && candidate.rdev == target.rdev
      rescue SystemCallError
        nil
      end.sort
    rescue SystemCallError
      []
    end
  end
end
