defmodule BBTest do
  use ExUnit.Case
  doctest BB

  test "greets the world" do
    assert BB.hello() == :world
  end
end
