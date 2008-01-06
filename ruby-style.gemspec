spec = Gem::Specification.new do |s|
  s.name = "ruby-style"
  s.version = "1.0.2"
  s.author = "Jeremy Evans"
  s.email = "code@jeremyevans.net"
  s.platform = Gem::Platform::RUBY
  s.summary = "Supervised TCPServer, Yielding Listeners Easily"
  s.files = %w'LICENSE README lib/style.rb lib/RailsSCGIStyle.rb lib/RailsMongrelStyle.rb'
  s.require_paths = ["lib"]
  s.executables = %w'style'
  s.has_rdoc = true
  s.rdoc_options = %w'--inline-source --line-numbers'
  s.rubyforge_project = 'ruby-style'
end
