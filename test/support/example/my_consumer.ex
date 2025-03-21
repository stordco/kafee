defmodule MyConsumer do
  @moduledoc """
  An example consuming used for testing and documentation.
  """

  use Kafee.Consumer,
    otp_app: :kafee,
    adapter: nil,
    host: "localhost",
    consumer_group_id: "test",
    topic: "test"

  def handle_message(_message) do
    :ok
  end

  def handle_failure(_error, _message) do
    :ok
  end
end
