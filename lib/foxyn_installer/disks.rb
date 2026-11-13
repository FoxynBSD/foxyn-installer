# frozen_string_literal: true

require 'open3'

module FoxynInstaller
  # Inventory only: results do not establish that a disk is safe to erase.
  class Disks
    DEVICE_NAME = /\A[a-zA-Z][a-zA-Z0-9_+-]*\z/

    def initialize(run: nil, serials: nil, matching_devices: nil)
      @run = run || method(:run_command)
      @serials = serials || method(:serial_aliases)
      @matching_devices = matching_devices || method(:matching_devices)
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
      mount_output, mount_ok = @run.call('/sbin/mount')
      raise 'Could not read mounted filesystems.' unless mount_ok

      mounts = mount_output.lines.map do |line|
        match = line.chomp.match(/\A(.+?) on (.+?) \((.+)\)\z/)
        raise 'Unrecognized mount output.' unless match

        { 'source' => match[1], 'mountpoint' => match[2],
          'matching_disks' => @matching_devices.call(match[1], disks.map { |d| d['device'] }) }
      end
      { 'disks' => disks, 'mounts' => mounts, 'mount_associations_complete' => false,
        'target_safety_checked' => false }
    end

    private

    def warnings(name, size, aliases)
      warnings = ['Model and bus are unavailable.', 'Mount associations may be incomplete; live and busy devices are not identified.']
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

    # Match already-present device nodes only; never open the nodes.  This
    # records positive evidence, not proof that other disks are unused.
    def matching_devices(source, disks)
      return [] unless source.start_with?('/dev/')

      source_stat = File.stat(source)
      return [] unless source_stat.chardev?

      disks.select do |disk|
        candidates = [disk] + Dir.glob("#{disk}s[0-9]*")
        candidates.any? do |path|
          next false unless path == disk || path.match?(/\A#{Regexp.escape(disk)}s\d+[a-z]?\z/)
          stat = File.stat(path)
          stat.chardev? && stat.rdev == source_stat.rdev
        rescue SystemCallError
          false
        end
      end
    rescue SystemCallError
      []
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
