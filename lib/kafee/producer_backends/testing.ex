defmodule Kafee.TestingProducerBackend do
  @moduledoc """
  A `Kafee.ProducerBackend` that sends the Kafka message to the
  process mailbox. This allows for easy testing with `ExUnit`.

  ## Setup

  First, you will need to set your producer's backend to this module. This
  can be done with:

      defmodule MyApp.MyProducer do
        use Kafee.Producer,
          producer_backend: Kafee.TestingProducerBackend
      end

  We recommend doing this dynamically in your configuration file so it only
  applies when running tests. You can do this via by adding these lines
  into your configuration files:

      # config.exs
      config :my_app,
        producer_backend: Kafee.SyncProducerBackend

      # test.exs
      config :my_app,
        producer_backend: Kafee.TestingProducerBackend

  and then grabbing this configuration in your module like so:

      defmodule MyApp.MyProducer do
        use Kafee.Producer,
          producer_backend: System.compile_env(:my_app, :producer_backend)
      end

  ## Usage

  Once you have setup this backend, any message produced in your application
  will be sent to your process mailbox. You can then use the
  `Kafee.TestAssertions` module functions to assert a message was sent in your
  application code.
  """

  use GenServer

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def init(_opts), do: {:ok, nil}

  @doc false
  def handle_call({:produce_messages, topic, messages}, _from, state) do
    for message <- messages do
      for pid <- pids() do
        Process.send(pid, {:kafee_message, topic, message}, [])
      end
    end

    {:reply, :ok, state}
  end

  defp pids do
    :"$ancestors"
    |> Process.get()
    |> List.wrap()
    |> Enum.drop(2)
    |> Enum.uniq()
  end
end
