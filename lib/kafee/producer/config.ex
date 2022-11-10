defmodule Kafee.Producer.Config do
  @moduledoc """
  A simple struct for options able to be given to a `Kafee.Producer`.

  ## Endpoints

  When creating a `Kafee.Producer`, you can simply specify the `hostname`
  and `port` options. If you want multiple endpoints, you can set the
  `endpoints` option similar to how you would in `:brod`. If you are only
  connecting to a single endpoint, these two specifications are the same.
  See the `brod_endpoints/1` function for more details.
  """

  use Agent

  defstruct [
    # Reference data
    producer: nil,
    producer_backend: nil,
    brod_client_id: nil,

    # Brod client connection details
    hostname: "localhost",
    port: 9092,
    endpoints: [],

    # Authentication options
    username: nil,
    password: nil,
    ssl: false,
    sasl: false,

    # Useful extras to clean up your code
    topic: nil,
    partition_fun: :hash,

    # Extra brod options
    brod_client_opts: [],
    brod_producer_opts: [],

    # Extra Kafee options
    kafee_async_worker_opts: []
  ]

  @typedoc """
  All configuration that can be given to a `Kafee.Producer`.
  """
  @type t :: %__MODULE__{
          producer: atom(),
          producer_backend: atom(),
          brod_client_id: atom() | nil,
          hostname: :brod.hostname(),
          port: :brod.portnum(),
          endpoints: list(:brod.endpoint()),
          username: binary() | nil,
          password: binary() | nil,
          ssl: boolean(),
          sasl: atom() | false,
          topic: :brod.topic() | nil,
          partition_fun: :brod.partitioner(),
          brod_client_opts: :brod.client_config(),
          brod_producer_opts: :brod.producer_config(),
          kafee_async_worker_opts: Keyword.t()
        }

  @doc """
  Starts a new `Kafee.Producer.Config` process.
  """
  @spec start_link(t()) :: {:ok, pid()}
  def start_link(%__MODULE__{} = config) do
    Agent.start_link(fn -> config end, name: process_name(config.producer))
  end

  @doc """
  Returns the `Kafee.Producer.Config` for a given `Kafee.Producer`.

  ## Examples

      iex> config = %Config{producer: MyProducer}
      ...> {:ok, _pid} = Config.start_link(config)
      ...> Config.get(MyProducer)
      %Config{producer: MyProducer}

  """
  @spec get(atom()) :: t()
  def get(producer) do
    producer
    |> process_name()
    |> Agent.get(& &1)
  end

  @doc """
  Creates a new `Kafee.Producer.Config` struct from the given
  `Keyword` list.

  ## Examples

      iex> new(producer: MyProducer)
      %Config{producer: MyProducer}

  """
  @spec new(Keyword.t()) :: t()
  def new(opts) do
    struct(__MODULE__, opts)
  end

  @doc """
  Merges new given configuration values with the existing configuration
  given.

  ## Examples

      iex> merge(%Config{producer: MyProducer}, port: 1234)
      %Config{producer: MyProducer, port: 1234}

      iex> merge(%Config{producer: MyProducer}, producer: MyNewProducer)
      %Config{producer: MyNewProducer}

  """
  @spec merge(t(), Keyword.t()) :: t()
  def merge(%__MODULE__{} = config, opts \\ []) do
    new_values =
      config
      |> Map.delete(:__struct__)
      |> Map.to_list()
      |> Keyword.merge(opts)

    struct(__MODULE__, new_values)
  end

  @doc """
  Runs validation on the given configuration. This catches some basic
  errors before even passing it to a lower level library.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    with {:error, _} <- Code.ensure_compiled(config.producer) do
      raise ArgumentError,
        message: """
        Kafee Producer configuration does not specify a valid producer module.
        Usually this indicates some broken library code.

        Received:
        #{inspect(config.producer)}
        """
    end

    with {:error, _} <- Code.ensure_compiled(config.producer_backend) do
      raise ArgumentError,
        message: """
        The Kafee Producer backend is unavailable or not loaded. Usually this
        means a simple misspelling. Aside from custom backends, these are the
        backends currently available:

        - `Kafee.Producer.AsyncBackend`
        - `Kafee.Producer.SyncBackend`
        - `Kafee.Producer.TestBackend`

        Received:
        #{inspect(config.producer_backend)}
        """
    end

    if is_nil(config.hostname) do
      raise ArgumentError,
        message: """
        The Kafee Producer received a hostname of nil. By default Kafee will
        use "localhost", so you are most likely overriding this with a nil
        configuration value. Please ensure that the `hostname` is set to a valid
        hostname, or unset it.
        """
    end

    if not Keyword.get(config.brod_client_opts, :auto_start_producers, true) do
      raise ArgumentError,
        message: """
        It looks like you are specificity setting the `auto_start_producers`
        option for your `Kafee.Producer`. This is unsupported and will break
        how `Kafee.Producer.AsyncBackend` sends message. Please remove this
        option.
        """
    end

    config
  end

  @doc """
  Generates a list of `:brod.endpoint()`s to be used when creating a new
  `:brod_client`.

  This function will first use the given `endpoints` field. If that field is
  not set, we fall back to generating one via the `hostname` and `port`
  fields.

  ## Examples

      iex> brod_endpoints(%Config{hostname: "kafka", port: 1234})
      [{"kafka", 1234}]

      iex> brod_endpoints(%Config{endpoints: [{"host1", 1234}, {"host2", 1234}]})
      [{"host1", 1234}, {"host2", 1234}]

  """
  @spec brod_endpoints(t()) :: list(:brod.endpoint())
  def brod_endpoints(%__MODULE__{endpoints: []} = config) do
    [{config.hostname, config.port}]
  end

  def brod_endpoints(%__MODULE__{endpoints: endpoints}), do: endpoints

  @doc """
  Generates options to pass into `:brod` when creating the client. Note,
  this will set some sane defaults unless you manually override them. See
  the [`:brod` documentation](https://hexdocs.pm/brod/readme.html#start-brod-client-on-demand)
  for more information.

  ## Examples

      iex> brod_client_config(%Config{ssl: false})
      [connect_timeout: 10000, auto_start_producers: true, ssl: false]

      iex> brod_client_config(%Config{ssl: false, brod_client_opts: [query_api_version: false]})
      [connect_timeout: 10000, auto_start_producers: true, ssl: false, query_api_version: false]

  """
  @spec brod_client_config(t()) :: :brod.client_config()
  def brod_client_config(%__MODULE__{} = config) do
    config.brod_client_opts
    |> Keyword.put(:ssl, config.ssl)
    |> Keyword.put(:auto_start_producers, true)
    # This matches how Elsa connects and is required for our Confluent cloud connection.
    |> Keyword.put_new(:connect_timeout, :timer.seconds(10))
    |> maybe_put_producer_backend_config(config.producer_backend)
    |> maybe_put_sasl(config)
    |> :brod_utils.init_sasl_opt()
  end

  defp maybe_put_producer_backend_config(opts, Kafee.Producer.SyncBackend) do
    # We are noticing that the brod client is having troubles when our Confluent cloud
    # restarts nodes. We set this configuration for the sync backend to help provide some
    # resilience here. It matches what the official Java client does (even if we don't fully
    # agree.) We _do not_ set this for the async backend as it will just keep retrying til
    # success.
    opts
    |> Keyword.put_new(:max_retries, -1)
    |> Keyword.put_new(:retry_backoff_ms, 100)
  end

  defp maybe_put_producer_backend_config(opts, _backend), do: opts

  defp maybe_put_sasl(opts, %{sasl: false}), do: opts

  defp maybe_put_sasl(opts, %{username: username, password: password, sasl: sasl}),
    do: Keyword.put(opts, :sasl, {sasl, username, password})

  @doc """
  Creates a `Kafee.Producer.Config` process atom name.

  ## Examples

      iex> process_name(MyProducer)
      MyProducer.Config

  """
  @spec process_name(atom()) :: Supervisor.name()
  def process_name(producer) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(producer, Config)
  end
end
