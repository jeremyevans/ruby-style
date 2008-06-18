#!/usr/local/bin/ruby
require 'getoptlong'
require 'socket'
require 'thread'
require 'yaml'

# Supervised TCPServer, Yielding Listeners Easily
#
# Style creates a supervised (or unsupervised) group of processes listening on
# one or more TCP sockets.  It allows for rock solid restarting of processes
# without modifications to other software, since the same listening socket is
# reused, and replacement processes are started before the previous processes
# are killed.  The number of processes used can be increased or decreased on
# the fly by sending signals to the process.  Children that die are automatically
# restarted.  The general idea for this was inspired by Erlang/OTP's supervision
# trees.
class Style
  attr_reader :config, :mutex
  
  # Configure style
  def initialize
    @config = {:pidfile=>'style.pid', :number=>1, :port=>9999,
               :fork=>1, :bind=>'127.0.0.1',
               :cliconfig=>{}, :killtime=>2, :config=>'style.yaml',
               :logfile=>'style.log', :children=>{},:sockets=>{},
               :adapter_config=>{}, :directory=>'.', :debug=>false, 
               :unsupervised=> false, :adapter=>'rails', :handler=>'mongrel'}
    @mutex = Mutex.new
    begin
      parse_options
    rescue GetoptLong::InvalidOption
      exit_with_error($!)
    end
  end
  
  # Check that the directory of the given filename exists and is a directory, exit otherwise 
  def check_dir(filename)
    filename = File.expand_path(filename)
    dirname = File.dirname(filename)
    exit_with_error("Invalid directory: #{dirname}") unless File.directory?(dirname)
    filename
  end
  
  # Check that the filename given exists and is a file, exit otherwise 
  def check_file(filename)
    filename = File.expand_path(filename)
    exit_with_error("Invalid file: #{filename}") unless File.file?(filename)
    filename
  end

  # Return a hash of options from the config file, or an empty hash
  def config_file_options(filename)
    conf = YAML.load(File.read(filename)) rescue (return Hash.new)
    return Hash.new unless conf.is_a?(Hash)
    conf.delete(:directory)
    conf.delete(:config)
    conf
  end
  
  def create_socket(bind, port)
    socket = TCPServer.new(bind, port)
    socket.listen(50)
    socket
  end
  
  # Detach the process from the controlling terminal, exit otherwise
  def detach
    unless Process.setsid
      puts "Cannot detach from controlling terminal"
      exit(1)
    end
    trap(:HUP, 'IGNORE')
  end
  
  # Print the error message and the usage, then exit
  def exit_with_error(error_message)
    puts error_message
    puts usage
    exit(1)
  end
  
  # Kill each of the given pids in order
  def kill_children_gently(pids)
    pids.each{|pid| kill_gently(pid)}
  end

  # Try to allow the child to die gracefully, by trying INT, TERM, and then KILL
  def kill_gently(pid)
    begin
      Process.kill('INT', pid)
      sleep(config[:killtime])
      Process.kill('TERM', pid)
      sleep(config[:killtime])
      Process.kill('KILL', pid)
    rescue
      return nil
    end
  end
  
  # Load the revelent style adapter/framework
  def load_adapter
    adapter = config[:adapter].to_s
    if adapter == 'rails'
      require "style/adapter/rails"
      run
    else
      require adapter
    end
  end
  
  # Load the revelent style handler/server
  def load_handler
    require "style/handler/#{config[:handler]}"
  end

  # Parse the command line options, and merge them with the default options and
  # the config file options.  Config file options take precendence over the
  # default options, and command line options take precendence over both.
  def parse_options
    cliconfig = config[:cliconfig]
    GetoptLong.new(
      [ '--adapter', '-a', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--bind', '-b', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--config', '-c', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--directory', '-d', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--debug', '-D', GetoptLong::NO_ARGUMENT],
      [ '--fork', '-f', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--handler', '-h', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--killtime', '-k', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--logfile', '-l', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--number', '-n', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--port', '-p', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--pidfile', '-P', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--unsupervised', '-u', GetoptLong::NO_ARGUMENT]
    ).each do |opt, arg|
      case opt
        when '--adapter'
          cliconfig[:adapter] = arg
        when '--bind'
          cliconfig[:bind] = arg
        when '--config'
          config[:config] = cliconfig[:config] = arg
        when '--directory'
          config[:directory] = arg
        when '--debug'
          cliconfig[:debug] = true
        when '--fork'
          cliconfig[:fork] = arg.to_i
        when '--handler'
          cliconfig[:handler] = arg
        when '--killtime'
          cliconfig[:killtime] = arg.to_i
        when '--logfile'
          cliconfig[:logfile] = arg
        when '--number'
          cliconfig[:number] = arg.to_i
        when '--port'
          cliconfig[:port] = arg.to_i
        when '--pidfile'
          cliconfig[:pidfile] = arg
        when '--unsupervised'
          cliconfig[:unsupervised] = true
      end
    end
    
    config[:directory] = File.expand_path(config[:directory])
    Dir.chdir(config[:directory]) rescue (exit_with_error("Invalid directory: #{config[:directory]}"))
    
    cliconfig[:config] = File.expand_path(check_file(cliconfig[:config])) if cliconfig[:config]
    config[:config] = File.expand_path(config[:config])
    reload_config
    
    unless config[:debug]
      [:logfile, :pidfile].each do |opt|
        cliconfig[opt] = File.expand_path(cliconfig[opt]) if cliconfig[opt]
        config[opt] = File.expand_path(config[opt])
        config[opt] = check_dir(config[opt])
      end
    end
  end

  # Process the command given 
  def process(command)
    if config[:debug]
      run_in_foreground
    elsif config[:unsupervised]
      process_unsupervised_command(command)
    else
      process_supervised_command(command)
    end
  end

  # Process the command given in supervised mode.  All commands except start just send
  # a signal to the pid in the pid file.
  def process_supervised_command(command)
    case command
      when 'decrement'
        signal_supervisor(:USR2)
      when 'halt'
        signal_supervisor(:TERM)
      when 'increment'
        signal_supervisor(:USR1)
      when 'restart'
        signal_supervisor(:HUP)
      when 'run'
        supervisor_loop
      when 'start'
        supervisor_start
      when 'stop'
        signal_supervisor(:INT)
      else
        exit_with_error("Not a valid command: #{command}")
    end
  end

  # Process the command given in unsupervised mode.  Only restart, start, and stop
  # are supported.
  def process_unsupervised_command(command)
    case command
      when /\A(decrement|increment|run)\z/
        puts "#{$1} not supported in unsupervised mode"
        exit(1)
      when 'restart'
        stop
        start
      when 'start'
        start
      when /\A(stop|halt)\z/
        stop
      else
        exit_with_error("Not a valid command: #{command}")
    end
  end
  
  # Reset the umask and redirect STDIN to /dev/null and STDOUT and STDERR to
  # the appropriate logfile.
  def redirect_io
    File.umask(0000)
    STDIN.reopen('/dev/null') rescue nil
    begin
      STDOUT.reopen(config[:logfile], "a")
      STDOUT.sync = true
    rescue
      STDOUT.reopen('/dev/null') rescue nil
    end
    STDERR.reopen(STDOUT) rescue nil
    STDERR.sync = true
  end

  # Reload the configuration, used when restarting.  Only the following options
  # take effect when reloading: config, killtime, pidfile, adapter, handler,
  # and adapter_config.  
  def reload_config
    config.merge!(config_file_options(config[:config]))
    config.merge!(config[:cliconfig])
  end

  # Clear the gem paths so that restarts can pick up gems that have been added
  # since style was initially started
  def reload_gems
    Gem.clear_paths
    # This is done by clear_paths starting with rubygems-0.9.4.4
    Gem.instance_variable_set(:@searcher, nil) if Gem::RubyGemsVersion < '0.9.4.4'
  end
  
  # Restart stopping children by waiting on them.  If the children have died and
  # are in the list of children, restart them.
  def restart_stopped_children
    loop do
      break unless pid = Process.wait(-1, Process::WNOHANG)
      #puts "received sigchild, pid #{pid}"
      mutex.synchronize do
        if socket = config[:children].delete(pid)
          start_child(socket)
        end
      end
    end rescue nil
  end
  
  # Load the relevant handler and adapter and run the server
  def run_child
    load_handler
    load_adapter
  end
  
  # Run the program in the foreground instead of daemonizing.  Only runs on one
  # port, and obviously doesn't fork.
  def run_in_foreground
    $STYLE_SOCKET = create_socket(config[:bind], config[:port])
    config[:sockets][$STYLE_SOCKET] = config[:port]
    run_child
  end
  
  # Setup the necessary signals used in supervisory mode:
  #
  #  * CLD - Restart any dead children
  #  * HUP - Reload configuration and restart all children
  #  * INT - Gracefully shutdown children and exit
  #  * TERM - Immediately shutdown children and exit
  #  * USR1 - Increase the number of listeners on each port by 1
  #  * USR2 - Decrease the number of listeners on each port by 1
  #
  # Note that these signals should be sent to the supervising process,
  # the child processes are only required to shutdown on INT and TERM, and will
  # respond to other signals differently depending on the style used.
  def setup_supervisor_signals
    trap(:CLD) do
      # Child Died
      restart_stopped_children
    end
    trap(:HUP) do
      # Restart Children
      Dir.chdir(config[:directory]) rescue nil
      reload_config
      reload_gems
      supervisor_restart_children
    end
    trap(:INT) do
      # Graceful Shutdown
      supervisor_shutdown
      kill_children_gently(config[:children].keys)
      supervisor_exit
    end
    trap(:TERM) do
      # Fast Shutdown
      supervisor_shutdown
      pids = config[:children].keys
      Process.kill('TERM', *pids) rescue nil
      sleep(config[:killtime])
      Process.kill('KILL', *pids) rescue nil
      supervisor_exit
    end
    trap(:USR1) do
      # Increment number of children
      config[:sockets].keys.each do |socket|
        mutex.synchronize{start_child(socket)}
      end
    end
    trap(:USR2) do
      # Decrement number of children
      config[:children].invert.values.each do |pid|
        mutex.synchronize do 
          config[:children].delete(pid)
          kill_gently(pid)
        end
      end
    end
  end
  
  # Read the pid file and signal the supervising process, or raise an error
  def signal_supervisor(signal)
    begin
      pid = File.read(config[:pidfile]).to_i
    rescue
      puts "Can't read pidfile (#{config[:pidfile]}) to send signal #{signal}"
      exit(1)
    end
    if pid > 1
      Process.kill(signal, pid)
    else
      puts "Illegal value in pidfile"
      exit(1)
    end
  end

  # Start a child process.  The child process will reset the signals used, as
  # well as close any unused sockets, and then it should listen indefinitely on
  # the provided socket.
  def start_child(socket)
    return if config[:shutdown]
    pid = fork do
      $STYLE_SOCKET = socket
      [:HUP, :INT, :TERM, :USR1, :USR2].each{|signal| trap(signal, 'DEFAULT')}
      config[:sockets].keys.each{|sock| sock.close unless sock == socket}
      $0 = "#{process_name} port:#{config[:sockets][socket]}"
      run_child
    end
    #puts "started pid #{pid}"
    config[:children][pid] = socket
  end

  # Start an unsupervised group of processes
  def start
    fork do
      detach
      redirect_io
      config[:number].times do |i|
        port = config[:port]+i
        socket = create_socket(config[:bind], port)
        config[:sockets][socket] = port
        config[:fork].times{start_child(socket)}
      end
      File.open(config[:pidfile], 'wb'){|file| file.print("#{config[:children].keys.join(' ')}")}
    end
  end

  # Stop an unsupervised group of processes
  def stop
    if File.file?(config[:pidfile])
      pids = nil
      File.open(config[:pidfile], 'rb'){|f| pids = f.read.split.collect{|x| x.to_i if x.to_i > 1}.compact}
      if pids.length > 0
        kill_children_gently(pids)
        File.delete(config[:pidfile])
      end
    end
  end
  
  # Name of the Style
  def process_name
    "style-#{config[:adapter]}-#{config[:handler]} #{Dir.pwd}"
  end
  
  
  # Start all necessary children of the supervisor process (number * fork)
  def supervisor_children_start
    config[:number].times do |i|
      port = config[:port]+i
      socket = create_socket(config[:bind], port)
      config[:sockets][socket] = port
      config[:fork].times{start_child(socket)}
    end
  end

  # Remove the pid file and exit
  def supervisor_exit
    File.delete(config[:pidfile]) rescue nil
    exit
  end

  # Do the final setup of the supervisor process, and then loop indefinitely
  def supervisor_loop
    $0 = "#{process_name} supervisor"
    redirect_io
    supervisor_children_start
    setup_supervisor_signals
    loop{sleep(10) && restart_stopped_children}
  end

  # Restart all children of the supervisor process
  def supervisor_restart_children
    config[:children].keys.each do |pid|
      mutex.synchronize{start_child(config[:children].delete(pid))}
      sleep(config[:killtime])
      kill_gently(pid)
    end
  end
  
  # Set the internal shutdown signal for the supervisor process.  Once this is set,
  # no children will be restarted
  def supervisor_shutdown
    config[:shutdown] = true
  end

  # Start the supervisor process, detaching it from the controlling terminal
  def supervisor_start
    fork do
      detach
      File.open(config[:pidfile], 'wb'){|file| file.print(fork{supervisor_loop})}
    end
  end

  # The command line usage of the style program
  def usage
    <<-END
  style [option value, ...] (decrement|halt|increment|restart|run|start|stop)
   Options:
    -a, --adapter       Adapter/Framework to use [rails]
    -b, --bind          IP address to bind to [127.0.0.1]
    -c, --config        Location of config file [config/style.yaml]
    -d, --directory     Working directory [.]
    -D, --debug         Run the program in the foreground without forking [No]
    -f, --fork          Number of listners on each port [1]
    -h, --handler       Handler/Server to use [mongrel]
    -k, --killtime      Number of seconds to wait when killing each child [2]
    -l, --logfile       Where to redirect STDOUT and STDERR [log/style.log]
    -n, --number        Number of ports to which to bind [1]
    -p, --port          Starting port to which to bind [9999]
    -P, --pidfile       Location of pid file [log/style.pid]
    -u, --unsupervised  Whether to run unsupervised [No]
    END
  end
end
