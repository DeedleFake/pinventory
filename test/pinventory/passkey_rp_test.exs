defmodule Pinventory.Accounts.Passkey.RPTest do
  use ExUnit.Case, async: true

  alias Pinventory.Accounts.Passkey.RP

  test "accepts matching hosts and subdomains" do
    assert :ok = RP.check("localhost", "http://localhost:4000")
    assert :ok = RP.check("box.tail1.ts.net", "https://box.tail1.ts.net")
    assert :ok = RP.check("example.com", "https://app.example.com")
  end

  test "rejects mismatches with an actionable message" do
    assert {:error, msg} = RP.check("localhost", "https://box.tail1.ts.net")
    assert msg =~ "PASSKEY_RP_ID"
    assert msg =~ "PASSKEY_ORIGIN"
    assert msg =~ ~s("https://box.tail1.ts.net")

    assert {:error, _} = RP.check("example.com", "https://badexample.com")
    assert {:error, _} = RP.check("box.ts.net", "http://box.ts.net")
    assert {:error, _} = RP.check("box.ts.net", "https://box.ts.net/app")
  end

  test "the test config is valid" do
    assert :ok = RP.validate!()
  end
end
