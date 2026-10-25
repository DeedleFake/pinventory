defmodule Pinventory.Items.NameSearchTest do
  use ExUnit.Case, async: true

  alias Pinventory.Items.NameSearch

  test "blank text has no terms" do
    assert NameSearch.parse("") == nil
    assert NameSearch.parse(" \t\n ") == nil
  end

  test "splits on whitespace and lowercases ASCII letters" do
    terms = NameSearch.parse("  Paint \t BRUSH ")

    assert Enum.map(terms, & &1.text) == ["paint", "brush"]
    assert Enum.map(terms, & &1.match) == ["*p*a*i*n*t*", "*b*r*u*s*h*"]
  end

  test "leaves non-ASCII letters as typed" do
    assert [%{text: "cafÉ"}] = NameSearch.parse("CAFÉ")
  end

  test "escapes GLOB wildcards" do
    assert [term] = NameSearch.parse("1*?[")

    assert term.match == "*1*[*]*[?]*[[]*"
    assert term.substring == "*1[*][?][[]*"
  end

  test "keeps other symbols as characters to match" do
    assert [term] = NameSearch.parse("o'brien,%_\\")

    assert term.match == "*o*'*b*r*i*e*n*,*%*_*\\*"
  end
end
