# frozen_string_literal: true

require 'json'
require 'socket'

module FoxynInstaller
  # One request per connection; no operation here can start an installation.
  class ReadOnlyServer
    ALLOWED = %w[capabilities check-hardware list-disks plan].freeze
    MAX_REQUEST = 16_384
    MAX_RESPONSE = 65_536
    TIMEOUT = 5.0
    SERVICE_TIMEOUT = 3.5

    def initialize(service:, authorized_uid:, peer_uid: nil, service_timeout: SERVICE_TIMEOUT)
      @service = service
      @service_timeout = service_timeout
      @authorized_uid = authorized_uid
      @peer_uid = peer_uid || ->(socket) { socket.getpeereid.first }
    end

    def handle(socket)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
      if @peer_uid.call(socket) != @authorized_uid
        send_response(socket, { 'error' => { 'code' => 'unauthorized' } }, deadline)
        return
      end
      data = read_line(socket, deadline)
      request = JSON.parse(data)
      response = if request.is_a?(Hash) && ALLOWED.include?(request['operation'])
                   service_response(request, deadline)
                 else
                   { 'version' => 1, 'id' => request.is_a?(Hash) ? request['id'] : nil,
                     'error' => { 'code' => 'operation_unavailable',
                                  'message' => 'This service only supports read-only requests.' } }
                 end
      send_response(socket, response, deadline)
    rescue JSON::ParserError, ArgumentError
      begin
        send_response(socket, { 'error' => { 'code' => 'invalid_request' } }, deadline)
      rescue IOError, SystemCallError, TimeoutError
        # Client may have disconnected while sending invalid input.
      end
    rescue IOError, SystemCallError, TimeoutError
      # A disconnected, unauthorized or stalled client cannot stop the server.
    ensure
      socket.close unless socket.closed?
    end

    class TimeoutError < StandardError; end

    private

    # Execute the read-only request in a separate session so a stuck probe
    # cannot prevent the privileged listener from accepting later requests.
    def service_response(request, connection_deadline)
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        begin
          Process.setsid
          Thread.current[:foxyn_request_worker] = true
          result = @service.call(request)
          output = JSON.generate(result)
          output = JSON.generate('error' => { 'code' => 'response_too_large' }) if output.bytesize > MAX_RESPONSE - 1
          writer.write(output)
        rescue StandardError
          writer.write(JSON.generate('error' => { 'code' => 'service_failed' })) rescue nil
        ensure
          writer.close
        end
        exit! 0
      end
      writer.close
      worker_deadline = [connection_deadline - 0.3,
                         Process.clock_gettime(Process::CLOCK_MONOTONIC) + @service_timeout].min
      data = +''
      loop do
        wait = worker_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return { 'error' => { 'code' => 'service_timeout' } } if wait <= 0
        next unless IO.select([reader], nil, nil, wait)
        part = reader.read_nonblock(4096, exception: false)
        next if part == :wait_readable
        break if part.nil?
        data << part
        return { 'error' => { 'code' => 'response_too_large' } } if data.bytesize > MAX_RESPONSE - 1
      end
      JSON.parse(data)
    rescue JSON::ParserError, IOError, SystemCallError
      { 'error' => { 'code' => 'service_failed' } }
    ensure
      writer&.close unless writer&.closed?
      reader&.close unless reader&.closed?
      if pid
        # The worker may not have reached setsid yet, so also signal it by PID.
        begin; Process.kill('KILL', -pid); rescue Errno::ESRCH; end
        begin; Process.kill('KILL', pid); rescue Errno::ESRCH; end
        begin; Process.detach(pid); rescue Errno::ECHILD; end
      end
    end

    def remaining(deadline)
      seconds = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise TimeoutError if seconds <= 0
      seconds
    end

    def read_line(socket, deadline)
      buffer = +''
      until buffer.include?("\n")
        raise ArgumentError if buffer.bytesize >= MAX_REQUEST
        raise TimeoutError unless IO.select([socket], nil, nil, remaining(deadline))
        chunk = socket.read_nonblock([4096, MAX_REQUEST - buffer.bytesize].min, exception: false)
        next if chunk == :wait_readable
        raise ArgumentError if chunk.nil? || chunk.empty?
        buffer << chunk
      end
      line, extra = buffer.split("\n", 2)
      raise ArgumentError if extra && !extra.empty?
      line
    end

    def send_response(socket, response, deadline)
      output = JSON.generate(response) + "\n"
      if output.bytesize > MAX_RESPONSE
        output = JSON.generate('error' => { 'code' => 'response_too_large' }) + "\n"
      end
      until output.empty?
        raise TimeoutError unless IO.select(nil, [socket], nil, remaining(deadline))
        count = socket.write_nonblock(output, exception: false)
        next if count == :wait_writable
        output = output.byteslice(count..-1) || ''
      end
    end
  end
end
