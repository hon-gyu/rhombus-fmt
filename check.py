"""Check the formatter on Rhombus files.

Usage: uv run --no-project python check.py [--racket] [FILE ...]

With no files, checks every `.rhm` file in the Rhombus checkout named by the
`RHOMBUS_DIR` environment variable. Each file is formatted, with Topiary or with
`--racket` with rhombus-fmt.rkt, and then must

- read to the same shrubbery as the original, by the official reader,
- differ from the original only in whitespace, and
- be unchanged by formatting it again.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "read.rkt")


def reference(files):
    out = subprocess.run(
        ["racket", REF, *files], capture_output=True, text=True, check=True
    ).stdout
    return dict(line.split("\t", 1) for line in out.splitlines())


def fmt(path):
    with open(path, "rb") as f:
        p = subprocess.run(
            [os.path.join(HERE, "fmt.sh")], stdin=f, capture_output=True, check=False
        )
    return p.returncode, p.stdout, p.stderr.decode(errors="replace")


def racket_fmt_all(files, tmp):
    """Format `files` in one Racket process, twice, to check idempotence."""
    results = {}
    for round in ("a", "b"):
        copies = {}
        for i, f in enumerate(files):
            if isinstance(results.get(f), str):
                continue
            c = os.path.join(tmp, f"{i}{round}.rhm")
            if round == "a":
                shutil.copy(f, c)
            else:
                with open(c, "wb") as h:
                    h.write(results[f])
            copies[c] = f
        p = subprocess.run(
            ["racket", os.path.join(HERE, "rhombus-fmt.rkt"), "-i", *copies],
            capture_output=True,
            text=True,
            check=False,
        )
        errors = dict(
            line.split(": ", 1) for line in p.stderr.splitlines() if ": " in line
        )
        for c, f in copies.items():
            if c in errors:
                results[f] = "rhombus-fmt: " + errors[c]
                continue
            with open(c, "rb") as h:
                out = h.read()
            if round == "b" and out != results[f]:
                results[f] = "not idempotent"
            else:
                results[f] = out
    return results


def squash(b):
    return re.sub(rb"\s+", b"", b)


def main():
    args = sys.argv[1:]
    racket = "--racket" in args
    args = [a for a in args if a != "--racket"]
    if not args and "RHOMBUS_DIR" not in os.environ:
        sys.exit("pass files to check, or set RHOMBUS_DIR to a Rhombus checkout")
    files = args or sorted(
        os.path.join(root, f)
        for root, _, fs in os.walk(os.environ["RHOMBUS_DIR"])
        for f in fs
        if f.endswith(".rhm")
    )
    files = [os.path.abspath(f) for f in files]
    tmp = tempfile.mkdtemp(dir=os.environ.get("TMPDIR"))
    formatted = {}
    failures = {}
    racket_results = racket_fmt_all(files, tmp) if racket else {}
    for i, f in enumerate(files):
        if racket:
            out = racket_results[f]
            if isinstance(out, str):
                failures[f] = out
                continue
        else:
            code, out, err = fmt(f)
            if code != 0:
                lines = [l for l in err.splitlines() if "ERROR" in l] or [
                    "topiary failed"
                ]
                failures[f] = "topiary: " + lines[0].split("] ", 1)[-1]
                continue
        with open(f, "rb") as h:
            if squash(h.read()) != squash(out):
                failures[f] = "non-whitespace change"
        g = os.path.join(tmp, f"{i}.rhm")
        with open(g, "wb") as h:
            h.write(out)
        formatted[f] = g
    ref = reference(files)
    new = reference(list(formatted.values()))
    skipped = 0
    for f, g in formatted.items():
        if ref[f].startswith("ERROR"):
            skipped += 1
        elif ref[f] != new[g] and f not in failures:
            failures[f] = f"tree changed (see {g})"
    for f, why in failures.items():
        print(f"{os.path.relpath(f)}: {why}")
    print(
        f"{len(files) - len(failures) - skipped} ok, {len(failures)} failed, {skipped} unreadable by reference"
    )


if __name__ == "__main__":
    main()
