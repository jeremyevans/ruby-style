require 'rubygems'
$eventmachine_library = :pure_ruby
require 'eventmachine'

module EventMachine
  class StreamObject < Selectable
    # Delete this when EventMachine fixes typo bug (Rubyforge bug #17461), see
    # https://rubyforge.org/tracker/index.php?func=detail&aid=17461&group_id=1555&atid=6060
    def eventable_write
      # coalesce the outbound array here, perhaps
      @last_activity = Reactor.instance.current_loop_time
      while data = @outbound_q.shift do
        begin
          data = data.to_s
          w = if io.respond_to?(:write_nonblock)
            io.write_nonblock data
          else
            io.syswrite data
          end

          if w < data.length
            @outbound_q.unshift data[w..-1]
            break
          end
        rescue Errno::EAGAIN
          @outbound_q.unshift data
        rescue EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED
          @close_scheduled = true
          @outbound_q.clear
        end
      end
    end
  end
  
  class EvmaTCPServer < Selectable
    class << self
      # Use $STYLE_SOCKET instead of creating a socket with the host and port
      def start_server(host, port)
        EvmaTCPServer.new $STYLE_SOCKET
      end
    end
  end
end
