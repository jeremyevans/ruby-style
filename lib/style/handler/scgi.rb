require 'rubygems'
require 'scgi'

class SCGI::Processor
  # Use the standard error as the output logger, and use $STYLE_SOCKET as the
  # socket on which to listen
  def initialize(settings = {})
    @socket ||= $STYLE_SOCKET
    @total_conns ||= 0
    @shutdown ||= false
    @dead ||= false
    @threads ||= Queue.new
    @log = Object.new
    def @log.info(msg)
      STDERR.puts("[INF][#{@pid ||= Process.pid}] #{msg}")
    end
    def @log.error(msg, exc=nil)
      STDERR.puts("[ERR][#{@pid ||= Process.pid}] #{msg}#{": #{exc}\n#{exc.backtrace.join("\n")}" if exc}")
    end
    @maxconns ||= settings[:maxconns] || 2**30-1
    super()
    setup_signals
  end
end

# This SCGI::Processor subclass hooks the SCGI request into Ruby on Rails.
class RailsSCGIProcessor < SCGI::Processor
  # Initialzes Rails with the appropriate environment and settings
  def initialize(settings)
    $0 += " environment:#{ENV['RAILS_ENV'] = settings[:environment] || 'production'}"
    require 'config/environment'
    ActiveRecord::Base.allow_concurrency = false
    require 'dispatcher'
    super(settings)
    @guard = Mutex.new
  end

  # Submits requests to Rails in a single threaded fashion
  def process_request(request, body, socket)
    return if socket.closed?
    cgi = SCGI::CGIFixed.new(request, body, socket)
    begin
      @guard.synchronize{Dispatcher.dispatch(cgi, ActionController::CgiRequest::DEFAULT_SESSION_OPTIONS, cgi.stdoutput)}
    rescue IOError
      @log.error("received IOError #$! when handling client.  Your web server doesn't like me.")
    rescue Object => rails_error
      @log.error("calling Dispatcher.dispatch", rails_error)
    end
  end
end
