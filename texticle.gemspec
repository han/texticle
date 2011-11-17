$:.push File.expand_path("../lib", __FILE__)
require "texticle/version"

Gem::Specification.new do |s|
  s.name = %q{texticle}
  s.version     = Texticle::VERSION
  s.platform    = Gem::Platform::RUBY


  s.authors = ["ecin", "Aaron Patterson", "Han Kessels"]
  s.description = %q{Texticle exposes full text search capabilities from PostgreSQL, extending
    ActiveRecord with scopes making search easy and fun!}
  s.email = ["han.kessels@gmail.com"]

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.homepage = %q{http://tenderlove.github.com/texticle}
  s.rdoc_options = ["--main", "README.rdoc"]
  s.rubyforge_project = %q{texticle}
  s.summary = %q{Texticle exposes full text search capabilities from PostgreSQL}


  s.add_development_dependency(%q<pg>, ["~> 0.11.0"])
  s.add_development_dependency(%q<rake>, ["~> 0.8.0"])
  s.add_dependency(%q<activerecord>, ["~> 3.0"])
end

