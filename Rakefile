require 'rake'
require 'rake/clean'
require 'rake/rdoctask'

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += ["--quiet", "--line-numbers", "--inline-source"]
  rdoc.main = "README"
  rdoc.title = "style (Supervised TCPServer, Yielding Listeners Easily)"
  rdoc.rdoc_files.add ["README", "LICENSE", "lib/**/*.rb"]
end

desc "Update docs and upload to rubyforge.org"
task :doc_rforge => [:rdoc]
task :doc_rforge do
  sh %{chmod -R g+w rdoc/*}
  sh %{scp -rp rdoc/* rubyforge.org:/var/www/gforge-projects/ruby-style}
end

desc "Package ruby-style"
task :package do
  sh %{gem build ruby-style.gemspec}
end
