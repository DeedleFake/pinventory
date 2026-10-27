defmodule Pinventory.MarkdownTest do
  use ExUnit.Case, async: true

  alias Pinventory.Markdown

  describe "to_html/1" do
    test "renders Markdown" do
      html = Markdown.to_html("# Names\n\n- **Boxes of Tissues**\n\n| a |\n| - |\n| 1 |")

      assert html =~ "<h1>Names</h1>"
      assert html =~ "<li><strong>Boxes of Tissues</strong></li>"
      assert html =~ "<td>1</td>"
    end

    test "drops raw HTML, scripts, and javascript links" do
      html =
        Markdown.to_html(
          "<script>alert(1)</script> <b onclick=\"x()\">hi</b> [x](javascript:alert(1))"
        )

      refute html =~ "<script"
      refute html =~ "onclick"
      refute html =~ "javascript:"
    end

    test "marks blocks with their source lines when asked" do
      text = "# Names\n\nOne\ntwo\n\n- a"

      assert Markdown.to_html(text, sourcepos: true) =~ ~s(<p data-sourcepos="3:1-4:3">)
      refute Markdown.to_html(text) =~ "data-sourcepos"
    end

    test "moves headings down a level when asked, stopping at h6" do
      html = Markdown.to_html("# One\n\n## Two\n\n###### Six", heading_offset: 1)

      assert html =~ "<h2>One</h2>"
      assert html =~ "<h3>Two</h3>"
      assert html =~ "<h6>Six</h6>"
      refute html =~ "<h1>"
    end

    test "keeps source lines on moved headings" do
      assert Markdown.to_html("# One", heading_offset: 1, sourcepos: true) =~
               ~s(<h2 data-sourcepos="1:1-1:5">One</h2>)
    end
  end

  describe "format/1" do
    test "rewrites Markdown in one style" do
      assert Markdown.format("Names\n=====\n\n* one\n+ two\n\n__bold__ _it_\n\n~~~\ncode\n~~~") ==
               "# Names\n\n- one\n\n<!-- end list -->\n\n- two\n\n**bold** *it*\n\n```\ncode\n```"
    end

    test "leaves formatted text as it is" do
      text = "# Names\n\n- one\n- two\n\n1. a\n2. b\n\n> quote\n\nfoo_bar 3*4"
      assert Markdown.format(text) == text
      assert Markdown.format(Markdown.format("* a\n*  b")) == Markdown.format("* a\n*  b")
    end

    test "keeps empty text empty" do
      assert Markdown.format("") == ""
    end
  end
end
