# frozen_string_literal: true

require_relative 'disks'

module FoxynInstaller
  # Protocol version 1 is intentionally read-only until the installer has
  # verified hardware detection, target discovery and an execution backend.
  class Service
    PROTOCOL_VERSION = 1
    MODES = %w[simple advanced].freeze
    FILESYSTEMS = %w[hammer2 ufs].freeze
    COMPONENTS = %w[base desktop].freeze

    def initialize(disks: Disks.new)
      @disks = disks
    end

    def call(request)
      raise ArgumentError, 'request must be an object' unless request.is_a?(Hash)
      raise ArgumentError, 'unsupported protocol version' unless request['version'] == PROTOCOL_VERSION

      result = case request['operation']
               when 'capabilities' then capabilities
               when 'check-hardware' then hardware
               when 'list-disks' then @disks.list
               when 'plan' then plan(request['options'])
               when 'install' then install_unavailable
               else raise ArgumentError, 'unknown operation'
               end
      { 'version' => PROTOCOL_VERSION, 'id' => request['id'], 'result' => result }
    rescue RuntimeError => e
      { 'version' => PROTOCOL_VERSION, 'id' => request.is_a?(Hash) ? request['id'] : nil,
        'error' => { 'code' => 'discovery_failed', 'message' => e.message } }
    rescue ArgumentError => e
      { 'version' => PROTOCOL_VERSION, 'id' => request.is_a?(Hash) ? request['id'] : nil,
        'error' => { 'code' => 'invalid_request', 'message' => e.message } }
    end

    private

    def capabilities
      { 'operations' => %w[capabilities check-hardware list-disks plan install],
        'installation_available' => false, 'disk_inventory_available' => true, 'target_discovery_available' => false,
        'target_safety_checked' => false }
    end

    def hardware
      { 'verdict' => 'not supported', 'complete' => false,
        'findings' => [{ 'severity' => 'blocking', 'code' => 'hardware_check_unavailable',
                         'message' => 'Hardware compatibility cannot yet be verified; installation is disabled.' }] }
    end

    def plan(options)
      raise ArgumentError, 'options must be an object' unless options.is_a?(Hash)
      mode = options['mode']
      filesystem = options['filesystem']
      components = options['components']
      target = options['target']
      raise ArgumentError, 'mode must be simple or advanced' unless MODES.include?(mode)
      raise ArgumentError, 'filesystem must be hammer2 or ufs' unless FILESYSTEMS.include?(filesystem)
      raise ArgumentError, 'simple mode requires hammer2' if mode == 'simple' && filesystem != 'hammer2'
      unless components.is_a?(Array) && components.uniq == components &&
             components.include?('base') && (components - COMPONENTS).empty?
        raise ArgumentError, 'components must include base and may include desktop once'
      end
      if mode == 'simple' && !components.include?('desktop')
        raise ArgumentError, 'simple mode requires the desktop'
      end
      unless target.is_a?(Hash) && %w[device model serial].all? { |key| target[key].is_a?(String) && !target[key].strip.empty? } &&
             target['size_bytes'].is_a?(Integer) && target['size_bytes'].positive?
        raise ArgumentError, 'target must include device, model, serial and positive size_bytes'
      end
      unless target['device'].match?(/\A\/dev\/[A-Za-z0-9_+-]+\z/)
        raise ArgumentError, 'target device must be a simple path under /dev'
      end

      { 'executable' => false, 'target_verified' => false,
        'target' => target.slice('device', 'model', 'serial', 'size_bytes'),
        'actions' => [
          { 'type' => 'erase_disk', 'description' => 'Erase the entire target disk.' },
          { 'type' => 'partition', 'scheme' => 'GPT', 'boot' => 'UEFI', 'root_filesystem' => filesystem },
          { 'type' => 'install_components', 'components' => components }
        ],
        'blockers' => ['Target identity and hardware compatibility have not been verified.',
                       'Installation operations are not implemented.'] }
    end

    def install_unavailable
      { 'accepted' => false, 'code' => 'installation_unavailable',
        'message' => 'No changes were made. Installation is not implemented.' }
    end
  end
end
