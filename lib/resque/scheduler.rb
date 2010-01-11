require 'rufus-scheduler'
require 'rufus/scheduler'
require 'thwait'

module Resque

  class Scheduler

    extend Resque::Helpers

    class << self

      # If true, logs more stuff...
      attr_accessor :verbose
      
      # If set, produces no output
      attr_accessor :mute

      # Schedule all jobs and continually look for delayed jobs (never returns)
      def run

        # trap signals
        register_signal_handlers

        # Load the schedule into rufus
        load_schedule!

        # Now start the scheduling part of the loop.
        handle_delayed_items

        # never gets here.
      end

      # For all signals, set the shutdown flag and wait for current
      # poll/enqueing to finish (should be almost istant).  In the
      # case of sleeping, exit immediately.
      def register_signal_handlers
        trap("TERM") { shutdown }
        trap("INT") { shutdown }
        trap('QUIT') { shutdown } unless defined? JRUBY_VERSION
      end

      # Pulls the schedule from Resque.schedule and loads it into the
      # rufus scheduler instance
      def load_schedule!
        log! "Schedule empty! Set Resque.schedule" if Resque.schedule.empty?

        Resque.schedule.each do |name, config|
          log! "Scheduling #{name} "
          rufus_scheduler.cron config['cron'] do
            log! "queuing #{config['class']} (#{name})"
            enqueue_from_config(config)
          end
        end
      end

      # Loop that handles queueing delayed items (never exits)
      def handle_delayed_items
        loop do
          item = nil
          handle_shutdown do
            if timestamp = Resque.next_delayed_timestamp
              begin
                if item = Resque.next_item_for_timestamp(timestamp)
                  log "queuing #{item['class']} [delayed]"
                  klass = constantize(item['class'])
                  Resque.enqueue(klass, *item['args'])
                end
              end while !item.nil?
            end
          end
          poll_sleep
        end
      end

      def handle_shutdown
        exit if @shutdown
        yield
        exit if @shutdown
      end

      # Enqueues a job based on a config hash
      def enqueue_from_config(config)
        args = config['args'] || config[:args]
        klass_name = config['class'] || config[:class]
        params = args.nil? ? [] : Array(args)
        Resque.enqueue(constantize(klass_name), *params)
      end

      def rufus_scheduler
        @rufus_scheduler ||= Rufus::Scheduler.start_new
      end

      # Stops old rufus scheduler and creates a new one.  Returns the new
      # rufus scheduler
      def clear_schedule!
        rufus_scheduler.stop
        @rufus_scheduler = nil
        rufus_scheduler
      end

      # Sleeps and returns true
      def poll_sleep
        @sleeping = true
        handle_shutdown { sleep 5 }
        @sleeping = false
        true
      end

      # Sets the shutdown flag, exits if sleeping
      def shutdown
        @shutdown = true
        exit if @sleeping
      end

      def log!(msg)
        puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} #{msg}" unless mute
      end

      def log(msg)
        # add "verbose" logic later
        log!(msg) if verbose
      end

    end

  end

end