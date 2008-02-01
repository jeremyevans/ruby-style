require 'rubygems'
require 'ramaze'

class Style
  # Run Ramaze with the mongrel adapter and start.rb runner
  def run
    settings = {:adapter=>config[:handler].to_sym, :test_connections=>false, 
                :force=>true, :runner =>'start.rb', :host=>config[:bind],
                :port=>config[:sockets][$STYLE_SOCKET]}.merge(config[:adapter_config])
    require settings[:runner].to_s
    Ramaze.start(settings)
  end
end

