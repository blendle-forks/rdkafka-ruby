module Rdkafka
  class Consumer
    # A list of topics with their partition information
    class TopicPartitionList
      # Create a new topic partition list.
      #
      # @param pointer [FFI::Pointer, nil] Optional pointer to an existing native list
      #
      # @return [TopicPartitionList]
      def initialize(pointer=nil)
        @tpl =
          Rdkafka::Bindings::TopicPartitionList.new(
            FFI::AutoPointer.new(
              pointer || Rdkafka::Bindings.rd_kafka_topic_partition_list_new(5),
              Rdkafka::Bindings.method(:rd_kafka_topic_partition_list_destroy)
            )
        )
      end

      # Number of items in the list
      # @return [Integer]
      def count
        @tpl[:cnt]
      end

      # Whether this list is empty
      # @return [Boolean]
      def empty?
        count == 0
      end

      # Add a topic with optionally partitions to the list.
      #
      # @example Add a topic with unassigned partitions
      #   tpl.add_topic("topic")
      #
      # @example Add a topic with assigned partitions
      #   tpl.add_topic("topic", (0..8))
      #
      # @example Add a topic with all topics up to a count
      #   tpl.add_topic("topic", 9)
      #
      # @param topic [String] The topic's name
      # @param partition [Array<Integer>, Range<Integer>, Integer] The topic's partitions or partition count
      #
      # @return [nil]
      def add_topic(topic, partitions=nil)
        if partitions.is_a? Integer
          partitions = (0..partitions - 1)
        end
        if partitions.nil?
          Rdkafka::Bindings.rd_kafka_topic_partition_list_add(
            @tpl,
            topic,
            -1
          )
        else
          partitions.each do |partition|
            Rdkafka::Bindings.rd_kafka_topic_partition_list_add(
              @tpl,
              topic,
              partition
            )
          end
        end
      end

      # Return a `Hash` with the topics as keys and and an array of partition information as the value if present.
      #
      # @return [Hash<String, [Array<Partition>, nil]>]
      def to_h
        {}.tap do |out|
          count.times do |i|
            ptr = @tpl[:elems] + (i * Rdkafka::Bindings::TopicPartition.size)
            elem = Rdkafka::Bindings::TopicPartition.new(ptr)
            if elem[:partition] == -1
              out[elem[:topic]] = nil
            else
              partitions = out[elem[:topic]] || []
              partition = Partition.new(elem[:partition], elem[:offset])
              partitions.push(partition)
              out[elem[:topic]] = partitions
            end
          end
        end
      end

      # Human readable representation of this list.
      # @return [String]
      def to_s
        "<TopicPartitionList: #{to_h}>"
      end

      def ==(other)
        self.to_h == other.to_h
      end

      # Return a copy of the internal native list
      # @private
      def copy_tpl
        Rdkafka::Bindings.rd_kafka_topic_partition_list_copy(@tpl)
      end
    end
  end
end
