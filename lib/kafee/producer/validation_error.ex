defmodule Kafee.Producer.ValidationError do
  @moduledoc """
  This error indicates a malformed message and gets raised before
  the message hits the queue.
  """

  defexception message: "Error while validating a message for Kafka", kafee_message: nil, validation_error: nil

  @impl Exception
  def exception(value) do
    kafee_message = Keyword.fetch!(value, :kafee_message)

    case Keyword.get(value, :validation_error, :unknown) do
      :topic ->
        %__MODULE__{
          message: "Message is missing a topic to send to.",
          kafee_message: kafee_message,
          validation_error: :topic
        }

      :partition ->
        %__MODULE__{
          message: "Message is missing a partition to send to.",
          kafee_message: kafee_message,
          validation_error: :partition
        }

      :headers ->
        %__MODULE__{
          message: "Message header keys and values must be a binary value.",
          kafee_message: kafee_message,
          validation_error: :headers
        }

      _ ->
        %__MODULE__{kafee_message: kafee_message}
    end
  end
end
