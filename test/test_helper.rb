
# Pretty much copied this file from the resque-mongo test_helper since we want
# to do all the same stuff

dir = File.dirname(File.expand_path(__FILE__))

require 'rubygems'
require 'test/unit'
require 'mocha'
gem 'resque-mongo'
require 'resque'
require File.join(dir, '../lib/resque_scheduler')
$LOAD_PATH.unshift File.dirname(File.expand_path(__FILE__)) + '/../lib'


#
# make sure we can run redis
#

# if !system("which redis-server")
#   puts '', "** can't find `redis-server` in your path"
#   puts "** try running `sudo rake install`"
#   abort ''
# end


#
# start our own redis when the tests start,
# kill it when they end
#

# at_exit do
#   next if $!
# 
#   if defined?(MiniTest)
#     exit_code = MiniTest::Unit.new.run(ARGV)
#   else
#     exit_code = Test::Unit::AutoRunner.run
#   end
# 
#   pid = `ps -e -o pid,command | grep [r]edis-test`.split(" ")[0]
#   puts "Killing test redis server..."
#   `rm -f #{dir}/dump.rdb`
#   Process.kill("KILL", pid.to_i)
#   exit exit_code
# end

Resque.mongo = 'localhost:27017'

module Resque
  # Drop all collections in the 'monque' database.
  # Note: do not drop the database directly, as mongod allocates disk space
  # each time it's re-created.
  def flushall
    for name in @db.collection_names
      begin
        @db.drop_collection(name)
      rescue Mongo::OperationFailure
        # "can't drop system ns"
      end
    end
  end
end

##
# test/spec/mini 3
# http://gist.github.com/25455
# chris@ozmm.org
#
def context(*args, &block)
  return super unless (name = args.first) && block
  require 'test/unit'
  klass = Class.new(defined?(ActiveSupport::TestCase) ? ActiveSupport::TestCase : Test::Unit::TestCase) do
    def self.test(name, &block)
      define_method("test_#{name.gsub(/\W/,'_')}", &block) if block
    end 
    def self.xtest(*args) end 
    def self.setup(&block) define_method(:setup, &block) end 
    def self.teardown(&block) define_method(:teardown, &block) end 
  end 
  (class << klass; self end).send(:define_method, :name) { name.gsub(/\W/,'_') }
  klass.class_eval &block
end

class SomeJob
  def self.perform(repo_id, path)
  end
end

class SomeIvarJob < SomeJob
  @queue = :ivar
end
