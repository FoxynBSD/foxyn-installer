# frozen_string_literal: true

module FoxynInstaller
  # Executes a fixed argv without a shell; returns failure on timeout or excess output.
  class Command
    def initialize(timeout: 5.0, max_output: 1_048_576)
      @timeout = timeout
      @max_output = max_output
    end

    def call(*argv)
      reader, writer = IO.pipe
      # A request worker has its own process group.  Keep probes in it so the
      # server can terminate the entire request on deadline.
      in_worker = Thread.current[:foxyn_request_worker] == true
      pid = Process.spawn(*argv, in: File::NULL, out: writer, err: File::NULL,
                          pgroup: !in_worker, close_others: true)
      writer.close
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      output = +''.b
      status = nil
      eof = false
      loop do
        status ||= Process.waitpid2(pid, Process::WNOHANG)&.last
        return [output.force_encoding(Encoding.default_external), status.success?] if status && eof

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return ['', false] if remaining <= 0
        if eof
          sleep([remaining, 0.05].min)
          next
        end
        next unless IO.select([reader], nil, nil, [remaining, 0.05].min)
        chunk = reader.read_nonblock(4096, exception: false)
        next if chunk == :wait_readable
        if chunk.nil?
          eof = true
        else
          output << chunk
          return ['', false] if output.bytesize > @max_output
        end
      end
    rescue SystemCallError, IOError
      ['', false]
    ensure
      writer&.close unless writer&.closed?
      reader&.close unless reader&.closed?
      if pid && !status
        begin
          Process.kill('KILL', in_worker ? pid : -pid)
        rescue Errno::ESRCH
          # The process may have just exited.
        end
        begin
          # Reap asynchronously: an uninterruptible kernel wait must not
          # hold the service request open after the deadline.
          Process.detach(pid)
        rescue Errno::ECHILD
          # Already reaped.
        end
      end
    end
  end
end
