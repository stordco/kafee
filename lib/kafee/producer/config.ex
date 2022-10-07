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

  @enforce_keys [:producer]

  defstruct [
    # Reference data. I wish I knew a better way to do this because it seems
    # messy, but I guess it works.
    producer: nil,

    # Brod client connection details
    hostname: "localhost",
    port: 9092,
    endpoints: [],

    # Authentication options
    password: nil,

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
          hostname: :brod.hostname(),
          port: :brod.portnum(),
          endpoints: list(:brod.endpoint()),
          password: binary() | nil,
          brod_client_opts: :brod.client_config(),
          brod_producer_opts: :brod.producer_config(),
          kafee_async_worker_opts: Keyword.t()
        }

  @doc """
  Creates a new `Kafee.Producer.Config` struct from the given
  `Keyword` list.

  ## Examples

      iex> new(producer: MyProducer)
      %Config{producer: MyProducer}

  """
  @spec new(Keyword.t()) :: t()
  def new(list) do
    struct(__MODULE__, list)
  end

  @doc """
  Creates a new `Kafee.Producer.Config` struct from the two given
  `Keyword` lists, overwriting any keys given in `left` with
  the keys given in `right`.

  ## Examples

      iex> new([producer: MyProducer], [port: 1234])
      %Config{producer: MyProducer, port: 1234}

      iex> new([producer: MyProducer], [producer: MyNewProducer])
      %Config{producer: MyNewProducer}

  """
  @spec new(Keyword.t(), Keyword.t()) :: t()
  def new(left, right) do
    struct(__MODULE__, Keyword.merge(left, right))
  end

  @doc """
  Generates a list of `:brod.endpoint()`s to be used when creating a new
  `:brod_client`.

  This function will first use the given `endpoints` field. If that field is
  not set, we fall back to generating one via the `hostname` and `port`
  fields.

  ## Examples

      iex> brod_endpoints(%Config{producer: MyProducer, hostname: "kafka", port: 1234})
      [{"kafka", 1234}]

      iex> brod_endpoints(%Config{producer: MyProducer, endpoints: [{"host1", 1234}, {"host2", 1234}]})
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

      iex> brod_client_config(%Config{producer: MyProducer})
      [auto_start_producers: true]

      iex> brod_client_config(%Config{producer: MyProducer, brod_client_opts: [query_api_version: false]})
      [auto_start_producers: true, query_api_version: false]

  """
  @spec brod_client_config(t()) :: :brod.client_config()
  def brod_client_config(%__MODULE__{} = config) do
    Keyword.put(config.brod_client_opts, :auto_start_producers, true)
  end
end
