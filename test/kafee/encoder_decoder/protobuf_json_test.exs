defmodule Kafee.ProtobufJsonEncoderDecoderTest do
  use ExUnit.Case, async: true

  alias Kafee.ProtobufJsonEncoderDecoder, as: EncoderDecoder

  defmodule MyProtobuf do
    use Protobuf, protoc_gen_elixir_version: "0.10.0", syntax: :proto3

    field(:key, 1, type: :string)
  end

  describe "content_type/0" do
    test "returns application/json content type" do
      assert "application/json" = EncoderDecoder.content_type()
    end
  end

  describe "encode!/2" do
    test "encodes regular map" do
      assert ~s({"key":"value"}) = EncoderDecoder.encode!(%MyProtobuf{key: "value"}, [])
    end

    test "allows passing options in" do
      assert ~s({"key":"value"}) = EncoderDecoder.encode!(%MyProtobuf{key: "value"}, use_proto_names: true)
    end

    test "raises on unencodable data" do
      assert_raise Kafee.EncoderDecoder.Error, fn -> EncoderDecoder.encode!(self(), []) end
    end
  end

  describe "decode!/2" do
    test "raises error without module specified" do
      assert_raise Kafee.EncoderDecoder.Error, fn -> EncoderDecoder.decode!(~s({"key":"value"}), []) end
    end

    test "decodes regular map" do
      assert %MyProtobuf{key: "value"} = EncoderDecoder.decode!(~s({"key":"value"}), module: MyProtobuf)
    end

    test "raises on undecodable data" do
      assert_raise Kafee.EncoderDecoder.Error, fn -> EncoderDecoder.decode!("{/nojson", module: MyProtobuf) end
    end
  end
end
