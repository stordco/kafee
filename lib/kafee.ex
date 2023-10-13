defmodule Kafee do
  @moduledoc """
  Kafee is an abstraction layer above multiple different lower level Kafka libraries, while also adding features relevant to Stord. This allows switching between `:brod` or `Broadway` for message consuming with a quick configuration change and no code changes. Features include:

  - Behaviour based adapters allowing quick low level changes.
  - Built in support for testing without mocking.
  - Automatic encoding and decoding of message values with `Jason` or `Protobuf`.
  - `:telemetry` metrics for producing and consuming messages.
  - Open Telemetry traces with correct attributes.
  - DataDog data streams support via `data-streams-ex`.
  """

  @typedoc "A Kafka message key."
  @type key :: binary()

  @typedoc "A Kafka message value encoded."
  @type value :: binary()

  @typedoc "A Kafka partition."
  @type topic :: String.t()

  @typedoc "Any valid Kafka partition."
  @type partition :: -2_147_483_648..2_147_483_647

  @typedoc "A function to assign a partition to a message."
  @type partition_fun :: :hash | :random | (topic(), [partition()], key(), value() -> partition())

  @typedoc "A valid Kafka offset for a message."
  @type offset :: -9_223_372_036_854_775_808..9_223_372_036_854_775_807

  @typedoc "A group id for consumers in a Kafka cluster."
  @type consumer_group_id :: binary()

  @typedoc "A list of Kafka message headers."
  @type headers :: [{binary(), binary()}]
end
