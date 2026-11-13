# frozen_string_literal: true

require_relative '../lib/foxyn_installer/read_only_server'
require_relative '../lib/foxyn_installer/service'

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
assert(response['id'] == 7 && service.calls == ['capabilities'], 'read-only operation not routed')
response = exchange(server, "{\"version\":1,\"id\":8,\"operation\":\"install\"}\n")
assert(response.dig('error', 'code') == 'operation_unavailable' && service.calls == ['capabilities'], 'install reached service')
assert(exchange(server, "{bad\n").dig('error', 'code') == 'invalid_request', 'invalid JSON accepted')
assert(exchange(server, 'x' * 16_384).dig('error', 'code') == 'invalid_request', 'oversized request accepted')
unauthorized = FoxynInstaller::ReadOnlyServer.new(service: service, authorized_uid: 42, peer_uid: ->(_socket) { 43 })
assert(exchange(unauthorized, nil).dig('error', 'code') == 'unauthorized', 'wrong UID accepted')
if UNIXSocket.instance_methods.include?(:getpeereid)
  actual = Process.euid
  real_auth = FoxynInstaller::ReadOnlyServer.new(service: service, authorized_uid: actual)
  real_denial = FoxynInstaller::ReadOnlyServer.new(service: service, authorized_uid: actual + 1)
  request = JSON.generate('version' => 1, 'operation' => 'capabilities') + "\n"
  assert(exchange(real_auth, request).dig('result', 'available') == false, 'real peer credential rejected')
  assert(exchange(real_denial, nil).dig('error', 'code') == 'unauthorized', 'real wrong UID accepted')
end
puts 'Read-only server tests passed'
