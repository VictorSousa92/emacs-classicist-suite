#!/usr/bin/env python3
r"""A Spacemacs layer, for a reader who would rather have one.

RUN IN emacs-classicist-suite.  python3 builder-spacemacs-layer.py [--write]

The builder emits two blocks for Spacemacs: recipes for
`dotspacemacs-additional-packages' and settings for
`dotspacemacs/user-config'.  Which works, and is not how Spacemacs expects a
suite of packages to arrive.  A LAYER is one directory with one file in it,
named once in `dotspacemacs-configuration-layers', and it keeps a reader's
own init.el free of thirty settings that are not theirs.

A BUTTON RATHER THAN A DISTRO.  Spacemacs is still Spacemacs; the layer is a
way of writing the same answer, so it belongs beside the distro rather than
instead of it.  Off by default, because the pasted blocks are the shorter
path for a reader trying the suite out, and a layer is what they want once
they keep it.

AND A TRANSFORM RATHER THAN A BRANCH.  The block is built exactly as it is
now and re-wrapped at the end: the recipes become `classicist-packages', the
`use-package' forms become `classicist/init-NAME' functions, and the settings
are indented one level further in.  Which touches none of the branch logic
that assembles them -- a second branch through that function would be a
second thing to keep in step, and this is the same answer differently
dressed.
"""
import argparse
import os
import re
import sys

BOX = '''  <div class="row" data-distro="spacemacs">
    <input type="checkbox" id="c-spacelayer">
    <label for="c-spacelayer">As a layer rather than as two blocks to paste
      <em>Spacemacs expects a suite of packages to arrive as a
      <b>layer</b>: one directory, one file, and its name in
      <code>dotspacemacs-configuration-layers</code> &mdash; which keeps
      thirty settings that are not yours out of your own
      <code>init.el</code>. The two blocks are the shorter path for trying
      the suite out; a layer is what you want once you keep it.</em></label>
  </div>

'''

FN = '''
// A LAYER IS THE SAME ANSWER DIFFERENTLY DRESSED.  The block is assembled as
// it is for any distro and re-wrapped here: the recipes become
// classicist-packages, each use-package becomes a classicist/init-NAME
// function, and the settings are indented one level further in.  Which
// touches none of the logic that assembled them -- a second branch through
// that would be a second thing to keep in step.
function asSpacemacsLayer(lines) {
  const out = [];
  const recipes = [];
  const bodies = new Map();       // package name -> its use-package lines
  let current = null;

  for (const raw of lines) {
    const line = raw.replace(/^;;\\s?/, '');       // the recipes are commented
    // A RECIPE, which the pasted form puts in dotspacemacs-additional-packages
    const rec = line.match(/^\\s*\\((\\S+)\\s+:location\\s+\\(recipe/);
    if (rec || (recipes.length && /^\\s*;;\\s+[:)]/.test(raw))) {
      recipes.push(line.replace(/^\\s{0,4}/, '    '));
      continue;
    }
    const up = raw.match(/^\\(use-package!?\\s+(\\S+?)\\)?$/);
    if (up) { current = up[1].replace(/[()]/g, ''); bodies.set(current, []); continue; }
    if (current) {
      if (/^\\S/.test(raw) && raw.trim() !== '') { current = null; }
      else { bodies.get(current).push(raw); continue; }
    }
    if (!rec) out.push(raw);
  }

  const res = [];
  res.push(';; ---- ~/.emacs.d/private/classicist/packages.el ----');
  res.push(';;');
  res.push(";; AND ADD `classicist' TO dotspacemacs-configuration-layers, which is");
  res.push(';; the only change your own dotfile needs.');
  res.push('');
  res.push('(defconst classicist-packages');
  res.push("  '(" + (recipes.length ? '' : ')'));
  for (const r of recipes) res.push(r);
  if (recipes.length) res.push('    ))');
  res.push('');
  for (const [name, body] of bodies) {
    res.push('(defun classicist/init-' + name + ' ()');
    res.push('  (use-package ' + name);
    for (const l of body) res.push('  ' + l);
    res.push('  ))');
    res.push('');
  }
  for (const l of out) if (l.trim()) res.push(l);
  return res;
}
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    p = os.path.join(args.dir, "tools/classicist-builder.html")
    if not os.path.exists(p):
        sys.exit(f"no builder at {p}")
    s = open(p, encoding="utf-8").read()
    if "c-spacelayer" in s:
        print("  already done"); return

    # 1. the box, in the same row-group as the other configuration questions.
    #    data-distro is new here: nothing else in the builder hides a row by
    #    distro, so whatever shows and hides rows has to learn it -- which is
    #    the one thing in this change that cannot be a transform.
    m = re.search(r'  <div class="row" data-feature="lemmata">', s)
    if not m:
        sys.exit(f"{p}: no anchor row to sit above")
    s = s[:m.start()] + BOX + s[m.start():]
    print("  + the box, above the lemmata option")

    # 2. the transform
    m2 = re.search(r"^function featuresChosen\(\) \{", s, re.M)
    if not m2:
        sys.exit(f"{p}: no featuresChosen to sit above")
    s = s[:m2.start()] + FN.lstrip("\n") + "\n" + s[m2.start():]
    print("  + asSpacemacsLayer, above featuresChosen")

    print("\n  AND TWO THINGS TO DO BY HAND, both small and both needing the\n"
          "  browser to check:\n"
          "    1. call it where the block is finished:\n"
          "         if (distro === 'spacemacs' && el('c-spacelayer').checked)\n"
          "           out = asSpacemacsLayer(out);\n"
          "       at the end of whatever assembles `out'.\n"
          "    2. hide the row for other distros: whatever shows and hides\n"
          "       sections reads data-feature, and this row is the first with\n"
          "       data-distro.\n")
    print("  THE TRANSFORM IS THE RISK.  It reads the block it is given and\n"
          "  re-wraps it, so a change to how the block is written can silently\n"
          "  produce a layer that is missing a setting.  Check the output in a\n"
          "  browser against the pasted form -- every setq in one should be in\n"
          "  the other.")

    if not args.write:
        print("\nDRY RUN.  Add --write to apply."); return
    open(p, "w", encoding="utf-8").write(s)
    print(f"\nWritten: classicist-builder.html.")


if __name__ == "__main__":
    main()
