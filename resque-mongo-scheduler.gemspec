# -*- encoding: utf-8 -*-
require File.expand_path("../lib/resque_scheduler/version", __FILE__)

Gem::Specification.new do |s|
  s.name        = "resque-mongo-scheduler"
  s.version     = ResqueScheduler::Version
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Ben VandenBos', 'Nicolas Fouche']
  s.email       = ['bvandenbos@gmail.com', 'nicolas@silentale.com']
  s.homepage    = "http://github.com/nfo/resque-mongo-scheduler"
  s.summary     = "Light weight job scheduling on top of Resque Mongo"
  s.description = %q{Light weight job scheduling on top of Resque Mongo.
    Adds methods enqueue_at/enqueue_in to schedule jobs in the future.
    Also supports queueing jobs on a fixed, cron-like schedule.}
  
  s.required_rubygems_version = ">= 1.3.6"
  s.add_development_dependency "bundler", ">= 1.0.0"

  s.files        = `git ls-files`.split("\n")
  s.executables  = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'
  
  s.add_runtime_dependency(%q<mongo>, [">= 1.1"])
  s.add_runtime_dependency(%q<resque-mongo>, [">= 1.9.8.1"])
  s.add_runtime_dependency(%q<rufus-scheduler>, [">= 0"])
  s.add_development_dependency(%q<mocha>, [">= 0"])
  s.add_development_dependency(%q<rack-test>, [">= 0"])
  
end
