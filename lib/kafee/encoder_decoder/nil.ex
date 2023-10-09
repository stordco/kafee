defmodule Kafee.NilEncoderDecoder do
  @moduledoc """
  An encoder decoder that does nothing.
  """

  @behaviour Kafee.EncoderDecoder

  @doc false
  @impl Kafee.EncoderDecoder
  def encode!(value, _opts), do: value

  @doc false
  @impl Kafee.EncoderDecoder
  def decode!(value, _opts), do: value
end
