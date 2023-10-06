defmodule Kafee.JasonEncoderDecoderTest do
  use ExUnit.Case, async: true

  alias Kafee.JasonEncoderDecoder, as: EncoderDecoder

  describe "content_type/0" do
    test "returns application/json content type" do
      assert "application/json" = EncoderDecoder.content_type()
    end
  end

  describe "encode!/2" do
    test "encodes regular map" do
      assert "{\"key\":\"value\"}" = EncoderDecoder.encode!(%{key: "value"}, [])
    end

    test "allows passing options in" do
      assert "{\n  \"key\": \"value\"\n}" = EncoderDecoder.encode!(%{key: "value"}, pretty: true)
    end

    test "raises on unencodable data" do
      assert_raise Kafee.EncoderDecoder.Error, fn -> EncoderDecoder.encode!(self(), []) end
    end
  end

  describe "decode!/2" do
    test "decodes regular map" do
      assert %{"key" => "value"} = EncoderDecoder.decode!("{\"key\":\"value\"}", [])
    end

    test "allows passing options in" do
      assert %{key: "value"} = EncoderDecoder.decode!("{\"key\":\"value\"}", keys: :atoms)
    end

    test "raises on undecodable data" do
      assert_raise Kafee.EncoderDecoder.Error, fn -> EncoderDecoder.decode!("{/nojson", []) end
    end
  end
end
