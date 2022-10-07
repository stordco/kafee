defmodule Kafee.Producer.AsyncBackend do
  @moduledoc """
  This is an asynchronous backend for sending messages to Kafka. It utilizes a
  `Registry` and `DynamicSupervisor` to start a `Kafee.Producer.AsyncWorker`
  process for every topic * partition we send messages to.

  The supervisor tree will look something similar to this when in use:

  ```mermaid
  graph TD
    B[Kafee.Producer.AsyncBackend]

    B --> U[:brod_client]
    B --> C[Kafee.Producer.AsyncConfig]
    B --> R[Kafee.Producer.AsyncRegistry]
    B --> S[Kafee.Producer.AsyncSupervisor]

    S --> |"topic: 1, partition: 0"| W1[Kafee.Producer.AsyncWorker]
    S --> |"topic: 1, partition: 1"| W2[Kafee.Producer.AsyncWorker]
    S --> |"topic: 2, partition: 0"| W4[Kafee.Producer.AsyncWorker]
  ```

  For the process of queuing messages, it looks something like this:

  ```mermaid
  sequenceDiagram
    participant P as MyProducer
    participant B as Kafee.Producer.AsyncBackend
    participant S as Kafee.Producer.AsyncSupervisor
    participant W as Kafee.Producer.AsyncWorker

    P->>+B: get_partition/4
    B-->>-P: 2

    P->>+B: produce/4
    B->>+S: queue/4
    Note over S,W: Creates AsyncWorker if it doesn't exist
    S->>+W: queue/2
    W-->>-P: :ok

    loop Every 10 seconds by default
        W->>+Kafka: send/4
        Kafka-->>-W: :ack
    end
  ```
  """
end
