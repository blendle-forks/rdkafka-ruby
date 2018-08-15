require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
end

require "pry"
require "rspec"
require "rdkafka"

def rdkafka_config(config_overrides={})
  config = {
    :"bootstrap.servers" => "localhost:9092",
    :"group.id" => "ruby-test-#{Random.new.rand(0..1_000_000)}",
    :"auto.offset.reset" => "earliest",
    :"enable.partition.eof" => false
  }
  if ENV["DEBUG_PRODUCER"]
    config[:debug] = "broker,topic,msg"
  elsif ENV["DEBUG_CONSUMER"]
    config[:debug] = "cgrp,topic,fetch"
  end
  config.merge!(config_overrides)
  Rdkafka::Config.new(config)
end

def native_client
  config = rdkafka_config
  config.send(:native_kafka, config.send(:native_config), :rd_kafka_producer)
end

def new_native_topic(topic_name="topic_name")
  Rdkafka::Bindings.rd_kafka_topic_new(
    native_client,
    topic_name,
    nil
  )
end

def wait_for_message(topic:, delivery_report:, timeout_in_seconds: 30, config: nil)
  config = rdkafka_config if config.nil?
  consumer = config.consumer
  consumer.subscribe(topic)
  timeout = Time.now.to_i + timeout_in_seconds
  loop do
    if timeout <= Time.now.to_i
      raise "Timeout of #{timeout_in_seconds} seconds reached in wait_for_message"
    end
    message = consumer.poll(100)
    if message &&
        message.partition == delivery_report.partition &&
        message.offset == delivery_report.offset
      return message
    end
  end
ensure
  consumer.commit
  consumer.close
end

def wait_for_assignment(consumer)
  10.times do
    break if !consumer.assignment.empty?
    sleep 1
  end
end
