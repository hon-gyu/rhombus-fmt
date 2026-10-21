; Topiary formatting queries for Rhombus (shrubbery notation).
;
; Shrubbery is layout-sensitive, so this formatter keeps the line structure of
; the input (every line break is an input softline) and only normalizes
; horizontal spacing and indentation. Indentation is relative to the enclosing
; construct, which is only sound when a multi-line construct does not start
; mid-line; the rules below force a line break in those cases.

; Leaves
; ======

[
  (string)
  (byte_string)
  (sexp_escape)
  (comment)
  (lang_line)
  (line_continuation)
  (text_block)
] @leaf

; A Scribble module body is text, where whitespace is content
(source_file
  (text)) @leaf

; Line structure
; ==============

; Keep line breaks from the input; otherwise separate by a space
[
  (identifier)
  (keyword)
  (operator)
  (number)
  (string)
  (byte_string)
  (boolean)
  (void)
  (sexp_escape)
  (parens)
  (brackets)
  (braces)
  (quotes)
  (at_expression)
  (group)
  (group_comment)
  (alternatives)
  (alternative)
  (alternative_comment)
  (comment)
  (splice)
] @prepend_input_softline

[
  (group)
  (group_comment)
  (alternative)
  (alternative_comment)
  (comment)
] @allow_blank_line_before

(lang_line) @append_hardline

; A line comment runs to the end of the line
(
  (comment) @append_hardline
  (#match? @append_hardline "^(//|#!|@//)")
)

(
  (comment) @append_input_softline
  (#match? @append_input_softline "^/\\*")
)

[
  ","
  ";"
] @prepend_antispace

(group_comment
  "#//" @append_space)

(alternative_comment
  "#//" @append_space)

; Blocks and alternatives
; =======================

(block
  ":" @prepend_antispace @append_indent_start)

; on the last named child, or the `:` itself when there is none
(block
  (_) @append_indent_end
  .)

(block
  ":" @append_indent_end
  .)

; A multi-line block starts on its own line, so that its groups and their
; continuation lines can be indented relative to the enclosing group. The
; break goes before the first group, so after the `«` of `:«...»`.
(block
  .
  [
    (group)
    (group_comment)
  ] @prepend_spaced_softline)

; `| ` is as wide as one indentation step, so an alternative's groups line up
; with its first one
(alternative
  "|" @append_space @append_indent_start)

; on the last named child, or the `|` itself when there is none
(alternative
  (_) @append_indent_end
  .)

(alternative
  "|" @append_indent_end
  .)

; Alternatives line up with their first one, so multi-line alternatives start
; on their own line
(alternatives
  .
  (alternative) @prepend_hardline
  (#multi_line_only!))

; Groups
; ======

; Continuation lines of a group are indented, but its block and alternatives
; are indented relative to the group itself
(group
  .
  [
    (identifier)
    (keyword)
    (operator)
    (number)
    (string)
    (byte_string)
    (boolean)
    (void)
    (sexp_escape)
    (parens)
    (brackets)
    (braces)
    (quotes)
    (at_expression)
  ] @append_indent_start)

; Brackets and quotes are not sensitive to the column of the enclosing group,
; so their contents are indented relative to the group itself rather than to
; its continuation lines. The first term already started the indentation.
(group
  (_)
  .
  [
    (parens)
    (brackets)
    (braces)
    (quotes)
  ] @prepend_indent_end @append_indent_start)

(group
  [
    (identifier)
    (keyword)
    (operator)
    (number)
    (string)
    (byte_string)
    (boolean)
    (void)
    (sexp_escape)
    (parens)
    (brackets)
    (braces)
    (quotes)
    (at_expression)
  ] @append_indent_end
  .
  (comment)*
  .
  [
    (block)
    (alternatives)
  ])

(group
  [
    (identifier)
    (keyword)
    (operator)
    (number)
    (string)
    (byte_string)
    (boolean)
    (void)
    (sexp_escape)
    (parens)
    (brackets)
    (braces)
    (quotes)
    (at_expression)
  ] @append_indent_end
  .)

; Brackets
; ========

(_
  [
    "("
    "["
    "{"
  ] @append_antispace @append_empty_softline @append_indent_start
  [
    ")"
    "]"
    "}"
  ] @prepend_antispace @prepend_empty_softline @prepend_indent_end)

; A multi-line group inside brackets starts on its own line
(parens
  (group
    .
    (_) @prepend_hardline)
  (#multi_line_only!))

(brackets
  (group
    .
    (_) @prepend_hardline)
  (#multi_line_only!))

(braces
  (group
    .
    (_) @prepend_hardline)
  (#multi_line_only!))

(quotes
  .
  "'" @append_antispace @append_indent_start
  "'" @prepend_antispace @prepend_indent_end
  .)

; The groups of a quote line up with its first one, so a multi-line quote
; starts them on their own line
(quotes
  .
  [
    (group)
    (group_comment)
  ] @prepend_empty_softline)

; Guillemets
; ----------

"«" @append_antispace

"»" @prepend_antispace

; `:«`, `|«` and `'«` are already indented by their block, alternative or
; quote, which also puts a multi-line sequence on its own line
(_
  [
    ":"
    "|"
  ] @append_antispace
  .
  "«")

(_
  [
    ";«"
    "(«"
  ] @append_antispace @append_empty_softline @append_indent_start
  [
    "»"
    "»)"
  ] @prepend_antispace @prepend_indent_end)

(at_command
  "«" @append_antispace @append_empty_softline @append_indent_start
  "»" @prepend_indent_end)


; At-notation
; -----------

; The parts of `@command(arguments){text}` must be adjacent
(at_expression
  "@" @append_antispace)

(at_expression
  (_) @append_antispace
  .
  (_))

(at_command
  (_) @append_antispace)

(at_arguments
  (group
    .
    (_) @prepend_hardline)
  (#multi_line_only!))

; Adjacency
; =========

; Function calls and indexing: `f(x)`, `xs[0]`, `Map{}`, but not after forms
; that take a parenthesized term, like `fun (x): x`
(
  (identifier) @append_antispace
  .
  [
    (parens)
    (brackets)
    (braces)
  ]
  (#not-any-of? @append_antispace
    "fun" "def" "let" "val" "match" "if" "cond" "when" "unless" "for" "values"
    "import" "export" "return" "method" "and" "or" "not" "in" "is_a")
)

(
  [
    (parens)
    (brackets)
  ] @append_antispace
  .
  [
    (parens)
    (brackets)
  ]
)

(
  (sexp_escape) @append_antispace
  .
  (parens)
)

; Member access: `a.b`
(
  [
    (identifier)
    (parens)
    (brackets)
    (braces)
  ]
  .
  (operator) @prepend_antispace @append_antispace
  .
  [
    (identifier)
    (sexp_escape)
  ]
  (#eq? @prepend_antispace ".")
)

; Prefix operators: `-x`, `a * -b`, `$x`
(group
  .
  (operator) @append_antispace
  .
  [
    (identifier)
    (parens)
    (brackets)
    (braces)
  ])

(
  (operator)
  .
  (operator) @append_antispace
  .
  [
    (identifier)
    (parens)
    (brackets)
    (braces)
  ]
)

(
  (operator) @append_antispace
  .
  [
    (identifier)
    (parens)
    (brackets)
    (braces)
  ]
  (#eq? @append_antispace "$")
)
