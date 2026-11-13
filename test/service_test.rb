# frozen_string_literal: true

module TestHarness
  def assert(condition, message = 'assertion failed')
    raise message unless condition
  end

  def assert_equal(expected, actual)
    assert(expected == actual, "expected #{expected.inspect}, got #{actual.inspect}")
  end
end
require 'json'
require 'open3'
require_relative '../lib/foxyn_installer/service'

class ServiceTest
  include TestHarness
  def setup
    @service = FoxynInstaller::Service.new
    @options = { 'mode' => 'simple', 'filesystem' => 'hammer2', 'components' => %w[base desktop],
                 'target' => { 'device' => '/dev/vbd1', 'model' => 'Test disk', 'serial' => '123',
                               'size_bytes' => 20_000_000_000 } }
  end

  def call(operation, options = nil)
    @service.call('version' => 1, 'id' => 'request-1', 'operation' => operation, 'options' => options)
  end

  def test_review_is_non_executable_and_includes_destructive_effect
    result = call('plan', @options).fetch('result')
    assert_equal false, result['executable']
    assert_equal false, result['target_verified']
    assert_equal @options['target'], result['target']
    assert_equal 'erase_disk', result['actions'].first['type']
    assert_equal 'hammer2', result['actions'][1]['root_filesystem']
  end

  def test_hardware_and_install_fail_closed
    assert_equal false, call('check-hardware').dig('result', 'complete')
    assert_equal 'not supported', call('check-hardware').dig('result', 'verdict')
    assert_equal false, call('install').dig('result', 'accepted')
    assert_equal false, call('capabilities').dig('result', 'installation_available')
  end

  def test_advanced_ufs_base_only_is_reviewable
    @options.merge!('mode' => 'advanced', 'filesystem' => 'ufs', 'components' => ['base'])
    result = call('plan', @options).fetch('result')
    assert_equal 'ufs', result['actions'][1]['root_filesystem']
    assert_equal ['base'], result['actions'][2]['components']
  end

  def test_rejects_bad_targets_and_options
    [nil, '/dev/vbd1;reboot', '/dev/../vbd1', '/tmp/disk', ''].each do |device|
      @options['target']['device'] = device
      assert_equal 'invalid_request', call('plan', @options).dig('error', 'code')
    end
    @options['target']['device'] = '/dev/vbd1'
    @options['components'] = %w[base desktop desktop]
    assert_equal 'invalid_request', call('plan', @options).dig('error', 'code')
    @options['components'] = ['base']
    assert_equal 'invalid_request', call('plan', @options).dig('error', 'code')
    @options['components'] = %w[base desktop]
    @options['filesystem'] = 'ufs'
    assert_equal 'invalid_request', call('plan', @options).dig('error', 'code')
  end

  def test_json_lines_continue_after_invalid_input
    binary = File.expand_path('../bin/foxyn-installer-backend', __dir__)
    input = "{bad\n" + JSON.generate('version' => 1, 'id' => 42, 'operation' => 'capabilities') + "\n"
    output, error, status = Open3.capture3(binary, stdin_data: input)
    assert status.success?, error
    rows = output.lines.map { |line| JSON.parse(line) }
    assert_equal 'invalid_json', rows[0].dig('error', 'code')
    assert_equal 42, rows[1]['id']
    assert_equal false, rows[1].dig('result', 'installation_available')
  end
end

suite = ServiceTest.new
methods = suite.public_methods(false).grep(/^test_/).sort
methods.each do |method|
  suite.setup
  suite.public_send(method)
  puts "PASS #{method}"
end
puts "#{methods.length} tests passed"
