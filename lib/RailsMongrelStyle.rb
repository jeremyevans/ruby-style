require 'rubygems'
require 'yaml'
require 'mongrel'
require 'mongrel/rails'
require 'etc'
require 'cgi_multipart_eof_fix' rescue nil

module Mongrel
  # Patch the Mongrel HttpServer to add a socket= method
  class HttpServer
    attr_writer :socket
    
    # Keep the interface the same, but ignore the host and port and don't
    # create a socket (one will be provided later)
    def initialize(host, port, num_processors=2**30-1, timeout=0)
      @classifier = URIClassifier.new
      @workers = ThreadGroup.new
      @timeout = timeout
      @num_processors = num_processors
      @death_time = 60
    end
  end
end

# This hooks the HTTP request into Ruby on Rails and Mongrel.
class RailsMongrelStyle
  attr_reader :mongrel
  
  # Initialzes Rails and Mongrel with the appropriate environment and settings.
  def initialize(settings)
    settings = {:cwd => Dir.pwd, :log_file => 'log/rails-mongrel.log', 
                :environment => 'production', :docroot => 'public',
                :mime_map => nil, :debug => false, :includes => ["mongrel"],
                :config_script => nil, :num_processors => 1024, :timeout => 0,
                :user => nil, :group => nil, :prefix => nil}.merge(settings)
    ENV['RAILS_ENV'] = settings[:environment]
    $0 += " environment:#{ENV['RAILS_ENV']}"
    @mongrel = Mongrel::Rails::RailsConfigurator.new(settings) do
      listener do
        mime = defaults[:mime_map] ? load_mime_map(defaults[:mime_map], mime) : {}
        debug "/" if defaults[:debug]
        uri defaults[:prefix] || "/", :handler => rails(:mime => mime, :prefix => defaults[:prefix])
        load_plugins
        run_config(defaults[:config_script]) if defaults[:config_script]
        setup_rails_signals
      end
    end
  end
  
  # Set the HttpServer to the correct socket and start running the mongrel event loop.
  def listen(socket)
    mongrel.instance_variable_get('@rails_handler').instance_variable_get('@listener').socket = socket
    mongrel.run
    mongrel.join
  end
end

GemPlugin::Manager.instance.load "mongrel" => GemPlugin::INCLUDE, "rails" => GemPlugin::EXCLUDE
