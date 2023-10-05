defmodule Kafee.Test do
  @moduledoc """
  Helpers for testing Kafka activity with the Kafee library.

  ## Note on sending from other processes

  If you are sending emails from another process (for example,
  from inside a `Task` or `GenServer`) you may need to use
  the shared mode. See the docs on `__using__/1` for more
  information.

  ## Producer

  In order to test Kafee producers, you will need to set the
  `Kafee.Producer.TestBackend`. This can be done in your config
  like so:

      config :kafee, :producer,
        producer_backend: Kafee.Producer.TestBackend

  or if you are specifically setting the producer_backend in
  a module, you'll need to do the same there.

      def MyProducer
        use Kafee.Producer,
          producer_backend: Application.compile_env(:my_app, :producer_backend)

  Once that is done, you can use this testing module in your tests.

      def MyProducerTest do
        use ExUnit.Case
        use Kafee.Test

        test "message is produced"
          MyApplication.send_kafka_message()
          assert_kafee_message(%{
            key: "test-key"
          })
        end
      end

  """

  import ExUnit.Assertions

  @doc """
  Imports the `Kafee.Test` helper macros.

  The `Kafee.Test` and `Kafee.Producer.TestBackend` work by sending a message
  to the current process when a Kafka message is sent. The process mailbox is
  then checked when the assertion helpers like `assert_producer_message/1`.

  Sometimes messages don't show up when asserting because you can send messages
  from a _different_ process than the test process. When that happens,
  turn on the shared mode. This will tell `Kafee.Producer.TestBackend` to always
  send the to the test process. This means that you cannot use shared mode with
  async tests.

  Try to use this first:

      use ExUnit.Case, async: true
      use Kafee.Test

  If that does not work, set `shared: true`

      use ExUnit.Case, async: false
      use Kafee.Test, shared: true

  It's common to require `shared: true` when sending Kafka messages from a `Task
  or `GenServer`.
  """
  defmacro __using__(shared: true) do
    quote do
      import Kafee.Test

      setup tags do
        if tags[:async] do
          raise """
          You cannot use Kafee.Test shared mode with async tests. Please
          set your test to [async: false].
          """
        end

        Application.put_env(:kafee, :test_process, self())
        :ok
      end
    end
  end

  defmacro __using__(_opts) do
    quote do
      # credo:disable-for-lines:2 Credo.Check.Consistency.MultiAliasImportRequireUse
      import ExUnit.Assertions
      import Kafee.Test

      setup tags do
        Application.delete_env(:kafee, :test_process)
        :ok
      end
    end
  end

  @doc """
  Asserts a Kafee message is produced. In case you are
  delivering from another process, the assertion waits up to 100ms
  before failing. Typically if a message is successfully sent the
  assertion will pass instantly, so the test suites will remain fast.

  ## Examples

      message = %Kafee.Producer.Message{}
      MyProducer.produce(message)
      assert_kafee_message(message)

  """
  defmacro assert_kafee_message(message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 500)

    quote do
      assert_receive({:kafee_message, unquote(message)}, unquote(timeout))
    end
  end

  @doc """
  Refutes a Kafee message is produced.

  ## Examples

      message = %Kafee.Producer.Message{}
      refute_kafee_message(message)

  """
  defmacro refute_kafee_message(message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 500)

    quote do
      refute_receive({:kafee_message, unquote(message)}, unquote(timeout))
    end
  end

  @doc """
  Returns a list of messages that has been produced during
  the test. We do _not_ recommend using this function as it
  can change between tests very easily.

  ## Examples

      assert [%Kafee.Producer.Message{}] = kafee_messages()

  """
  def kafee_messages do
    {:messages, messages} = Process.info(self(), :messages)

    for {:kafee_message, message} <- messages do
      message
    end
  end
end
