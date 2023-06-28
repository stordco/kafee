defmodule Kafee.SchemaRegistry.Registry do
  @moduledoc """
  Access the Confluent Schema Registry.
  """

  use Nebulex.Caching

  alias Kafee.SchemaRegistry.Cache

  @ttl :timer.hours(1)

  @headers [
    {"accept", "application/vnd.schemaregistry+json"},
    {"content-type", "application/vnd.schemaregistry+json"}
  ]

  @doc """
  Lists all subjects in the schema registry.
  """
  @decorate cacheable(cache: Cache, key: :subjects, opts: [ttl: @ttl])
  @spec get_subjects() :: {:ok, Req.Response.t()} | {:error, any()}
  def get_subjects() do
    get(["/subjects"])
  end

  @doc """
  Lists all versions of a subject in the schema registry.
  """
  @decorate cacheable(cache: Cache, key: {:versions, subject}, opts: [ttl: @ttl])
  @spec get_versions(String.t()) :: {:ok, Req.Response.t()} | {:error, any()}
  def get_versions(subject) do
    get([subject, "versions"])
  end

  @doc """
  Grabs information about a subject and version.
  """
  @decorate cacheable(cache: Cache, key: {:version, subject, version}, opts: [ttl: @ttl])
  @spec get_version(String.t(), String.t()) :: {:ok, Req.Response.t()} | {:error, any()}
  def get_version(subject, version) do
    get([subject, "versions", version])
  end

  @doc """
  Grabs information about a subject and the latest version in
  the schema registry.
  """
  @decorate cacheable(cache: Cache, key: {:latest, subject}, opts: [ttl: @ttl])
  @spec get_latest(String.t()) :: {:ok, Req.Response.t()} | {:error, any()}
  def get_latest(subject) do
    with {:ok, versions} <- get_versions(subject) do
      [latest | _] = Enum.reverse(versions.data)
      get_version(subject, latest)
    end
  end

  @doc """
  Grabs the latest schema id for a subject.
  """
  @decorate cacheable(cache: Cache, key: {:latest_id, subject}, opts: [ttl: @ttl])
  @spec get_latest_id(String.t()) :: {:ok, String.t()} | {:error, any()}
  def get_latest_id(subject) do
    with {:ok, response} <- get_latest(subject) do
      response.data["id"]
    end
  end

  @spec get([String.t()]) :: {:ok, Req.Response.t()} | {:error, any()}
  defp get(paths) do
    [
      auth: build_auth(),
      headers: @headers,
      receive_timeout: 5_000,
      url: build_path(paths)
    ]
    |> Req.new()
    |> Req.get()
  end

  @spec build_auth() :: {String.t(), String.t()} | nil
  defp build_auth() do
    with nil <- config(:username),
         nil <- config(:password) do
      nil
    else
      _ -> {config(:username), config(:password)}
    end
  end

  @spec build_path([String.t()]) :: String.t()
  defp build_path(paths) do
    ([config(:url)] ++ paths)
    |> Path.join()
  end

  @spec config(atom(), value) :: value when value: any()
  defp config(key, default \\ nil) do
    :kafee
    |> Application.get_env(:schema_registry, [])
    |> Keyword.get(key, default)
  end
end
