defmodule Kafee.SchemaRegistry.Cache do
  @moduledoc false

  use Nebulex.Cache,
    otp_app: :kafee,
    adapter: Nebulex.Adapters.Local
end
