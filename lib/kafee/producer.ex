defmodule Kafee.Producer do
  @moduledoc """
  A module based Kafka producer with pluggable backends allowing for
  asynchronous, synchronous, and no-op sending of messages to Kafka.

  ## Configuration Options



  ## Configuration Loading

  Every `Kafee.Producer` can load configuration from three different places
  (in order):

  - The application configuration with `config :kafee, :producer, []`
  - The module options with `use Kafee.Producer`
  - The init options with `{MyProducer, []}`
  """

  @doc false
  def __using__(module_opts \\ []) do
    quote do
      use Supervisor

      @doc false
      @impl true
      def init(init_opts \\ []) do
        config =
          [producer: __MODULE__]
          |> Kafee.Producer.Config.new()
          |> Kafee.Producer.Config.merge(Application.get_env(:kafee, :producer, []))
          |> Kafee.Producer.Config.merge(unquote(module_opts))
          |> Kafee.Producer.Config.merge(init_opts)
          |> Kafee.Producer.Config.validate!()

        children = [
          {config.producer_backend, config}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      @doc """
      Starts a new `Kafee.Producer` process and associated children.
      """
      @spec start_link(Keyword.t()) :: Supervisor.on_start()
      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end
    end
  end

  @doc """
  Produces a list of messages depending on the configuration set
  in the producer.

  ## Examples

      iex> produce(MyProducer, [message])
      :ok

  """
  @spec produce(atom(), [map()]) :: :ok | {:error, term()}
  def produce(producer, messages) do
  end
end
