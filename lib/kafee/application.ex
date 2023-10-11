defmodule Kafee.Application do
  @moduledoc false

  use Application

  @doc false
  @spec start(Application.start_type(), term()) :: {:ok, pid} | {:error, term()}
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Kafee.Producer.AsyncRegistry}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
