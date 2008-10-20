require 'lib/monkey_shield'
require 'rake'
require 'spec/rake/spectask'

desc "Run all examples"
Spec::Rake::SpecTask.new('spec') do |t|
  t.spec_files = FileList['spec/**/*.rb']
end

require 'rubygems'
require 'hoe'

Hoe.new('monkeyshield', MonkeyShield::VERSION) do |p|
  p.rubyforge_name = 'coderrr'
  p.author = 'coderrr'
  p.email = 'coderrr.contact@gmail.com'
  # p.summary = 'FIX'
  p.description = p.paragraphs_of('README.txt', 0..1).join("\n\n")
  # p.url = p.paragraphs_of('README.txt', 0).first.split(/\n/)[1..-1]
  p.changes = p.paragraphs_of('History.txt', 0..1).join("\n\n")
  p.remote_rdoc_dir = '' # Release to root
  p.extra_deps << ["RubyInline", ">= 3.6.7"]
end
