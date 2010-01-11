require File.dirname(__FILE__) + '/test_helper'

class Resque::DelayedQueueTest < Test::Unit::TestCase

  def setup
    Resque::Scheduler.mute = true
    Resque.redis.flush_all
  end

  def test_enqueue_at_adds_correct_list_and_zset

    timestamp = Time.now - 1 # 1 second ago (in the past, should come out right away)

    assert_equal(0, Resque.redis.llen("delayed:#{timestamp.to_i}").to_i, "delayed queue should be empty to start")

    Resque.enqueue_at(timestamp, SomeIvarJob, "path")

    # Confirm the correct keys were added
    assert_equal(1, Resque.redis.llen("delayed:#{timestamp.to_i}").to_i, "delayed queue should have one entry now")
    assert_equal(1, Resque.redis.zcard(:delayed_queue_schedule), "The delayed_queue_schedule should have 1 entry now")

    read_timestamp = Resque.next_delayed_timestamp

    # Confirm the timestamp came out correctly
    assert_equal(timestamp.to_i, read_timestamp, "The timestamp we pull out of redis should match the one we put in")
    item = Resque.next_item_for_timestamp(read_timestamp)

    # Confirm the item came out correctly
    assert_equal('SomeIvarJob', item['class'], "Should be the same class that we queued")
    assert_equal(["path"], item['args'], "Should have the same arguments that we queued")
    
    # And now confirm the keys are gone
    assert(!Resque.redis.exists("delayed:#{timestamp.to_i}"))
    assert_equal(0, Resque.redis.zcard(:delayed_queue_schedule), "delayed queue should be empty")
  end

  def test_something_in_the_future_doesnt_come_out
    timestamp = Time.now + 600 # 10 minutes from now (in the future, shouldn't come out)

    assert_equal(0, Resque.redis.llen("delayed:#{timestamp.to_i}").to_i, "delayed queue should be empty to start")

    Resque.enqueue_at(timestamp, SomeIvarJob, "path")

    # Confirm the correct keys were added
    assert_equal(1, Resque.redis.llen("delayed:#{timestamp.to_i}").to_i, "delayed queue should have one entry now")
    assert_equal(1, Resque.redis.zcard(:delayed_queue_schedule), "The delayed_queue_schedule should have 1 entry now")

    read_timestamp = Resque.next_delayed_timestamp

    assert_nil(read_timestamp, "No timestamps should be ready for queueing")
  end

  def test_enqueue_at_and_enqueue_in_are_equivelent
    timestamp = Time.now + 60

    Resque.enqueue_at(timestamp, SomeIvarJob, "path")
    Resque.enqueue_in(timestamp - Time.now, SomeIvarJob, "path")

    assert_equal(1, Resque.redis.zcard(:delayed_queue_schedule), "should have one timestamp in the delayed queue")
    assert_equal(2, Resque.redis.llen("delayed:#{timestamp.to_i}"), "should have 2 items in the timestamp queue")
  end

  def test_delayed_queue_peek
    t = Time.now
    expected_timestamps = (1..5).to_a.map do |i|
      (t + 60 + i).to_i
    end

    expected_timestamps.each do |timestamp|
      Resque.delayed_push(timestamp, {:class => SomeIvarJob, :args => 'blah1'})
    end

    timestamps = Resque.delayed_queue_peek(2,3)

    assert_equal(expected_timestamps[2,3], timestamps)
  end

  def test_delayed_queue_schedule_size
    assert_equal(0, Resque.delayed_queue_schedule_size)
    Resque.enqueue_at(Time.now+60, SomeIvarJob)
    assert_equal(1, Resque.delayed_queue_schedule_size)
  end

  def test_delayed_timestamp_size
    t = Time.now + 60
    assert_equal(0, Resque.delayed_timestamp_size(t))
    Resque.enqueue_at(t, SomeIvarJob)
    assert_equal(1, Resque.delayed_timestamp_size(t))
    assert_equal(0, Resque.delayed_timestamp_size(t.to_i+1))
  end

  def test_delayed_timestamp_peek
    t = Time.now + 60
    assert_equal([], Resque.delayed_timestamp_peek(t, 0, 1), "make sure it's an empty array, not nil")
    Resque.enqueue_at(t, SomeIvarJob)
    assert_equal(1, Resque.delayed_timestamp_peek(t, 0, 1).length)
    Resque.enqueue_at(t, SomeIvarJob)
    assert_equal(1, Resque.delayed_timestamp_peek(t, 0, 1).length)
    assert_equal(2, Resque.delayed_timestamp_peek(t, 0, 3).length)

    assert_equal({'args' => [], 'class' => 'SomeIvarJob'}, Resque.delayed_timestamp_peek(t, 0, 1).first)
  end

end