defmodule Kafee.Reconsumer do
  @moduledoc """
  Reconsumer is a `Task` that queries and filters
  messages from Kafka for ad hoc re-consumption. This
  is mainly used for debugging or fixing an out of band
  issue that arose in the system.

  ## Querying

  This module is based on a built query for the Kafka messages.
  It's based off of `Ecto.Query` and allows you to filter out
  messages based off of timestamp, offset, partition, topic, and key.

  To start, you want to create a query from an already existing `Kafee.Consumer`.
  This will pull in all of the consumer configuration set, like connection
  details, group id, topics, and handler function.

      MyConsumer
      |> Kafee.Reconsumer.from_consumer()

  Next up, you can refine the query by adding or ignoring topics.

      MyConsumer
      |> Kafee.Reconsumer.from_consumer()
      |> Kafee.Reconsumer.add_topic(["good_topic_1"])
      |> Kafee.Reconsumer.remove_topic(["bad_topic_1", "bad_topic_2"])

  You'll then want to filter out the messages based off of the criteria you have.

      MyConsumer
      |> Kafee.Reconsumer.from_consumer()
      |> Kafee.Reconsumer.add_topic(["good_topic_1"])
      |> Kafee.Reconsumer.remove_topic(["bad_topic_1", "bad_topic_2"])
      |> Kafee.Reconsumer.filter_timestamp_window(~U[2020-01-01 00:00:00Z], ~U[2020-01-02 00:00:00Z])
      |> Kafee.Reconsumer.filter_key("my_key")

  Lastly, you can run the query.

      MyConsumer
      |> Kafee.Reconsumer.from_consumer()
      |> Kafee.Reconsumer.add_topic(["good_topic_1"])
      |> Kafee.Reconsumer.remove_topic(["bad_topic_1", "bad_topic_2"])
      |> Kafee.Reconsumer.filter_timestamp_window(~U[2020-01-01 00:00:00Z], ~U[2020-01-02 00:00:00Z])
      |> Kafee.Reconsumer.filter_key("my_key")
      |> Kafee.Reconsumer.run()

  ### Assumptions

  When the query is created from the consumer, we take the existing consumer group name and
  append a random generated string. This is to ensure that the reconsumer does not interfere
  with the existing consumer group. Once the reconsumer is done, we will automatially delete the
  consumer group to avoid any lingering consumer group issues.

  When setting time windows, we set the initial offset for the consumer groups _close to_ (but not exactly)
  to the needed offset. This should optimize the query to only pull in the messages that are needed.

  ## Running

  Once you have your reconsumer query set up, you can call the `run/0` function.
  This will run the reconsumer synchronously. We recommend wrapping this up in a
  `Task`, use [`Flame`](https://github.com/phoenixframework/flame), or run via a Kubernetes job.
  """
end
