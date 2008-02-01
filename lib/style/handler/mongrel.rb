require 'rubygems'
require 'mongrel'

module Mongrel
  class HttpServer
    # Keep the interface the same, but ignore the host and port and use the
    # socket provided by style
    def initialize(host, port, num_processors=950, throttle=0, timeout=60)
      tries = 0
      @socket = $STYLE_SOCKET
      @classifier = URIClassifier.new
      @host = host
      @port = port
      @workers = ThreadGroup.new
      @throttle = throttle
      @num_processors = num_processors
      @timeout = timeout
    end
  end
end
