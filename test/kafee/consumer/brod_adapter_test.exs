defmodule Kafee.Consumer.BrodAdapterTest do
  use ExUnit.Case, async: false

  alias Kafee.Consumer.BrodAdapter

  describe "init/1" do
    test "validates adapter options correctly" do
      consumer = TestConsumer

      # Valid options with adapter-specific config
      valid_options = [
        adapter:
          {BrodAdapter,
           [
             connect_timeout: 5000,
             max_retries: 5,
             retry_backoff_ms: 200
           ]},
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group"
      ]

      assert {:ok, {_supervisor_flags, children}} = BrodAdapter.init({consumer, valid_options})
      assert length(children) == 2
    end

    test "uses default options when not specified" do
      consumer = TestConsumer

      options = [
        adapter: BrodAdapter,
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group"
      ]

      # Should initialize with default options
      assert {:ok, {_supervisor_flags, children}} = BrodAdapter.init({consumer, options})
      assert length(children) == 2
    end

    test "handles invalid adapter options" do
      consumer = TestConsumer

      invalid_options = [
        adapter:
          {BrodAdapter,
           [
             connect_timeout: "not a number"
           ]},
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group"
      ]

      assert {:error, %NimbleOptions.ValidationError{}} =
               BrodAdapter.init({consumer, invalid_options})
    end
  end

  describe "child_spec/1" do
    test "generates correct child spec" do
      consumer = TestConsumer

      options = [
        adapter: BrodAdapter,
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group"
      ]

      spec = BrodAdapter.child_spec({consumer, options})

      assert spec.id == BrodAdapter
      assert spec.start == {BrodAdapter, :start_link, [{consumer, options}]}
      assert spec.type == :supervisor
    end
  end

  describe "supervisor init" do
    test "initializes supervisor with correct children" do
      consumer = TestConsumer

      options = [
        adapter: BrodAdapter,
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group"
      ]

      assert {:ok, {supervisor_flags, children}} = BrodAdapter.init({consumer, options})

      # Supervisor uses a map format
      assert supervisor_flags == %{
               strategy: :one_for_one,
               intensity: 3,
               period: 5,
               auto_shutdown: :never
             }

      assert length(children) == 2

      # Check brod client child
      [brod_client, subscriber] = children
      assert brod_client.id == TestConsumer.BrodClient
      assert brod_client.restart == :permanent
      assert brod_client.shutdown == 500

      # Check subscriber child
      assert subscriber.id == consumer
      assert subscriber.restart == :permanent
      assert subscriber.shutdown == :infinity
    end

    test "configures SSL when enabled" do
      consumer = TestConsumer

      options = [
        adapter: BrodAdapter,
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group",
        ssl: true
      ]

      {:ok, {_, [brod_client | _]}} = BrodAdapter.init({consumer, options})

      # Extract client config from start args
      {_, _, [_, _, client_config]} = brod_client.start
      assert Keyword.get(client_config, :ssl) == true
    end

    test "configures SASL authentication" do
      consumer = TestConsumer
      sasl_config = {:plain, "username", "password"}

      options = [
        adapter: BrodAdapter,
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group",
        sasl: sasl_config
      ]

      {:ok, {_, [brod_client | _]}} = BrodAdapter.init({consumer, options})

      {_, _, [_, _, client_config]} = brod_client.start
      assert Keyword.get(client_config, :sasl) == sasl_config
    end

    test "passes adapter-specific options to client config" do
      consumer = TestConsumer

      options = [
        adapter:
          {BrodAdapter,
           [
             connect_timeout: 20_000,
             max_retries: 10,
             retry_backoff_ms: 500
           ]},
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group"
      ]

      {:ok, {_, [brod_client | _]}} = BrodAdapter.init({consumer, options})

      {_, _, [_, _, client_config]} = brod_client.start
      assert Keyword.get(client_config, :connect_timeout) == 20_000
      assert Keyword.get(client_config, :max_retries) == 10
      assert Keyword.get(client_config, :retry_backoff_ms) == 500
    end

    test "filters out nil values from client config" do
      consumer = TestConsumer

      options = [
        adapter: BrodAdapter,
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group",
        ssl: nil,
        sasl: nil
      ]

      {:ok, {_, [brod_client | _]}} = BrodAdapter.init({consumer, options})

      {_, _, [_, _, client_config]} = brod_client.start
      refute Keyword.has_key?(client_config, :ssl)
      refute Keyword.has_key?(client_config, :sasl)
    end

    test "subscriber configuration uses correct parameters" do
      consumer = TestConsumer

      options = [
        adapter: BrodAdapter,
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-consumer-group"
      ]

      {:ok, {_, [_, subscriber]}} = BrodAdapter.init({consumer, options})

      # Extract subscriber config
      {_, _, [subscriber_config]} = subscriber.start

      assert subscriber_config.client == TestConsumer.BrodClient
      assert subscriber_config.group_id == "test-consumer-group"
      assert subscriber_config.topics == ["test-topic"]
      assert subscriber_config.cb_module == Kafee.Consumer.BrodWorker
      assert subscriber_config.message_type == :message
      assert subscriber_config.init_data.consumer == consumer
      assert subscriber_config.init_data.options == options
      assert is_list(subscriber_config.init_data.adapter_options)
    end

    test "subscriber uses BrodWorker with explicit single_message mode" do
      consumer = TestConsumer

      options = [
        adapter: {BrodAdapter, mode: :single_message},
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-consumer-group"
      ]

      {:ok, {_, [_, subscriber]}} = BrodAdapter.init({consumer, options})

      # Extract subscriber config
      {_, _, [subscriber_config]} = subscriber.start

      assert subscriber_config.cb_module == Kafee.Consumer.BrodWorker
      assert subscriber_config.message_type == :message
      assert subscriber_config.init_data.adapter_options[:mode] == :single_message
    end

    test "subscriber uses BrodBatchWorker and message_set when mode is :batch" do
      consumer = TestConsumer

      options = [
        adapter:
          {BrodAdapter,
           [
             mode: :batch,
             batch: [size: 100]
           ]},
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-consumer-group"
      ]

      {:ok, {_, [_, subscriber]}} = BrodAdapter.init({consumer, options})

      # Extract subscriber config
      {_, _, [subscriber_config]} = subscriber.start

      assert subscriber_config.cb_module == Kafee.Consumer.BrodBatchWorker
      assert subscriber_config.message_type == :message_set
      assert subscriber_config.init_data.adapter_options[:batch_size] == 100
    end

    test "validates batch configuration options - new style" do
      consumer = TestConsumer

      valid_batch_options = [
        adapter:
          {BrodAdapter,
           [
             mode: :batch,
             batch: [size: 500, timeout: 2000, max_bytes: 5_000_000],
             processing: [async: true, max_concurrency: 20, max_in_flight_batches: 5],
             acknowledgment: [
               strategy: :best_effort,
               dead_letter_topic: "dead-letter-queue",
               dead_letter_max_retries: 5
             ]
           ]},
        host: "localhost",
        port: 9092,
        topic: "test-topic",
        consumer_group_id: "test-group"
      ]

      assert {:ok, {_, children}} = BrodAdapter.init({consumer, valid_batch_options})
      assert length(children) == 2
    end
  end

  # Module to use for testing
  defmodule TestConsumer do
    use Kafee.Consumer

    def handle_message(_message), do: :ok
  end
end
