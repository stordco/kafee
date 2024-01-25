if Code.ensure_loaded?(Protobuf) do
  defmodule Kafee.ProtobufEncoderDecoder do
    @moduledoc """
    Automatic Protobuf binary format encoding and decoding. Uses
    the `application/x-protobuf` content type. This expects you to
    pass in a `:module` option for decoding data into the correct
    Struct.
    """

    @behaviour Kafee.EncoderDecoder

    @doc false
    @impl Kafee.EncoderDecoder
    def content_type, do: "application/x-protobuf"

    @doc false
    @impl Kafee.EncoderDecoder
    def encode!(value, _opts) do
      Protobuf.encode(value)
    rescue
      e in Protobuf.EncodeError ->
        reraise Kafee.EncoderDecoder.Error, [message: Exception.message(e)], __STACKTRACE__

      _e in FunctionClauseError ->
        inspected_value = inspect(value)

        reraise Kafee.EncoderDecoder.Error,
                [
                  message: """
                  Expected the value given to be a Protobuf encodable struct.

                  #{inspected_value}
                  """
                ],
                __STACKTRACE__
    end

    @doc false
    @impl Kafee.EncoderDecoder
    def decode!(value, opts) do
      unless module = Keyword.get(opts, :module) do
        raise Kafee.EncoderDecoder.Error,
          message: """
          Expected a :module to be given to the encoder decoder. This should
          be the Elixir module with `use Protobuf`.
          """
      end

      Protobuf.decode(value, module)
    rescue
      e in Protobuf.DecodeError ->
        reraise Kafee.EncoderDecoder.Error, [message: Exception.message(e)], __STACKTRACE__
    end
  end
end
