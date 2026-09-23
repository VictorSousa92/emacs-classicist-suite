#!/usr/bin/env python3
r"""Every symbol the builder emits, checked against what the suite defines.

    python3 check-builder-names.py
    python3 check-builder-names.py --dir . --builder tools/classicist-builder.html

WHY THIS EXISTS.  `tools/classicist-builder.html' is 2,969 lines that
generate a reader's configuration, and NOTHING CHECKED IT.  Every other
change in this package is caught by a gate -- the compile ratchet,
`check-declare', the duplicate check -- and a mistake in the builder is
silent until somebody uses it and gets configuration that does not work.

It had thirty-two stale names when this was written: the whole windows layer
(`split-direction', `window-behaviour', `companion-roles', `focus-*'), the
browser's options and commands, and the lookup's keys.  Every one still
FUNCTIONED, because the renames left obsolete aliases behind -- so the
builder emitted deprecated names, and a reader following it got an init file
that Emacs would complain about the first time each was touched.  Which is
the opposite of what a configuration builder is for.

A generator should generate the real names.  The aliases are for readers who
already have old configuration.

WHAT COUNTS AS A PROBLEM.  A symbol the builder emits and the suite does not
define:

    RENAMED   there is an obsolete alias for it, so the builder is emitting a
              deprecated name that still works.  The fix is the new name.
    UNKNOWN   neither defined nor aliased.  Either a typo, or a name that
              went away, or -- and this has happened -- a feature name or a
              word of prose that only looks like a symbol.

AND THE BASE'S OWN NAMES ARE FINE.  `diogenes-path',
`diogenes-preset-directory' and the dictionary paths are upstream's or the
dictionaries' and are not renamed; they are reported as `the base's' and pass.
"""
import argparse
import os
import re
import sys

DEFINER = re.compile(
    r"^\((?:cl-)?(?:defun|defmacro|defsubst|defcustom|defvar|defvar-local"
    r"|defvar-keymap|defconst|defface|define-derived-mode|define-minor-mode"
    r"|transient-define-prefix|transient-define-argument"
    r"|transient-define-suffix)\s+([^\s()]+)", re.M)

ALIAS = re.compile(r"\(define-obsolete-\w+-alias\s+'(\S+)\s*\n?\s*'(\S+)")

# NAMES THE GENERATOR DEFINES rather than calls.  The Windows block writes a
# `defun' into the configuration it emits -- the bundled-Perl finder -- so the
# name is not expected to exist in this repository or in the base: the
# generated file is where it comes from.
#
# READ OUT OF THE BUILDER AND NOT LISTED BY HAND, so that a defun which goes
# away takes its exception with it.  The note on `classicist-browser' in
# NOT_SYMBOLS below is what a hand-written exception costs: it outlived the
# fact that justified it and hid two dead forms for as long as it sat there.
EMITTED_DEFUN = re.compile(
    r"\(defun\s+((?:diogenes|classicist|tei)[a-z0-9-]*)\s*\(")

