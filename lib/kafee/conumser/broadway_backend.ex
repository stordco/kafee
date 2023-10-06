defmodule Kafee.Consumer.BroadwayBackend do
  @moduledoc """
  A Kafee consumer backend based on the exceptional `Broadway` library.
  This backend is made for maximum freight train throughput with no
  stopping. **All messages are acknowledged immediately** after being
  received. This means that you are responsible for creating some logic
  to handle failed messages, **or they will be dropped**.
  """

  @behaviour Kafee.Consumer.Backend

  @doc false
  @impl Kafee.Consumer.Backend
  def start_link(module, _options) do
    Broadway.start_link(__MODULE__,
      name: module,
      producer: [
        module:
          {BroadwayKafka.Producer,
           [
             hosts: [localhost: 9092],
             group_id: "group_1",
             topics: ["test"]
           ]},
        concurrency: 10
      ],
      processors: [
        default: [
          concurrency: 10
        ]
      ]
    )
  end

  @doc false
  def handle_message(message, context) do
    full_message = %Kafee.Consumer.Message{

    }

    context.config.consumer_module.push_messages(context.consumer, full_message)
  end
end
