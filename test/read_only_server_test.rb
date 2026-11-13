# frozen_string_literal: true

require_relative '../lib/foxyn_installer/read_only_server'
require_relative '../lib/foxyn_installer/service'
require 'tmpdir'
require 'rbconfig'

class FixtureService
  attr_reader :calls
  def initialize
    @calls = []
  end

  def call(request)
    @calls << request['operation']
    { 'version' => 1, 'id' => request['id'], 'result' => { 'available' => false } }
  end
end

def exchange(server, input)
  client, accepted = UNIXSocket.pair
  worker = Thread.new { server.handle(accepted) }
  client.write(input) if input
  client.close_write
  response = JSON.parse(client.read)
  worker.join
  client.close
  response
end

def assert(value, message)
  raise message unless value
end

service = FixtureService.new
server = FoxynInstaller::ReadOnlyServer.new(service: service, authorized_uid: 42, peer_uid: ->(_socket) { 42 })
response = exchange(server, "{\"version\":1,\"id\":7,\"operation\":\"capabilities\"}\n")
assert(response['id'] == 7 && response.dig('result', 'available') == false, 'read-only operation not routed')
response = exchange(server, "{\"version\":1,\"id\":8,\"operation\":\"install\"}\n")
assert(response.dig('error', 'code') == 'operation_unavailable', 'install reached service')
assert(exchange(server, "{bad\n").dig('error', 'code') == 'invalid_request', 'invalid JSON accepted')
assert(exchange(server, 'x' * 16_384).dig('error', 'code') == 'invalid_request', 'oversized request accepted')
unauthorized = FoxynInstaller::ReadOnlyServer.new(service: service, authorized_uid: 42, peer_uid: ->(_socket) { 43 })
assert(exchange(unauthorized, nil).dig('error', 'code') == 'unauthorized', 'wrong UID accepted')
slow = Object.new
def slow.call(_request)
  sleep 30
end
slow_server = FoxynInstaller::ReadOnlyServer.new(service: slow, authorized_uid: 42,
                                                  peer_uid: ->(_socket) { 42 }, service_timeout: 0.6)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
response = exchange(slow_server, "{\"version\":1,\"operation\":\"capabilities\"}\n")
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
assert(response.dig('error', 'code') == 'service_timeout' && elapsed < 3, 'service deadline failed')
response = exchange(server, "{\"version\":1,\"operation\":\"capabilities\"}\n")
assert(response.dig('result', 'available') == false, 'server did not recover after timeout')
Dir.mktmpdir('foxyn-timeout-test') do |directory|
  marker = File.join(directory, 'child-finished')
  child_service = Object.new
  child_service.define_singleton_method(:call) do |_request|
    pid = Process.spawn(RbConfig.ruby, '-e', 'sleep 1.5; File.write(ARGV[0], "unexpected")', marker)
    Process.wait(pid)
    {}
  end
  child_server = FoxynInstaller::ReadOnlyServer.new(service: child_service, authorized_uid: 42,
                                                    peer_uid: ->(_socket) { 42 }, service_timeout: 0.5)
  response = exchange(child_server, "{\"version\":1,\"operation\":\"capabilities\"}\n")
  assert(response.dig('error', 'code') == 'service_timeout', 'child service did not time out')
  sleep 1.7
  assert(!File.exist?(marker), 'child process survived request timeout')
end
if UNIXSocket.instance_methods.include?(:getpeereid)
  actual = Process.euid
  real_auth = FoxynInstaller::ReadOnlyServer.new(service: service, authorized_uid: actual)
  real_denial = FoxynInstaller::ReadOnlyServer.new(service: service, authorized_uid: actual + 1)
  request = JSON.generate('version' => 1, 'operation' => 'capabilities') + "\n"
  assert(exchange(real_auth, request).dig('result', 'available') == false, 'real peer credential rejected')
  assert(exchange(real_denial, nil).dig('error', 'code') == 'unauthorized', 'real wrong UID accepted')
end
puts 'Read-only server tests passed'
