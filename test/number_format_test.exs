defmodule Number.Format.Test do
  use ExUnit.Case
  import Cldr.Number.Format.Test, only: [sanitize: 1]
  
  Enum.each Cldr.Number.Format.Test.test_data(), fn {value, result, args} ->
    test "formatted #{inspect value} == #{inspect sanitize(result)} with args: #{inspect args}" do
      assert Cldr.Number.to_string(unquote(value), unquote(args)) == unquote(result)
    end
  end
  
end