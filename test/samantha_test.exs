defmodule SamanthaTest do
  use ExUnit.Case
  doctest Samantha

  test "greets the world" do
    assert Samantha.hello() == :world
  end
end
