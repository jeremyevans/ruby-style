require 'rake'
require 'rake/clean'

RDOC_OPTS = ["--quiet", "--line-numbers", "--inline-source"]
rdoc_task_class = begin
  require "rdoc/task"
  RDOC_OPTS.concat(['-f', 'hanna'])
  RDoc::Task
rescue LoadError
  require "rake/rdoctask"
  Rake::RDocTask
end

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += RDOC_OPTS
  rdoc.main = "README"
  rdoc.title = "style (Supervised TCPServer, Yielding Listeners Easily)"
  rdoc.rdoc_files.add ["README", "LICENSE", "lib/**/*.rb"]
end

desc "Package ruby-style"
task :package do
  sh %{gem build ruby-style.gemspec}
end
