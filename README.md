# topiary-rhombus

Two experimental formatters for [Rhombus](https://rhombus-lang.org/):

- `rhombus-fmt.rkt`, written in Racket on the official shrubbery reader. It
  keeps the aligned indentation style of the Rhombus codebase.
- A [Topiary](https://github.com/topiary/topiary) formatter on
  [tree-sitter-rhombus](https://github.com/hon-gyu/tree-sitter-rhombus). Topiary can only indent by
  level, so it rewrites aligned code into a "break and indent" style.

Both keep the line breaks of the input. On the 614 `.rhm` files of the
Rhombus repository, `rhombus-fmt.rkt` changes 1.8% of lines and Topiary 28%.

## rhombus-fmt.rkt

### Usage

```sh
racket rhombus-fmt.rkt FILE ...        # print formatted files
racket rhombus-fmt.rkt -i FILE ...     # rewrite in place
```

Needs Racket with `shrubbery-lib`.

### Style

Within a line, the formatter puts one space between tokens, no space just
inside brackets or before `,` and `;`, and one space after `,`. Whitespace
before a comment, and inside strings, text and comments, is kept.

Each line is then indented relative to the token that gives it its meaning,
at that token's new column:

- A group lines up with the first group of its sequence.
- The first group of a block or bracket, when it starts a line, is indented
  2 past the group that owns the block or bracket.
- A continuation line keeps its offset from the start of its group.
- A `|` lines up with the first `|` of its alternatives, and the first one
  keeps its offset from its group.
- A closer that starts a line lines up with the line of its opener.
- Text lines of `@` notation move by as much as their `{`, so the text does
  not change.
- Comment lines move by as much as the line after them. Lines of a group
  commented out with `#//` have no tree, so they move with the line before
  them and are otherwise kept as written.

So respacing a line realigns everything that lines up with it:

```
fun   f( x,   y ):                      fun f(x, y):
    match x                               match x
    | _:   pack('(where_infoer,           | _: pack('(where_infoer,
                  ($x, $y))')                         ($x, $y))')
def    r = foo( alpha,                  def r = foo(alpha,
                beta )                              beta)
```

Afterwards, the formatter reads the result back with `shrubbery/parse`. If
the shrubbery differs from the input's, strings included, it leaves the file
alone and reports an error. `--no-check` skips this, for debugging.

Scribble modules (`#lang rhombus/scribble/...`), whose body is text, are left
as they are.

### Limitations

- The rules are fixed; there are no options.
- Spacing around operators is kept as written.
- Deliberate column alignment within a line, as in
  `f([1, 2],  [3, 4])`, is collapsed to single spaces.

## Topiary

### Setup

Needs `topiary` (tested with 0.7.3) and the `tree-sitter` CLI. Build the
grammar from a checkout of tree-sitter-rhombus next to the config:

```sh
tree-sitter build -o rhombus.dylib path/to/tree-sitter-rhombus
```

`languages.ncl` loads it as `rhombus.dylib` on every platform.

### Usage

```sh
./fmt.sh < input.rhm > output.rhm
```

`fmt.sh` runs `topiary format` with `languages.ncl` and
`queries/rhombus.scm`. Pass Topiary flags through it, e.g. `-s` to skip the
idempotence check.

### Style

- Line breaks and blank lines are kept.
- Indentation is two spaces per level: `:` blocks, `|` alternatives,
  brackets, quotes and a group's continuation lines each add one level.
  Alternatives line up with the group they belong to.
- Terms are separated by one space, operators included (`x*x` becomes
  `x * x`). Calls, indexing and member access are written without spaces
  (`f(x)`, `xs[0]`, `a.b`), as are prefix operators (`-x`, `$x`).
- `fun (x)`, `match (x)`, `if (x)` and similar forms keep their space; the
  list is in `queries/rhombus.scm`.

Topiary indents by level and cannot align to a column, but a multi-line
construct that starts mid-line sets its column there. The formatter
therefore breaks the line first, after `'` in a multi-line quote, after `(`
in a multi-line bracket, before the first group of a multi-line block, and
before the first `|` of multi-line alternatives:

```
bind_meta.pack('(where_infoer,          bind_meta.pack(
                 ($bind_left, ...))')     '
                                            (
                                              where_infoer,
                                              ($bind_left, ...)
                                            )'
                                        )
```

### Limitations

- **No alignment**, as above.
- **Multi-line text blocks.** The reader measures the indentation of the
  lines in an `@f{...}` text block relative to the `@`, so moving the `@`
  sideways changes the text. Topiary prints the text as a leaf and cannot
  shift its lines along with it.
- **Line width.** The formatter never wraps or joins lines by width.

## Checking

```sh
RHOMBUS_DIR=path/to/rhombus uv run --no-project python check.py [--racket] [FILE ...]
```

With no files, this checks every `.rhm` file in the
[Rhombus repository](https://github.com/racket/rhombus) checkout at
`RHOMBUS_DIR`, using Topiary, or `rhombus-fmt.rkt` with `--racket`. Each formatted file must:

- read to the same datum as the original, strings included, by the official
  reader (`read.rkt`, which uses `shrubbery/parse`)
- differ from the original only in whitespace, so no token or comment is lost
- format to itself

Racket must have `shrubbery-lib` installed; set `PLTADDONDIR` if it lives in
a non-default addon directory.

| Formatter         | Pass       | Failures                                            |
| ----------------- | ---------- | --------------------------------------------------- |
| `rhombus-fmt.rkt` | 613 of 614 | `main.rhm`                                          |
| Topiary           | 611 of 614 | `main.rhm`, plus 2 files with multi-line text blocks |

`rhombus-lib/rhombus/main.rhm` is `#lang racket/base`, which neither
formatter can read.
