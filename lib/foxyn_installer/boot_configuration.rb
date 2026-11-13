# frozen_string_literal: true

require 'tempfile'

module FoxynInstaller
  # Internal only. The caller must control the target tree and all mounts;
  # no disk selection, formatting, loader copy or authorization is done here.
  class BootConfiguration
    UUID = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

    def write(target:, root_uuid:, esp_uuid:, filesystem:, console:)
      raise ArgumentError, 'target must be a real directory' unless File.lstat(target).directory?
      raise ArgumentError, 'invalid root UUID' unless root_uuid.is_a?(String) && UUID.match?(root_uuid)
      raise ArgumentError, 'invalid ESP UUID' unless esp_uuid.is_a?(String) && UUID.match?(esp_uuid)
      raise ArgumentError, 'root and ESP must differ' if root_uuid.casecmp?(esp_uuid)
      raise ArgumentError, 'unsupported filesystem' unless %w[ufs hammer2].include?(filesystem)
      raise ArgumentError, 'unsupported console' unless %w[efi comconsole].include?(console)

      target = File.realpath(target)
      raise ArgumentError, 'target must not be the running root' if target == '/'
      %w[etc boot boot/efi boot/efi/boot].each do |path|
        raise ArgumentError, "unsafe or missing directory: #{path}" unless File.lstat(File.join(target, path)).directory?
      end
      rc_path = File.join(target, 'etc/rc.conf')
      raise ArgumentError, 'rc.conf must be a regular file' unless File.lstat(rc_path).file?
      fstab = File.join(target, 'etc/fstab')
      loader = File.join(target, 'boot/loader.conf')
      esp_loader = File.join(target, 'boot/efi/boot/loader.conf')
      [fstab, loader, esp_loader].each do |path|
        begin
          raise ArgumentError, "unsafe configuration file: #{path}" unless File.lstat(path).file?
        rescue Errno::ENOENT
          # A fresh target may not contain these files yet.
        end
      end
      root = "slice-by-uuid/#{root_uuid.downcase}"
      esp = "slice-by-uuid/#{esp_uuid.downcase}"
      check = filesystem == 'ufs' ? 1 : 0
      fstab_data = "# Device\tMountpoint\tFStype\tOptions\tDump\tPass#\n" \
                   "/dev/#{root}\t/\t#{filesystem}\trw\t#{check}\t#{check}\n" \
                   "/dev/#{esp}\t/boot/efi\tmsdos\trw,noauto\t0\t0\n"
      loader_data = "console=\"#{console}\"\n"
      loader_data << "boot_serial=\"YES\"\n" if console == 'comconsole'
      loader_data << "autoboot_delay=\"3\"\nvfs.root.mountfrom=\"#{filesystem}:#{root}\"\n"
      rc_data = File.readlines(rc_path).reject { |line| line.match?(/\A\s*root_rw_mount\s*=/) }.join
      atomic_write(fstab, fstab_data)
      atomic_write(loader, loader_data)
      atomic_write(esp_loader, loader_data)
      atomic_write(rc_path, rc_data)
      { 'root_device' => root, 'esp_device' => esp }
    end

    private

    def atomic_write(path, contents)
      mode = File.exist?(path) ? (File.stat(path).mode & 0o777) : 0o644
      Tempfile.create('.foxyn-config-', File.dirname(path)) do |file|
        file.chmod(mode)
        file.write(contents)
        file.flush
        File.rename(file.path, path)
      end
    end
  end
end
