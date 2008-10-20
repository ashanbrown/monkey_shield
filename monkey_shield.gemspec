Gem::Specification.new do |s|
  s.name     = "monkey_shield"
  s.version  = "0.1.0"
  s.summary  = "protects you from monkey patching!"
  s.email    = "coderrr.contact@gmail.com"
  s.homepage = "http://github.com/coderrr/monkey_shieldgrit"
  s.description = "gets around the method collision problem of monkey patching by allowing you to define methods in contexts"
  s.has_rdoc = true
  s.authors  = ["coderrr"]
  s.files    = [
    "History.txt", 
    "Manifest.txt", 
    "README.txt", 
    "Rakefile", 
    "monkey_shield.gemspec", 
    "lib/monkey_shield.rb", 
    "lib/monkeyshield.rb"]
  s.test_files = ["spec/monkey_shield_spec.rb",
      "spec/real_libs_spec_explicit.rb"]
  s.rdoc_options = ["--main", "README.txt"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt", "README.txt"]
  s.add_dependency("RubyInline", [">= 3.6.7"])
end