# A symbol in the builder's own prose or in a feature position, which is not a
# variable or a command and cannot be checked.  Each was looked at by hand.
NOT_SYMBOLS = {
    "diogenes",                 # the feature, and the base's transient
    # THE FEATURE NAMES, in with-eval-after-load forms the builder writes.
    # diogenes-browser was here and was TRUE when the browser was called
    # that; classicist-browser.el provides only classicist-browser, so the
    # two forms naming the old feature never fired and this exception hid
    # it.  An exception outliving the fact that justified it.
    "classicist-browser",
    "diogenes-presets",         # likewise
    "diogenes-config",          # the builder's own word for a config block
    "classicist",               # the feature
    "classicist-base",          # a git BRANCH on the fork, not a symbol
    "diogenes-roam",            # a package of its own, not in this suite
    # SPACEMACS READS IT AND NOTHING HERE DEFINES IT.  A layer declares its
    # own `LAYER-packages' in the file Spacemacs loads, so the builder writes
    # that name as part of a layer rather than naming a symbol this suite
    # has.  Same for the init functions below, which Spacemacs calls by name.
    "classicist-packages",
    "classicist-roam",           # its branch that works with this suite
    "classicist-suite",         # part of the repository name
                                # emacs-classicist-suite, caught by the regexp
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".")
    ap.add_argument("--builder",
                    default="tools/classicist-builder.html")
    ap.add_argument("--roam", default=os.environ.get("DIOGENES_ROAM", ""),
                    help="where diogenes-roam is; $DIOGENES_ROAM by default")
    ap.add_argument("--base", default=os.environ.get("DIOGENES", ""),
                    help="where the installed base is; $DIOGENES by default")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    b = os.path.join(args.dir, args.builder)
    if not os.path.exists(b):
        print(f"   no {args.builder} -- nothing to check")
        return 0
    html = open(b, encoding="utf-8", errors="replace").read()

    defined, aliased = set(), {}
    for f in sorted(x for x in os.listdir(args.dir) if x.endswith(".el")):
        s = open(os.path.join(args.dir, f), encoding="utf-8",
                 errors="replace").read()
        defined |= {m.group(1) for m in DEFINER.finditer(s)}
        for m in ALIAS.finditer(s):
            aliased[m.group(1)] = m.group(2)

    # AND THE BASE, if it can be found.  Without it, any undefined
    # `diogenes-' name passes as "upstream's" -- which silently excused
    # `diogenes-split-direction', a windows-layer name renamed in this work
    # and not upstream's at all.  A fallback that forgives everything it does
    # not recognise is the shape of gate this project has been removing all
    # along.
    inbase = set()
    if args.base and os.path.isdir(args.base):
        for f in sorted(x for x in os.listdir(args.base)
                        if x.endswith(".el")):
            t = open(os.path.join(args.base, f), encoding="utf-8",
                     errors="replace").read()
            inbase |= {m.group(1) for m in DEFINER.finditer(t)}
    # AND THE PASSAGE-NOTES PACKAGE, which the builder configures and the
    # suite does not carry: thirteen of its names are emitted here, and
    # excusing them by hand would have meant thirteen entries that stop being
    # checked.  A second directory is the honest answer.
    if args.roam and os.path.isdir(args.roam):
        for f in sorted(x for x in os.listdir(args.roam)
                        if x.endswith(".el")):
            t = open(os.path.join(args.roam, f), encoding="utf-8",
                     errors="replace").read()
            inbase |= {m.group(1) for m in DEFINER.finditer(t)}
    elif not args.quiet:
        print("   NO ROAM PACKAGE TO CHECK AGAINST.  Pass --roam or set")
        print("   DIOGENES_ROAM, or its thirteen names read as undefined.")

    if not (args.base and os.path.isdir(args.base)) and not args.quiet:
        print("   NO BASE TO CHECK AGAINST.  Pass --base or set DIOGENES, or\n"
              "   every unrecognised diogenes- name is taken on trust.")

    names = sorted(set(re.findall(r"\b(?:diogenes|classicist|tei)-[a-z0-9-]+",
                                  html)))
    emitted_defuns = set(EMITTED_DEFUN.findall(html))
    renamed, unknown, base, ok, selfdef = [], [], [], [], []
    for n in names:
        if n in NOT_SYMBOLS:
            continue
        if n in emitted_defuns:
            selfdef.append(n)
            continue
        if n in defined:
            ok.append(n)
        elif n in aliased:
            renamed.append((n, aliased[n]))
        elif n in inbase:
            base.append(n)
        elif n.startswith("tei-"):
            # the other repository's: diorisis, the treebank, the TEI reader
            base.append(n)
        elif not inbase and n.startswith("diogenes-"):
            base.append(n)          # taken on trust; see the warning above
        else:
            unknown.append(n)

    if not args.quiet:
        print(f"   the builder names {len(names)} symbols: "
              f"{len(ok)} defined here, {len(base)} the base's or another "
              f"repository's"
              + (f", {len(selfdef)} the generated config's own"
                 if selfdef else ""))
        for n in selfdef:
            print(f"      defined by the emitted config: {n}")

    if renamed:
        print(f"\n   TROUBLE  {len(renamed)} renamed, and the builder emits "
              f"the OLD name.\n"
              f"            They still work, through the obsolete aliases, so "
              f"nothing\n"
              f"            fails -- a reader just gets deprecated names in "
              f"their init file.")
        for a, n in renamed:
            print(f"                {a:44} -> {n}")
    if unknown:
        print(f"\n   TROUBLE  {len(unknown)} neither defined nor aliased.\n"
              f"            A typo, a name that went away, or prose that "
              f"looks like a symbol\n"
              f"            -- if the last, add it to NOT_SYMBOLS with a "
              f"word about why.")
        for n in unknown:
            print(f"                {n}")

    if renamed or unknown:
        print(f"\n   {len(renamed) + len(unknown)} to fix.  A generator "
              f"should generate the real names;\n"
              f"   the aliases are for readers who already have old "
              f"configuration.")
        return 1
    if not args.quiet:
        print("   every symbol the builder emits is a real one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
