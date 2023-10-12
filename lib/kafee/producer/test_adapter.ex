defmodule Kafee.Producer.TestAdapter do
  @moduledoc """
  This is a `Kafee.Producer.Adapter` used for in local ExUnit
  tests. It takes all messages and sends them to the testing
  pid for use by the `Kafee.Test` module.

  ### Automatic decoding

  If you are using OTP 26+ you have probably noticed that map key
  order is no longer sorted. This means if you take a standard text
  compare for JSON encoded data, it will probably fail.

  To deal with this, the `Kafee.Producer.TestAdapter` will automatically
  use the `encoder_decoder` module set to decode data before sending
  it to the test process. This means you will be able to assert keys
  in the message value without issue. For example, if you have a producer
  module setup with the JSON encoder decoder module like so:

      defmodule MyProducer do
        use Kafee.Producer,
          encoder_decoder: Kafee.JasonEncoderDecoder,
          producer_adapter: Kafee.Producer.TestAdapter

        def publish(:order_created, %Order{} = order)
          produce(%Kafee.Producer.Message{
            key: order.tenant_id,
            value: order,
            topic: "order-created"
          })
        end
      end

  You'll be able to assert order keys in your test like this:

      test "order id is passed in to test" do
        order = %Order{id: "test"}
        publish(:order_created, order)
        assert_kafee_message(%{value: %{"id" => "test"}})
      end

  Note that because the value is JSON encoded and then decoded
  without the `keys` option set to `atoms`, the resulting value
  map has string keys.
  """

  @behaviour Kafee.Producer.Adapter

  @doc false
  @impl Kafee.Producer.Adapter
  def child_spec([_config]), do: nil

  @doc """
  This will always return 0 as the partition.
  """
  @impl Kafee.Producer.Adapter
  def partition(_config, message) do
    partition_fun = :brod_utils.make_part_fun(message.partition_fun)
    partition_fun.(message.topic, 1, message.key, message.value)
  end

  @doc """
  Adds messages to the internal memory.
  """
  @impl Kafee.Producer.Adapter
  def produce(
        %Kafee.Producer.Config{
          encoder_decoder: mod,
          encoder_decoder_options: opts,
          test_process: pid
        },
        messages
      ) do
    for message <- messages do
      send(pid, {:kafee_message, %{message | value: mod.decode!(message.value, opts)}})
    end

    :ok
  end
end
