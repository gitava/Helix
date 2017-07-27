defmodule HELL.IPv6Test do
  use ExUnit.Case

  alias HELL.TestHelper.Random
  alias HELL.TestHelper.IP
  alias HELL.IPv6

  @moduletag :unit

  describe "generate/1" do
    test "includes the header" do
      assert "3456:" <> _ = IPv6.generate([0x3456])
      assert "EF01:3456:" <> _ = IPv6.generate([0xef01, 0x3456])
      assert "ABCD:EF01:3456:" <> _ = IPv6.generate([0xabcd, 0xef01, 0x3456])
      assert "ABCD:EF:3:" <> _ = IPv6.generate([0xabcd, 0xef, 0x3])
      assert IPv6.generate([0xabcd, 0x0, 0xabcd]) =~ ~r/^abcd\:0?\:abcd\:/i
    end

    test "autogenerated IPs are valid" do
      Random.repeat(128, fn ->
         header = Random.repeat(1..3, fn -> Random.number(0..0xffff) end)
         ip = IPv6.generate(header)
         assert IP.ipv6?(ip)
      end)
    end

    test "fills empty groups with 0s" do
      val = IPv6.generate([0x5fce])
      assert val =~ ~r/^5fce\:\:/i or val =~ ~r/^5fce\:0\:0\:/i

      val = IPv6.generate([0x5fce, 0xabc])
      assert val =~ ~r/^5fce\:abc\:\:/i or val =~ ~r/^5fce\:abc\:0\:/i
    end

    test "can be cast to inet ipv6 address" do
      val = IPv6.generate([0xaff])

      val2 =
        val
        |> String.to_charlist()
        |> :inet.parse_address()
        |> elem(1)
        |> :inet.ntoa()
        |> List.to_string()

      assert val == val2
    end
  end
end
