defmodule ScannerTest do
  @moduledoc false
  use ExUnit.Case
  alias Gherkin.Scanner
  alias Gherkin.Scanner.SyntaxError

  @keywords [
    {"Feature:", :feature},
    {"Rule:", :rule},
    {"Example:", :scenario},
    {"Scenario:", :scenario},
    {"Given ", :given},
    {"When ", :when},
    {"Then ", :then},
    {"But ", :but},
    {"And ", :and},
    {"Background:", :background},
    {"Scenario Outline:", :scenario_outline},
    {"Scenario Template:", :scenario_outline},
    {"Examples:", :scenarios},
    {"Scenarios:", :scenarios}
  ]

  def tokenize(contents) do
    contents
    |> Scanner.tokenize()
    |> Enum.take(2000)
  end

  describe "#tokenize(list) Recognizes Primitives:" do
    @some_text "This is some text"
    @keywords
    |> Enum.each(fn {textual_syntax, keyword} ->
      test "Gherkin Keyword: `#{textual_syntax}`" do
        assert [
                 {unquote(keyword), String.trim(unquote(textual_syntax), ":"), {:location, 1, 1},
                  unquote(@some_text)}
               ] ==
                 tokenize(["#{String.trim(unquote(textual_syntax))} #{@some_text}"])
      end
    end)

    test "Recognizes Comment: `#`" do
      assert [{:comment, "#", {:location, 1, 1}, " This is some comment"}] ==
               tokenize(["# This is some comment"])
    end

    test "Recognizes Tag: `@`" do
      assert [{:tag, "@", {:location, 1, 1}, [{1, "@some_tag"}]}] == tokenize(["@some_tag"])
    end

    test "Recognizes Table: `|`" do
      assert [
               {:data_table, "|", {:location, 1, 1}, [{3, "A"}, {7, "B"}, {11, "C"}]}
             ] ==
               tokenize(["| A | B | C |"])
    end

    test "Recognizes Docstring: `\"\"\"`" do
      delim = "\"\"\""

      assert [{:doc_string, "\"\"\"", {:location, 1, 1}, {delim, :plain}}] ==
               tokenize([delim])
    end

    test "Recognizes Docstring with annotated type: `\"\"\"ruby`" do
      delim = "\"\"\""

      assert [{:doc_string, "\"\"\"", {:location, 1, 1}, {delim, :ruby}}] ==
               tokenize(["#{delim}ruby"])
    end
  end

  describe "#tokenize(path: _) works for all Good Feature Files" do
    __DIR__
    |> Path.join("support/testdata/good/*.feature")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      file =
        path
        |> String.split()
        |> List.last()

      test "#{file}" do
        expected = File.read!("#{unquote(path)}.tokens")

        result =
          [path: unquote(path)]
          |> tokenize()
          |> ScannerSupport.to_feature_tokens_format()

        if expected != result do
          IO.inspect(unquote(path), label: :failed, syntax_colors: [string: :red])
        end

        assert expected == result
      end
    end)
  end

  describe "#tokenize(list) ignores Gherkin Keywords within Docstring" do
    @some_text "This is some text"
    @keywords
    |> Enum.each(fn {textual_syntax, keyword} ->
      test "Gherkin Keyword: `#{textual_syntax}`" do
        gherkin_keyword_content = "#{unquote(textual_syntax)} #{@some_text}"

        docstring_lines =
          """
          This is a Docstring

          All content in here is regarded as normal text
          Regardless as to Gherkin Keywords being indented:
                #{gherkin_keyword_content}

          or not
          #{gherkin_keyword_content}
          """
          |> String.split("\n")
          |> Enum.map(&(&1 <> "\n"))
          |> Kernel.++(["\"\"\""])

        ["\"\"\"" | docstring_lines]
        |> tokenize
        |> Enum.each(fn {actual_keyword, actual_textual_syntax, _, _} ->
          assert actual_keyword != unquote(keyword)
          assert actual_textual_syntax != unquote(textual_syntax)
          assert actual_keyword in [:doc_string, :content, :empty]
        end)
      end
    end)
  end

  describe "#tokenize(list) does not allow ending Docstring with a typed delim" do
    test "Starting without typed delim but ending with typed delim" do
      assert_raise SyntaxError, fn ->
        tokenize(["\"\"\"", "a\n", "\"\"\"ruby"])
      end
    end

    test "Starting and ending with typed delim" do
      assert_raise SyntaxError, fn ->
        tokenize(["\"\"\"ruby", "a\n", "\"\"\"ruby"])
      end

      assert_raise SyntaxError, fn ->
        tokenize(["\"\"\"ruby", "a\n", "\"\"\"ruby", "\"\"\""])
      end
    end
  end
end
