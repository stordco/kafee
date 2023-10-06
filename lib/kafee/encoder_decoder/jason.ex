if Code.ensure_loaded?(Jason) do
  defmodule Kafee.JasonEncoderDecoder do
    @moduledoc """
    Automatic JSON encoding and decoding provided by `Jason`. Uses
    the `application/json` content type.
    """

    @behaviour Kafee.EncoderDecoder

    @doc false
    @impl Kafee.EncoderDecoder
    def content_type, do: "application/json"

    @doc false
    @impl Kafee.EncoderDecoder
    def encode!(value, opts) do
      Jason.encode!(value, opts)
    rescue
      e in Jason.EncodeError ->
        reraise Kafee.EncoderDecoder.Error, [message: Exception.message(e)], __STACKTRACE__

      _e in Protocol.UndefinedError ->
        inspected_value = inspect(value)

        reraise Kafee.EncoderDecoder.Error,
                [
                  message: """
                  Jason.Encoder protocol is not implemented for value.

                  #{inspected_value}
                  """
                ],
                __STACKTRACE__
    end

    @doc false
    @impl Kafee.EncoderDecoder
    def decode!(value, opts) do
      Jason.decode!(value, opts)
    rescue
      e in Jason.DecodeError ->
        reraise Kafee.EncoderDecoder.Error, [message: Exception.message(e)], __STACKTRACE__
    end
  end
end
