#!/usr/bin/env python3
r"""A cookie on a form that asks something of its own file.

    python3 tools/check-autoloads.py [DIR]

`;;;###autoload' COPIES A FORM INTO THE PACKAGE'S AUTOLOADS, where it runs
before the file it came from has loaded.  So a cookie is safe on a DEFINITION
-- the point of the mechanism, a stub that loads the file when called -- and
safe on a form whose body asks nothing of that file.  It is not safe on
anything else, and the failure is silent as often as it is loud.

FIVE IN ONE DAY, in one package:

    classicist-morphology.el  (classicist--lookup-register-shipped-dictionaries)
                              -- void at the first `doom sync'
    classicist-morphology.el  (classicist--lookup-install-registered-keys),
                              with TWO stacked cookies, which is how the
                              first survived being looked for
    tei-browser.el            (with-eval-after-load 'diogenes
                                (tei--add-to-diogenes-menu))
                              -- void at the first Emacs start after the
                              install worked
    tei-browser.el            (with-eval-after-load 'classicist-browser
                                (when (boundp 'tei-mode-map)
                                  (tei--lend-browser-keys)))
                              -- and this one DID NOT ERROR: `tei-mode-map' is
                              unbound in the autoloads context, so the guard
                              was false and the form quietly did nothing.  A
                              no-op is worse than a void function, which at
                              least says so.

WHAT THE COMPILER CANNOT SEE.  Byte-compiling a file does not run its
top-level forms, and the autoloads file is the package manager's to generate
-- so `make compile' passes and the package breaks on installation.  Every one
of these was found by a reader starting Emacs.

THE CONDITION, stated because getting it wrong is what let the fourth through:
a cookie on a `with-eval-after-load' is fine ONLY IF ITS BODY NEEDS NOTHING.
An earlier scan of mine whitelisted every such form and missed two.
"""
import os
import re
import sys

# A cookie on one of these is the mechanism working as intended.
SAFE = re.compile(
    r"\((cl-)?def(un|macro|var|custom|const|group|face|alias|subst|"
    r"ine-[a-z-]+)\b"
    r"|\(put\b"
    r"|\(add-to-list\b"
    r"|\(autoload\b"
    r"|\(provide\b"
    # A PREFIX IS A DEFINITION, and the pattern above wants `def' at the
    # start: transient-define-prefix begins with `transient-', so a cookie on
    # one read as a call and the body was scanned for dependencies it only
    # touches when invoked -- by which time the file is loaded.  The fourth
    # correction this check has taken from real code.
    r"|\([a-z-]*define-[a-z-]+\b"
)

# A name with a double hyphen is internal to the package that defines it, and
# a cookied form calling one is asking its own file for something.  A name
# this file itself defines is the same fault under a public name.
INTERNAL = re.compile(r"\(([a-z][a-z0-9-]*--[a-z0-9-]+)")
DEFINER = re.compile(r"^\((?:cl-)?def(?:un|macro|subst|ine-[a-z-]+)\s+"
                     r"([^\s()]+)", re.M)

# AND A COOKIED FORM MAY CALL AN AUTOLOADED FUNCTION OF ITS OWN FILE.  That is
# the working pattern: the stub exists before the file loads, calling it loads
# the file, and the form is satisfied.  diogenes-org.el does it three times
# with diogenes-org-setup and diogenes-org-install-keys, both cookied
# themselves -- and this check called all three wrong on its first run.
#
# The five it was written for were not like that: classicist--lookup-register-
# shipped-dictionaries, --install-registered-keys, tei--add-to-diogenes-menu
# and tei--lend-browser-keys are internals with no stub, and four of the five
# proved it by erroring or quietly doing nothing in a running Emacs.
AUTOLOADED = re.compile(
    r"^;;;###autoload\s*$\s*\n(?:^;[^\n]*\n|^\s*\n)*"
    r"^\((?:cl-)?def(?:un|macro|subst|ine-[a-z-]+)\s+([^\s()]+)",
    re.M)


