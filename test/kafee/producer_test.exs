defmodule Kafka.ProducerTest do
  use ExUnit.Case, async: true

  import Kafee.Producer

  alias Kafka.ProducerTest.{MyProducer, Order}

  defmodule Order do
    defstruct [:id]
  end

  defmodule MyProducer do
    use Kafee.Producer,
      producer_backend: Kafee.Producer.TestBackend,
      partition_fun: nil

    def publish(:order_created, %Order{} = _order), do: :ok
  end

  doctest Kafee.Producer

  setup_all do
    start_supervised!(MyProducer)
    :ok
  end
end
