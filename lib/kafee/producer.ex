defmodule Kafee.Producer do
  @moduledoc """
  A module that produces Kafka messages. Under the hood, it can use different
  sending mechanics. This allows for easy testing of message producing in
  your application without the need of `Mox` or other mocking libraries.

  ## Usage

  This is the most basic example. In most cases, this should give you a great
  start at sending Kafka messages.

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {MyApp.MyProducer, [
              host: "localhost",
              port: 9092,
              username: "user",
              password: "pass",
              ssl: true
            ]}
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

      defmodule MyApp.MyProducer do
        use Kafee.Producer,
          topic: "testing"
      end

      iex> MyApp.MyProducer.produce(%Kafee.Message{value: "message value"})

  But what if you want to be a little more organized? This can be done by
  adding some function heads in your producer.

      defmodule MyApp.MyProducer do
        use Kafee.Producer,
          topic: "testing"

        def publish(:record_added, %MyApp.DatabaseRecord{} = record) do
          produce(%Kafee.Message{
            key: "record_added",
            value: JASON.encode!(record)
          })
        end
      end

      iex> MyApp.MyProducer.publisH(:record_added, new_database_record)

  By adding a simple function head, you can now keep your Kafka logic and
  application logic organized and trust that the producer logic will do all of
  the encoding and message wrapping you need. Obviously this isn't the only
  way to organize your code, but it gives a good starting point on
  recommended practice.

  ### Dynamic Topics

  Some applications make use of dynamic Kafka topics and can't possibly
  make a module for every one. To handle this use case, you can pass
  an optional `topic` option when producing a message. When producing
  the message, the option topic will always take priority.

        MyApp.MyProducer.produce(%Kafee.Message{}, topic: "unique")

  Note that while this is allowed, it's recommended to set the topic on
  the module to start the connection pool on application startup. This will
  give you a performance boost on initial posting.

  ### Encoding Messages

  By the time a message gets passed to the provider backend, it will
  need to be in the form of a `%Kafee.message()`. This can be done in
  application code, but more than likely you will want to standardize
  it in this module. To do this, you can override the `prepare/3`
  function. This will allow you to modify any message before sending
  it to the provider backend.

  For example, if you need to JSON encode your message before sending,
  you can do something like this:

        defmodule MyApp.MyProducer do
          use Kafee.Producer,
            topic: "test-topic"

          def publish(:order_created, order) do
            produce(%{
              order_id: order.id,
              timestamp: order.created_at
            })
          end

          def publish(:order_fulfilled, order) do
            produce(%{
              order_id: order.id,
              timestamp: order.fulfilled_at
            })
          end

          def prepare(topic, order_message, opts) do
            %Kafee.Message{
              key: order_message.order_id,
              value: Jason.encode!(order_message)
            }
          end
        end

  You can also use this logic to simplify your use of Protobuf messages
  like this:

        defmodule MyApp.MyProducer do
          use Kafee.Producer,
            topic: "test-topic"

          def publish(:order_created, order) do
            [order_id: order.id, timestamp: order.created_at]
            |> MyProtobuf.OrderCreated.new!()
            |> produce()
          end

          def publish(:order_fulfilled, order) do
            [order_id: order.id, timestamp: order.created_at]
            |> MyProtobuf.OrderFulfilled.new!()
            |> produce()
          end

          def prepare(topic, order_message, opts) do
            %Kafee.Message{
              key: order_message.order_id,
              value: Protobuf.encode_to_iodata(order_message)
            }
          end
        end

  ## Testing

  This module accepts a `producer_backend` option to change how Kafka
  messages are sent. When you are in a testing environment, you can
  switch this out with `Kafee.TestingProducerBackend` which will send
  messages to the process inbox. This allows `ExUnit` tests to
  assert a message was sent without ever touching Kafka. See the
  `Kafee.TestAssertions` module for example usage.
  """

  defmacro __using__(opts \\ []) do
    quote do
      @opts unquote(opts)
      @topic Keyword.get(@opts, :topic, nil)
      @producer_backend_module Keyword.get(@opts, :producer_backend, Kafee.SyncProducerBackend)

      use Supervisor

      @doc false
      @init Supervisor
      def start_link(connection_opts \\ []) do
        Supervisor.start_link(__MODULE__, connection_opts, name: __MODULE__)
      end

      @doc false
      @impl Supervisor
      def init(connection_opts \\ []) do
        module_opts =
          @opts
          |> Keyword.merge(connection_opts)
          |> Keyword.put(:brod_client, __MODULE__)
          |> Keyword.drop([:producer_backend])

        children = [
          {@producer_backend_module, module_opts}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      @doc """
      Passes a message to `prepare/3` before sending it to the producer backend
      module. By default this will use the configured topic set with
      `use Kafee.Producer`, however you can override this by setting the `topic`
      option.
      """
      @spec produce(any(), keyword()) :: :ok | {:error, term}
      def produce(message, opts \\ [])

      def produce(messages, opts) when is_list(messages) do
        {topic, opts} = Keyword.pop(opts, :topic, @topic)
        messages = Enum.map(messages, fn message -> prepare(topic, message, opts) end)
        GenServer.call(producer_backend_pid(), {:produce_messages, topic, messages})
      end

      def produce(message, opts) do
        {topic, opts} = Keyword.pop(opts, :topic, @topic)
        message = prepare(topic, message, opts)
        GenServer.call(producer_backend_pid(), {:produce_messages, topic, [message]})
      end

      @doc """
      Prepares a message to be sent via the configured producer backend. This
      is a great place to make any last minute adjustments, add common headers,
      and encode data (via Jason or Protobuf.)
      """
      @spec prepare(Kafee.topic(), any(), keyword()) :: Kafee.Message.t()
      def prepare(_topic, any, _opts), do: any

      defoverridable prepare: 3

      defp producer_backend_pid do
        with [{_, pid, _, _}] <- Supervisor.which_children(__MODULE__) do
          pid
        end
      end
    end
  end
end
