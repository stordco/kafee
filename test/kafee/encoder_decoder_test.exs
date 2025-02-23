defmodule Kafee.EncoderDecoderTest do
  use ExUnit.Case, async: true

  defmodule TestEncoder do
    @behaviour Kafee.EncoderDecoder

    @impl true
    def content_type, do: "application/x-test"

    @impl true
    def encode!(data, _opts) do
      case data do
        map when is_map(map) -> :erlang.term_to_binary(map)
        _ -> raise Kafee.EncoderDecoder.Error, message: "Can only encode maps"
      end
    end

    @impl true
    def decode!(binary, _opts) do
      try do
        :erlang.binary_to_term(binary)
      rescue
        _ -> raise Kafee.EncoderDecoder.Error, message: "Invalid binary data"
      end
    end
  end

  describe "encoder decoder behaviour" do
    test "implements content_type/0" do
      assert TestEncoder.content_type() == "application/x-test"
    end

    test "encodes and decodes data successfully" do
      data = %{foo: "bar", baz: 123}
      encoded = TestEncoder.encode!(data, [])
      assert is_binary(encoded)
      decoded = TestEncoder.decode!(encoded, [])
      assert decoded == data
    end

    test "raises error for invalid input data" do
      assert_raise Kafee.EncoderDecoder.Error, "Can only encode maps", fn ->
        TestEncoder.encode!("not a map", [])
      end
    end

    test "raises error for invalid binary data" do
      assert_raise Kafee.EncoderDecoder.Error, "Invalid binary data", fn ->
        TestEncoder.decode!("invalid binary", [])
      end
    end
  end
end
