defmodule Kafee.SchemaRegistry.WireFormat do
  @moduledoc """
  Helper functions for dealing with the schema registry
  wire format.
  """

  @type t :: %{
          schema_id: integer(),
          data: binary()
        }

  @doc """
  Parses the magic bytes from the schema registry wire format and
  returns a struct of information.
  """
  @spec parse_magic_bytes(binary()) :: {:ok, t()} | {:error, any()}
  def parse_magic_bytes(<<0::size(8), id::size(32), body::binary>>) do
  end

  def parse_magic_bytes(_) do
    {:error, :invalid_magic_bytes}
  end
end
