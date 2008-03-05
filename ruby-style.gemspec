spec = Gem::Specification.new do |s|
  s.name = "ruby-style"
  s.version = "1.1.3"
  s.author = "Jeremy Evans"
  s.email = "code@jeremyevans.net"
  s.platform = Gem::Platform::RUBY
  s.summary = "Supervised TCPServer, Yielding Listeners Easily"
  s.files = %w'LICENSE README' + Dir['lib/**/*.rb']
  s.require_paths = ["lib"]
  s.executables = %w'style'
  s.has_rdoc = true
  s.rdoc_options = %w'--inline-source --line-numbers README lib'
  s.rubyforge_project = 'ruby-style'
end
