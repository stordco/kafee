defmodule Kafee.Telemetry.DataStreams.Propagator do
  @moduledoc """
  Handles propagating `Kafee.Telemetry.DataStreams.Pathway` via encoding and
  adding to message headers.
  """

  import Protobuf.Wire.Varint

  alias Kafee.Telemetry.DataStreams.Pathway

  @propagation_key "dd-pathway-ctx"

  @doc """
  Returns the well known header key for propagating encoded pathway data
  """
  @spec propagation_key() :: String.t()
  def propagation_key, do: @propagation_key

  @doc """
  Encodes a pathway to a string able to be placed in a header.

  ## Examples

      iex> %Pathway{hash: 17210443572488294574, pathway_start: 1677632342000000000, edge_start: 1677632342000000000}
      ...> |> encode()
      ...> |> Base.encode64()
      "rtARjT7H1+7gn/Cq02Hgn/Cq02E="

      iex> %Pathway{hash: 2003974475228685984, pathway_start: 1677628446000000000, edge_start: 1677628446000000000}
      ...> |> encode()
      ...> |> Base.encode64()
      "oKb07iqMzxvg1JSn02Hg1JSn02E="

  """
  @spec encode(Pathway.t()) :: String.t()
  def encode(pathway) do
    :binary.encode_unsigned(pathway.hash, :little) <>
      encode_time(pathway.pathway_start) <> encode_time(pathway.edge_start)
  end

  # Close
  @doc """
  Encodes a pathway time. This is some weird stuff man.

  ## Examples

      iex> encode_time(1677632342000000000)
      <<224, 159, 240, 170, 211, 97>>

  """
  def encode_time(time) do
    (time / 1_000_000)
    |> floor()
    |> Protobuf.Wire.Zigzag.encode()
    |> Protobuf.Wire.Varint.encode()
    |> IO.iodata_to_binary()
  end

  @doc """
  Tries to decode a value into a pathway.

  ## Examples

      iex> "rtARjT7H1+7gn/Cq02Hgn/Cq02E="
      ...> |> Base.decode64!()
      ...> |> decode()
      %Pathway{hash: 17210443572488294574, pathway_start: 1677632342000000000, edge_start: 1677632342000000000}

  """
  @spec decode(String.t()) :: Pathway.t() | nil
  def decode(<<hash::binary-size(8), pathway::binary-size(6), edge::binary-size(6)>>) do
    %Pathway{
      hash: :binary.decode_unsigned(hash, :little),
      pathway_start: decode_time(pathway),
      edge_start: decode_time(edge)
    }
  end

  def decode(_value), do: nil

  @doc """
  Decodes a pathway binary time. Again. Weird stuff man.

  ## Examples

      iex> decode_time(<<224, 159, 240, 170, 211, 97>>)
      1677632342000000000

  """
  def decode_time(binary) do
    [time] = decode_time_binary(binary)
    time = Protobuf.Wire.Zigzag.decode(time)
    time * 1_000_000
  end

  defp decode_time_binary(<<bin::bits>>), do: decode_time_binary(bin, [])

  defp decode_time_binary(<<>>, acc), do: acc

  defdecoderp decode_time_binary(acc) do
    decode_time_binary(rest, [value | acc])
  end
end