def cookied_forms(lines):
    """Each (cookie-line, form-line) where a cookie precedes a form."""
    for i, line in enumerate(lines):
        if line.strip() != ";;;###autoload":
            continue
        j = i + 1
        while j < len(lines) and (not lines[j].strip()
                                  or lines[j].lstrip().startswith(";")):
            j += 1
        if j < len(lines):
            yield i, j


def body_of(lines, start):
    """The form beginning at START, by counting parens outside strings."""
    depth, out, instr, esc = 0, [], False, False
    for line in lines[start:start + 40]:
        out.append(line)
        for c in line:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif instr:
                if c == '"':
                    instr = False
            elif c == '"':
                instr = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
        if depth <= 0 and len(out) > 0:
            break
    return "\n".join(out)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    trouble = []
    files = sorted(f for f in os.listdir(d) if f.endswith(".el"))
    n = 0
    for name in files:
        path = os.path.join(d, name)
        text = open(path, encoding="utf-8", errors="replace").read()
        lines = text.split("\n")
        # what this file defines, less what it also autoloads
        mine = ({m.group(1) for m in DEFINER.finditer(text)}
                - {m.group(1) for m in AUTOLOADED.finditer(text)})
        for cookie, at in cookied_forms(lines):
            n += 1
            form = lines[at].lstrip()
            if SAFE.match(form):
                continue
            body = body_of(lines, at)
            # AND A NAME GUARDED BY fboundp IS NOT A DEPENDENCY.  That is
            # the whole point of the guard: the form asks whether its file has
            # loaded and does the work itself if not.  diorisis.el is written
            # that way -- (if (fboundp 'diorisis--add-to-diogenes-menu) (call
            # it) (else the append in full)) -- and this called it wrong.
            #
            # A CHECK THAT CANNOT TELL A CORRECT FORM FROM AN ABSENT ONE is
            # worse than none: acting on its first verdict, I deleted two
            # working menu appends and lost the Diorisis and TEI entries from
            # Diogenes' own transient.
            guarded = set(re.findall(r"fboundp '([a-z][a-z0-9-]*)", body))
            stubs = ({m.group(1) for m in AUTOLOADED.finditer(text)}
                     | guarded)
            # THE SUBTRACTION APPLIES TO BOTH HALVES.  It bound only the
            # first, so a name removed as guarded was added back by the
            # second for being defined in this file -- and the check went on
            # flagging a form that was written correctly.  Twice now a patch
            # of mine has gone to one half of this expression.
            asks = sorted(({m.group(1) for m in INTERNAL.finditer(body)}
                           | {w for w in re.findall(
                                  r"\(([a-z][a-z0-9-]+)", body)
                              if w in mine})
                          - stubs)
            if asks:
                trouble.append((name, at + 1, cookie + 1, asks))
            # AND THE OLDER SPELLING TOO.  eval-after-load takes a quoted form
            # where with-eval-after-load takes a body, and this whitelisted only
            # the newer one, so diogenes-org.el line 538 fell through to "a call,
            # not a definition" when it is the same deferred shape.
            elif not re.match(r"\((with-)?eval-after-load\b", form):
                trouble.append((name, at + 1, cookie + 1,
                                ["a call, not a definition"]))

    print(f"   {n} autoload cookies in {len(files)} files")
    if not trouble:
        print("   every one is on a definition, or on a form that needs "
              "nothing")
        return 0

    print(f"\n   TROUBLE  {len(trouble)} cookie(s) on a form that asks "
          f"something of its own file.")
    print("            An autoloaded form runs BEFORE that file has loaded, so")
    print("            the call finds nothing -- loudly if it errors, quietly")
    print("            if a guard turns it into a no-op.")
    for name, at, cookie, asks in trouble:
        print(f"                {name}:{at} (cookie at {cookie})")
        print(f"                   wants {', '.join(asks)}")
    print("\n   Either drop the cookie -- the form runs when the file loads,")
    print("   which is usually when it is wanted -- or write the form so that")
    print("   it asks nothing, naming only autoloaded commands.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
