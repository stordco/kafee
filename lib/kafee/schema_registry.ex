defmodule Kafee.SchemaRegistry do
  @moduledoc """
  Helper functions for interacting with the Confluent Schema Registry
  and stord-proto Protobuf messages. This handles decoding and encoding
  from the schema registry wire format. It's important to note, we **do not**
  use schema registry to dynamically fetch schemas. We use the pre built
  stord-proto library and _only_ handle the bare minimum to get
  schema registry wire format working.

  ## Assumptions

  To do this, we make a couple of assumptions based off how we upload
  Protobuf messages to schema registry.

  1) The protobuf message we encode as is the first message in the
  schema registry. For example, when viewing a schema online, it will
  look like this:

  ```proto
  syntax = "proto3";

  message stord {
    message activity {
      message v1alpha {
        message Envelope {
          oneof message {
            FirstMessage first_message = 3;
          }
        }
        message FirstMessage {
          string field = 1;
        }
      }
    }
  }
  ```

  If it looks like the following example, this module will run into issues.

  ```proto
  syntax = "proto3";

  message stord {
    message activity {
      message v1alpha {
        message FirstMessage {
          string field = 1;
        }
        message Envelope {
          oneof message {
            FirstMessage first_message = 3;
          }
        }
      }
    }
  }
  ```

  2) We always use the latest version of the schema. This means we need
  to keep backwards compatibility. This is done via linting rules in
  stord-proto.

  ## Configuration

  This module requires the following configuration:

  ```elixir
  config :kafee, :schema_registry,
    url: "http://localhost:8081",
    username: "user",
    password: "pass"
  ```

  """
end
