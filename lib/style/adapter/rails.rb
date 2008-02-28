require 'rubygems'

# This hooks the HTTP request into Ruby on Rails and Mongrel.
class Style
  # Initialzes Rails and Mongrel with the appropriate environment and settings.
  def run
    if config[:handler] == 'scgi'
      run_rails_scgi
    elsif config[:handler] == 'thin'
      run_rails_thin
    else
      run_rails_mongrel
    end
  end
  
  def run_rails_thin
    options = {:environment=>'production', :address=>config[:bind],
      :port=>config[:sockets][$STYLE_SOCKET], :pid=>'/dev/null',
      :log=>'/dev/null', :timeout=>Thin::Server::DEFAULT_TIMEOUT,
      :max_persistent_conns=>Thin::Server::DEFAULT_MAXIMUM_PERSISTENT_CONNECTIONS,
      :max_conns=>Thin::Server::DEFAULT_MAXIMUM_CONNECTIONS}.merge(config[:adapter_config])
    Thin::Controllers::Controller.new(options).start
  end
  
  def run_rails_scgi
    RailsSCGIProcessor.new(config[:adapter_config]).listen
  end
  
  def run_rails_mongrel
    require 'mongrel/rails'
    settings = {:cwd => Dir.pwd, :log_file => 'log/rails-mongrel.log', 
                :environment => 'production', :docroot => 'public',
                :mime_map => nil, :debug => false, :includes => ["mongrel"],
                :config_script => nil, :num_processors => 1024, :timeout => 0,
                :user => nil, :group => nil, :prefix => nil}.merge(config[:adapter_config])
    ENV['RAILS_ENV'] = settings[:environment]
    $0 += " environment:#{ENV['RAILS_ENV']}"
    mongrel = Mongrel::Rails::RailsConfigurator.new(settings) do
      listener do
        mime = defaults[:mime_map] ? load_mime_map(defaults[:mime_map], mime) : {}
        debug "/" if defaults[:debug]
        uri defaults[:prefix] || "/", :handler => rails(:mime => mime, :prefix => defaults[:prefix])
        load_plugins
        run_config(defaults[:config_script]) if defaults[:config_script]
        trap("INT") { @log.info("SIGTERM, forced shutdown."); shutdown(force=true) }
        setup_rails_signals
      end
    end
    mongrel.run
    mongrel.join
  end
end
