defmodule Kafee.Producer.TestAdapterTest do
  use Kafee.BrodCase, async: true

  defmodule MyProducer do
    use Kafee.Producer,
      otp_app: :kafee,
      adapter: Kafee.Producer.TestAdapter,
      encoder: Kafee.JasonEncoderDecoder,
      partition_fun: :random
  end

  setup %{topic: topic} do
    start_supervised!({MyProducer, topic: topic})
    :ok
  end

  describe "produce/2" do
    test "it asserts all keys on a message" do
      message = %Kafee.Producer.Message{
        key: "test-key",
        value: ~s({"key":"value"}),
        topic: "test-topic",
        partition: 0,
        partition_fun: :hash,
        headers: [{"dd-pathway-ctx", <<0>>}, {"kafka_contentType", "application/json"}]
      }

      assert :ok = MyProducer.produce([message])
      assert_receive {:kafee_message, ^message}
    end

    test "it decodes messages before sending to test pid" do
      spy(Kafee.JasonEncoderDecoder)

      message = %Kafee.Producer.Message{
        key: "test-key",
        value: %{"key" => "value"},
        topic: "test-topic",
        partition: 0,
        partition_fun: :hash,
        headers: [{"dd-pathway-ctx", <<0>>}, {"kafka_contentType", "application/json"}]
      }

      assert :ok = MyProducer.produce([message])
      assert_receive {:kafee_message, ^message}
      assert_called_once(Kafee.JasonEncoderDecoder.decode!(~s({"key":"value"}), _config))
    end
  end
end
