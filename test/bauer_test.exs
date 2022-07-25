defmodule BauerTest do
  use ExUnit.Case
  doctest Bauer

  test "greets the world" do
    assert Bauer.hello() == :world
  end
end
