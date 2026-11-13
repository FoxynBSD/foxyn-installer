# frozen_string_literal: true

require 'open3'

module FoxynInstaller
  # Internal building block, not exposed by the installer protocol.  Its
  # caller must own both trees and prevent concurrent path replacement.
  class SystemCopy
    DIRECTORIES = %w[bin boot etc lib libexec root sbin usr var].freeze

    class Error < StandardError
      attr_reader :directory

      def initialize(directory, message)
        @directory = directory
        super(message)
      end
    end

    def initialize(cpdup: '/bin/cpdup', run: nil)
      @cpdup = cpdup
      @run = run || method(:run_cpdup)
    end

    def copy(source:, target:, progress: nil)
      raise ArgumentError, 'target must be a real directory' unless File.lstat(target).directory?
      source = File.realpath(source)
      target = File.realpath(target)
      raise ArgumentError, 'source must be a directory' unless File.directory?(source)
      raise ArgumentError, 'target must be empty' unless Dir.empty?(target)
      raise ArgumentError, 'source and target must differ' if source == target

      directories = DIRECTORIES.select { |name| File.directory?(File.join(source, name)) }
      raise ArgumentError, 'source contains no system directories' if directories.empty?
      directories.each do |name|
        origin = File.realpath(File.join(source, name))
        if target == origin || target.start_with?(origin + '/') || origin.start_with?(target + '/')
          raise ArgumentError, 'source and target trees overlap'
        end
      end

      directories.each do |name|
        progress&.call('directory' => name, 'state' => 'started')
        success, error = @run.call(@cpdup, File.join(source, name), File.join(target, name))
        raise Error.new(name, "Copy of #{name} failed: #{error}") unless success
        progress&.call('directory' => name, 'state' => 'completed')
      end
      { 'copied_directories' => directories }
    end

    private

    def run_cpdup(program, source, target)
      _out, error, status = Open3.capture3(program, '-i0', '-s0', '-q', source, target)
      [status.success?, error.strip]
    rescue SystemCallError => e
      [false, e.message]
    end
  end
end
