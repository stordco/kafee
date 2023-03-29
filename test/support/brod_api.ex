defmodule Kafee.BrodApi do
  @moduledoc """
  Some useful functions for interacting with `:brod`.
  """

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  @doc """
  Creates a random atom to use as a `:brod_client` id.

  Note: this function uses `String.to_atom/1` and is unsafe for production
  workloads.
  """
  @spec generate_client_id :: atom()
  def generate_client_id do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom(Faker.Beer.name())
  end

  @doc """
  Starts a new `:brod_client`.
  """
  @spec client!(atom()) :: pid()
  def client!(brod_client_id) do
    start_supervised!(%{
      id: brod_client_id,
      start: {:brod_client, :start_link, [endpoints(), brod_client_id, client_config()]}
    })
  end

  @doc """
  Returns a list of client options to put into `:brod_client`.
  """
  @spec client_config() :: Keyword.t()
  def client_config do
    [
      auto_start_producers: true,
      query_api_version: false
    ]
  end

  defdelegate host(), to: Kafee.KafkaApi
  defdelegate port(), to: Kafee.KafkaApi
  defdelegate endpoints(), to: Kafee.KafkaApi
end
