defmodule PinventoryWeb.NoteHistoryComponentsTest do
  use ExUnit.Case, async: true

  alias Pinventory.Accounts.User
  alias Pinventory.Items.NoteVersion
  alias PinventoryWeb.NoteHistoryComponents

  describe "authors_label/1" do
    test "names one, two, or three authors" do
      assert NoteHistoryComponents.authors_label(["deedle"]) == "deedle"
      assert NoteHistoryComponents.authors_label(["deedle", "sam"]) == "deedle and sam"

      assert NoteHistoryComponents.authors_label(["deedle", "sam", "alex"]) ==
               "deedle, sam, and alex"
    end

    test "names two and others for four or more, with the full list as a tooltip" do
      authors = ["deedle", "sam", "alex", "kim"]

      assert NoteHistoryComponents.authors_label(authors) == "deedle, sam, and others"
      assert NoteHistoryComponents.authors_title(authors) == "deedle, sam, alex, kim"
      assert NoteHistoryComponents.authors_title(["deedle", "sam", "alex"]) == nil
    end
  end

  test "range_authors/3 lists each author in the compared range once" do
    versions = [
      %NoteVersion{number: 0, text: ""},
      version(1, "alex@example.com"),
      version(2, "deedle@example.com"),
      version(3, "sam@example.com"),
      version(4, "deedle@example.com")
    ]

    assert NoteHistoryComponents.range_authors(versions, 1, 4) == ["deedle", "sam"]
    assert NoteHistoryComponents.range_authors(versions, 4, 0) == ["alex", "deedle", "sam"]
    assert NoteHistoryComponents.range_authors(versions, 2, 2) == []
  end

  test "relative_time/2" do
    now = ~U[2026-10-11 12:00:00Z]

    assert NoteHistoryComponents.relative_time(~U[2026-10-11 11:59:30Z], now) == "just now"
    assert NoteHistoryComponents.relative_time(~U[2026-10-11 11:15:00Z], now) == "45m ago"
    assert NoteHistoryComponents.relative_time(~U[2026-10-11 07:00:00Z], now) == "5h ago"
    assert NoteHistoryComponents.relative_time(~U[2026-10-08 12:00:00Z], now) == "3d ago"
    assert NoteHistoryComponents.relative_time(~U[2026-08-01 12:00:00Z], now) == "Aug 1, 2026"
  end

  defp version(number, email) do
    %NoteVersion{number: number, text: "v#{number}", user: %User{email: email}}
  end
end
