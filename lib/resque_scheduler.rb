require 'rubygems'
gem 'resque-mongo'
require 'resque'
require 'resque/server'
require 'resque_scheduler/version'
require 'resque/scheduler'
require 'resque_scheduler/server'
require 'resque_scheduler/search_delayed'

module ResqueScheduler

  def schedules
    self.mongo ||= ENV['MONGO'] || 'localhost:27017'
    @schedules ||= @db.collection('schedules')
  end

  def schedules_changed
    self.mongo ||= ENV['MONGO'] || 'localhost:27017'
    @schedules_changed ||= @db.collection('schedules_changed')
  end

  def delayed_queue
    self.mongo ||= ENV['MONGO'] || 'localhost:27017'
    @delayed_queue ||= @db.collection('delayed_queue')
  end

  #
  # Accepts a new schedule configuration of the form:
  #
  #   {some_name => {"cron" => "5/* * * *",
  #                  "class" => DoSomeWork,
  #                  "args" => "work on this string",
  #                  "description" => "this thing works it"s butter off"},
  #    ...}
  #
  # :name can be anything and is used only to describe the scheduled job
  # :cron can be any cron scheduling string :job can be any resque job class
  # :every can be used in lieu of :cron. see rufus-scheduler's 'every' usage for 
  #   valid syntax. If :cron is present it will take precedence over :every.
  # :class must be a resque worker class
  # :args can be any yaml which will be converted to a ruby literal and passed
  #   in a params. (optional)
  # :rails_envs is the list of envs where the job gets loaded. Envs are comma separated (optional)
  # :description is just that, a description of the job (optional). If params is
  #   an array, each element in the array is passed as a separate param,
  #   otherwise params is passed in as the only parameter to perform.
  def schedule=(schedule_hash)
    if Resque::Scheduler.dynamic
      schedule_hash.each do |name, job_spec|
        set_schedule(name, job_spec)
      end
    end
    @schedule = schedule_hash
  end

  # Returns the schedule hash
  def schedule
    @schedule ||= {}
  end
  
  # reloads the schedule from mongo
  def reload_schedule!
    @schedule = get_schedules
  end
  
  # gets the schedule as it exists in mongo
  def get_schedules
    if schedules.count > 0
      h = {}
      schedules.find.each do |a|
        h[a.delete('_id')] = a
      end
      h
    else
      nil
    end
  end
  
  # create or update a schedule with the provided name and configuration
  def set_schedule(name, config)
    existing_config = get_schedule(name)
    unless existing_config && existing_config == config
      schedules.insert(config.merge('_id' => name))
      schedules_changed.insert('_id' => name)
    end
    config
  end
  
  # retrieve the schedule configuration for the given name
  def get_schedule(name)
    schedule = schedules.find_one('_id' => name)
    schedule.delete('_id') if schedule
    schedule
  end
  
  # remove a given schedule by name
  def remove_schedule(name)
    schedules.remove('_id' => name)
    schedules_changed.insert('_id' => name)
  end

  def pop_schedules_changed
    while doc = schedules_changed.find_and_modify(:remove => true)
      yield doc['_id']
    end
  rescue Mongo::OperationFailure
    # "Database command 'findandmodify' failed: {"errmsg"=>"No matching object found", "ok"=>0.0}"
    # Sadly, the mongo driver raises (with a global exception class) instead of returning nil when
    # the collection is empty.
  end

  # This method is nearly identical to +enqueue+ only it also
  # takes a timestamp which will be used to schedule the job
  # for queueing.  Until timestamp is in the past, the job will
  # sit in the schedule list.
  # @return the number of items for this timestamp
  def enqueue_at(timestamp, klass, *args)
    delayed_push(timestamp, job_to_hash(klass, args))
  end

  # Identical to enqueue_at but takes number_of_seconds_from_now
  # instead of a timestamp.
  # @return the number of items for this timestamp
  def enqueue_in(number_of_seconds_from_now, klass, *args)
    enqueue_at(Time.now + number_of_seconds_from_now, klass, *args)
  end

  # Used internally to stuff the item into the schedule sorted list.
  # +timestamp+ can be either in seconds or a datetime object
  # Insertion if O(log(n)).
  # Returns true if it's the first job to be scheduled at that time, else false
  # @return the number of items for this timestamp
  def delayed_push(timestamp, item)
    # Add this item to the list for this timestamp
    doc = delayed_queue.find_and_modify(
      :query => {'_id' => timestamp.to_i},
      :update => {'$push' => {:items => item}},
      :upsert => true,
      :new => true
    )
    doc['items'].size
  end

  # Returns an array of timestamps based on start and count
  def delayed_queue_peek(start, count)
    delayed_queue.find({}, :skip => start, :limit => count, :fields => '_id', :sort => ['_id', 1]).map {|d| d['_id']}
  end

  # Returns the size of the delayed queue schedule
  def delayed_queue_schedule_size
    delayed_queue.count
  end

  # Returns the number of jobs for a given timestamp in the delayed queue schedule
  def delayed_timestamp_size(timestamp)
    document = delayed_queue.find_one('_id' => timestamp.to_i)
    document ? (document['items'] || []).size : 0
  end

  # Returns an array of delayed items for the given timestamp
  def delayed_timestamp_peek(timestamp, start, count)
    doc = delayed_queue.find_one(
      {'_id' => timestamp.to_i},
      :fields => {'items' => {'$slice' => [start, count]}}
    )
    doc ? doc['items'] || [] : []
  end

  # Returns the next delayed queue timestamp
  # (don't call directly)
  def next_delayed_timestamp(at_time=nil)
    doc = delayed_queue.find_one(
      {'_id' => {'$lte' => (at_time || Time.now).to_i}},
      :sort => ['_id', Mongo::ASCENDING]
    )
    doc ? doc['_id'] : nil
  end

  # Returns the next item to be processed for a given timestamp, nil if
  # done. (don't call directly)
  # +timestamp+ can either be in seconds or a datetime
  def next_item_for_timestamp(timestamp)
    # Returns the array of items before it was shifted
    doc = delayed_queue.find_and_modify(
      :query => {'_id' => timestamp.to_i},
      :update => {'$pop' => {'items' => -1}} # -1 means shift
    )
    item = doc['items'].first
    
    # If the list is empty, remove it.
    clean_up_timestamp(timestamp)
    
    item
  rescue Mongo::OperationFailure
    # Database command 'findandmodify' failed: {"errmsg"=>"No matching object found", "ok"=>0.0}
    nil
  end

  # Clears all jobs created with enqueue_at or enqueue_in
  def reset_delayed_queue
    delayed_queue.remove
  end

  # given an encoded item, remove it from the delayed_queue
  # does not clean like +next_item_for_timestamp+
  # TODO ? unlike resque-scheduler, it does not return the number of removed items,
  # can't use find_and_modify because it only updates one item.
  def remove_delayed(klass, *args)
    delayed_queue.update(
      {},
      {'$pull' => {'items' => job_to_hash(klass, args)}},
      :multi => true
    )
  end

  def count_all_scheduled_jobs
    total_jobs = 0
    delayed_queue.find.each do |doc|
      total_jobs += (doc['items'] || []).size
    end
    total_jobs
  end 

  private
    def job_to_hash(klass, args)
      {:class => klass.to_s, :args => args, :queue => queue_from_class(klass).to_s}
    end

    def clean_up_timestamp(timestamp)
      delayed_queue.remove('_id' => timestamp.to_i, :items => {'$size' => 0})
    end

end

Resque.extend ResqueScheduler
Resque::Server.class_eval do
  include ResqueScheduler::Server
end
