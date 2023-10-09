if Code.ensure_loaded?(Protobuf) and Code.ensure_loaded?(Jason) do
  defmodule Kafee.ProtobufJsonEncoderDecoder do
    @moduledoc """
    Automatic Protobuf JSON encoding and decoding. Uses the
    `application/json` content type. This expects you to
    pass in a `:module` option for decoding data into the correct
    Struct.
    """

    @behaviour Kafee.EncoderDecoder

    @doc false
    @impl Kafee.EncoderDecoder
    def content_type, do: "application/json"

    @doc false
    @impl Kafee.EncoderDecoder
    def encode!(value, opts) do
      case Protobuf.JSON.encode(value, opts) do
        {:ok, data} -> data
        {:error, error} -> raise error
      end
    rescue
      e in FunctionClauseError ->
        reraise Kafee.EncoderDecoder.Error, [message: Exception.message(e)], __STACKTRACE__
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

      case Protobuf.JSON.decode(value, module) do
        {:ok, data} ->
          data

        {:error, error} ->
          raise Kafee.EncoderDecoder.Error, message: Exception.message(error)
      end
    end
  end
end
