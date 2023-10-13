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
          adapter: Kafee.Producer.TestAdapter,
          encoder: Kafee.JasonEncoderDecoder

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

  alias Kafee.Producer.Message

  @doc false
  @impl Kafee.Producer.Adapter
  def start_link(_producer, _options), do: :ignore

  @doc """
  Always returns a static `[0]` value for partitioning during
  tests.
  """
  @impl Kafee.Producer.Adapter
  @spec partitions(module(), Kafee.Producer.options()) :: [Kafee.partition()]
  def partitions(_producer, _options), do: [0]

  @doc """
  Adds messages to the internal memory.
  """
  @impl Kafee.Producer.Adapter
  @spec produce([Message.t()], module(), Kafee.Producer.options()) :: :ok | {:error, term()}
  def produce(messages, producer, options) do
    pid = Application.get_env(:kafee, :test_process, self())

    for message <- messages do
      new_message =
        message
        |> Message.set_module_values(producer, options)
        |> Message.encode(producer, options)
        |> Message.partition(producer, options)
        |> Message.set_request_id_from_logger()
        |> Message.validate!()

      decoded_message_value =
        case Keyword.get(options, :encoder, nil) do
          nil -> new_message.value
          encoder when is_atom(encoder) -> encoder.decode!(new_message.value, [])
          {encoder, encoder_options} -> encoder.decode!(new_message.value, encoder_options)
        end

      send(pid, {:kafee_message, %{new_message | value: decoded_message_value}})
    end

    :ok
  end
end
