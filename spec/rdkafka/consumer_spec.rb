require "spec_helper"

describe Rdkafka::Consumer do
  let(:config) { rdkafka_config }
  let(:consumer) { config.consumer }
  let(:producer) { config.producer }

  describe "#subscripe, #unsubscribe and #subscription" do
    it "should subscribe, unsubscribe and return the subscription" do
      expect(consumer.subscription).to be_empty

      consumer.subscribe("consume_test_topic")

      expect(consumer.subscription).not_to be_empty
      expected_subscription = Rdkafka::Consumer::TopicPartitionList.new.tap do |list|
        list.add_topic("consume_test_topic")
      end
      expect(consumer.subscription).to eq expected_subscription

      consumer.unsubscribe

      expect(consumer.subscription).to be_empty
    end

    it "should raise an error when subscribing fails" do
      expect(Rdkafka::Bindings).to receive(:rd_kafka_subscribe).and_return(20)

      expect {
        consumer.subscribe("consume_test_topic")
      }.to raise_error(Rdkafka::RdkafkaError)
    end

    it "should raise an error when unsubscribing fails" do
      expect(Rdkafka::Bindings).to receive(:rd_kafka_unsubscribe).and_return(20)

      expect {
        consumer.unsubscribe
      }.to raise_error(Rdkafka::RdkafkaError)
    end

    it "should raise an error when fetching the subscription fails" do
      expect(Rdkafka::Bindings).to receive(:rd_kafka_subscription).and_return(20)

      expect {
        consumer.subscription
      }.to raise_error(Rdkafka::RdkafkaError)
    end
  end

  context "#close" do
    it "should close a consumer" do
      consumer.subscribe("consume_test_topic")
      consumer.close
      expect(consumer.poll(100)).to be_nil
    end
  end

  describe "#commit and #committed" do
    before do
      # Make sure there's a stored offset
      report = producer.produce(
        topic:     "consume_test_topic",
        payload:   "payload 1",
        key:       "key 1",
        partition: 0
      ).wait
      # Wait for message commits the current state,
      # commit is therefore tested here.
      message = wait_for_message(
        topic: "consume_test_topic",
        delivery_report: report,
        config: config
      )
    end

    it "should only accept a topic partition list" do
      expect {
        consumer.committed("list")
      }.to raise_error TypeError
    end

    it "should raise an error when committing fails" do
      expect(Rdkafka::Bindings).to receive(:rd_kafka_commit).and_return(20)

      expect {
        consumer.commit
      }.to raise_error(Rdkafka::RdkafkaError)
    end

    it "should fetch the committed offsets for a specified topic partition list" do
      list = Rdkafka::Consumer::TopicPartitionList.new.tap do |list|
        list.add_topic("consume_test_topic", [0, 1, 2])
      end
      partitions = consumer.committed(list).to_h["consume_test_topic"]
      expect(partitions[0].offset).to be > 0
      expect(partitions[1].offset).to eq -1001
      expect(partitions[2].offset).to eq -1001
    end

    it "should raise an error when getting committed fails" do
      expect(Rdkafka::Bindings).to receive(:rd_kafka_committed).and_return(20)
      list = Rdkafka::Consumer::TopicPartitionList.new.tap do |list|
        list.add_topic("consume_test_topic", [0, 1, 2])
      end
      expect {
        consumer.committed(list)
      }.to raise_error Rdkafka::RdkafkaError
    end
  end

  describe "#query_watermark_offsets" do
    it "should return the watermark offsets" do
      # Make sure there's a message
      producer.produce(
        topic:     "consume_test_topic",
        payload:   "payload 1",
        key:       "key 1",
        partition: 0
      ).wait

      low, high = consumer.query_watermark_offsets("consume_test_topic", 0, 5000)
      expect(low).to eq 0
      expect(high).to be > 0
    end

    it "should raise an error when querying offsets fails" do
      expect(Rdkafka::Bindings).to receive(:rd_kafka_query_watermark_offsets).and_return(20)
      expect {
        consumer.query_watermark_offsets("consume_test_topic", 0, 5000)
      }.to raise_error Rdkafka::RdkafkaError
    end
  end

  describe "#lag" do
    let(:config) { rdkafka_config(:"enable.partition.eof" => true) }

    it "should calculate the consumer lag" do
      # Make sure there's a message in every partition and
      # wait for the message to make sure everything is committed.
      (0..2).each do |i|
        report = producer.produce(
          topic:     "consume_test_topic",
          key:       "key lag #{i}",
          partition: i
        ).wait
      end

      # Consume to the end
      consumer.subscribe("consume_test_topic")
      eof_count = 0
      loop do
        begin
          consumer.poll(100)
        rescue Rdkafka::RdkafkaError => error
          if error.is_partition_eof?
            eof_count += 1
          end
          break if eof_count == 3
        end
      end

      # Commit
      consumer.commit

      # Create list to fetch lag for. TODO creating the list will not be necessary
      # after committed uses the subscription.
      list = consumer.committed(Rdkafka::Consumer::TopicPartitionList.new.tap do |l|
        l.add_topic("consume_test_topic", (0..2))
      end)

      # Lag should be 0 now
      lag = consumer.lag(list)
      expected_lag = {
        "consume_test_topic" => {
          0 => 0,
          1 => 0,
          2 => 0
        }
      }
      expect(lag).to eq(expected_lag)

      # Produce message on every topic again
      (0..2).each do |i|
        report = producer.produce(
          topic:     "consume_test_topic",
          key:       "key lag #{i}",
          partition: i
        ).wait
      end

      # Lag should be 1 now
      lag = consumer.lag(list)
      expected_lag = {
        "consume_test_topic" => {
          0 => 1,
          1 => 1,
          2 => 1
        }
      }
      expect(lag).to eq(expected_lag)
    end
  end

  describe "#poll" do
    it "should return nil if there is no subscription" do
      expect(consumer.poll(1000)).to be_nil
    end

    it "should return nil if there are no messages" do
      consumer.subscribe("empty_test_topic")
      expect(consumer.poll(1000)).to be_nil
    end

    it "should return a message if there is one" do
      producer.produce(
        topic:     "consume_test_topic",
        payload:   "payload 1",
        key:       "key 1"
      ).wait

      consumer.subscribe("consume_test_topic")
      message = consumer.poll(5000)
      expect(message).to be_a Rdkafka::Consumer::Message

      # Message content is tested in producer spec
    end

    it "should raise an error when polling fails" do
      message = Rdkafka::Bindings::Message.new.tap do |message|
        message[:err] = 20
      end
      message_pointer = message.to_ptr
      expect(Rdkafka::Bindings).to receive(:rd_kafka_consumer_poll).and_return(message_pointer)
      expect(Rdkafka::Bindings).to receive(:rd_kafka_message_destroy).with(message_pointer)
      expect {
        consumer.poll(100)
      }.to raise_error Rdkafka::RdkafkaError
    end
  end

  describe "#each" do
    it "should yield messages" do
      10.times do
        producer.produce(
          topic:     "consume_test_topic",
          payload:   "payload 1",
          key:       "key 1",
          partition: 0
        ).wait
      end

      consumer.subscribe("consume_test_topic")
      count = 0
      # Check the first 10 messages
      consumer.each do |message|
        expect(message).to be_a Rdkafka::Consumer::Message
        count += 1
        break if count == 10
      end
    end
  end
end
