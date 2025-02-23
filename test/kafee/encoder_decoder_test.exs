defmodule Kafee.EncoderDecoderTest do
  use ExUnit.Case, async: true

  defmodule TestEncoder do
    @behaviour Kafee.EncoderDecoder

    @impl Kafee.EncoderDecoder
    def content_type, do: "application/x-test"

    @impl Kafee.EncoderDecoder
    def encode!(data, _opts) do
      case data do
        map when is_map(map) -> :erlang.term_to_binary(map)
        _ -> raise Kafee.EncoderDecoder.Error, message: "Can only encode maps"
      end
    end

    @impl Kafee.EncoderDecoder
    def decode!(binary, _opts) do
        :erlang.binary_to_term(binary)
      rescue
        # credo:disable-for-next-line Credo.Check.Warning.RaiseInsideRescue
        _ -> raise Kafee.EncoderDecoder.Error, message: "Invalid binary data"
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
