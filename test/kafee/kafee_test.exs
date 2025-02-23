defmodule KafeeTest do
  use ExUnit.Case, async: true

  import Kafee, only: [is_partition: 1, is_offset: 1]

  describe "is_partition/1" do
    test "returns true for valid partition numbers" do
      assert is_partition(0)
      assert is_partition(1)
      assert is_partition(-1)
      assert is_partition(2_147_483_647)
      assert is_partition(-2_147_483_648)
    end

    test "returns false for invalid partition numbers" do
      refute is_partition(2_147_483_648)
      refute is_partition(-2_147_483_649)
      refute is_partition(2.5)
      refute is_partition("not a number")
    end
  end

  describe "is_offset/1" do
    test "returns true for valid offset numbers" do
      assert is_offset(0)
      assert is_offset(1)
      assert is_offset(-1)
      assert is_offset(9_223_372_036_854_775_807)
      assert is_offset(-9_223_372_036_854_775_808)
    end

    test "returns false for invalid offset numbers" do
      refute is_offset(9_223_372_036_854_775_808)
      refute is_offset(-9_223_372_036_854_775_809)
      refute is_offset(2.5)
      refute is_offset("not a number")
    end
  end
end
