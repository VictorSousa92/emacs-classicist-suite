# The shadowing rests on filename order

Found by installing on Doom and pressing `C-c d bg`: the buffer came up in
`diogenes-browser-mode`, not `classicist-browser-mode`. So none of the
`texts` feature was active — no header line, no citations beside the text, no
click-to-lookup, no rejoined hyphens — while the suite sat loaded and
apparently fine.

## What the suite does

`classicist.el` **redefines twenty-one of the base's commands under the
base's own names**: seven `diogenes-browse-*`, seven `diogenes-search-*`,
seven `diogenes-dump-*`. Each body calls the suite's own `classicist--*`
worker. So a reader keeps every key and command they know and gets the
suite's behaviour.

That is a good design. It is also, as things stand, a coin toss.

## Why it fails

Shadowing by redefinition works only if the base has defined the name
**first**. In one load that is what `require` is for. Across two packages it
is not:

- both packages autoload all twenty-one names, so
  `classicist-autoloads.el` and `diogenes-autoloads.el` each carry a stub;
- the stub written second wins, and which that is comes down to the order the
  package manager generates them, which is filename order;
- `diogenes` sorts after `classicist`, so the base's stub wins, loads the
  base, and the base's definition is the one that runs.

**And `classicist.el` cannot simply require the base.** `(require 'diogenes)`
fails at load time: the base's own top level calls `diogenes--path`, which
errors with *"diogenes-path is not set!"* before a reader has had a chance to
set it. Tried, and the compile said so.

## Why it looked right

In a long session something had pulled `classicist.el` in last -- a
`M-x classicist-check-base`, an autoloaded command, a `with-eval-after-load`
-- so its definitions were the live ones. A fresh Emacs has no such history.

Which is the third thing today that worked only because of a session's
accumulated state.

## Three ways out

**Wrap the twenty-one in `with-eval-after-load 'diogenes`.** Correct and
smallest: the definitions run when the base has loaded, whichever stub won.
Costs an indentation level on twenty-one `defun`s and makes them invisible to
`check-declare` and to the duplicates gate, which reads top-level forms.

**`advice-add ... :override` for each.** Correct, reversible, and says out
loud that it is overriding something. Twenty-one advices to install and to
remove, and the advice has to be installed after the base loads too -- so it
wants the same `with-eval-after-load`, with more machinery inside it.

**Rename the suite's commands.** `classicist-browse-tlg` and the rest, and
the menu offers those. No shadowing at all, nothing resting on load order,
and the base is left entirely alone -- which is the honest relation between
a package and the one it extends. The cost is that a reader's muscle memory
and any existing configuration point at the base's names, so the suite would
want aliases in the other direction, and `classicist-obsolete.el` already has
the pattern for that.

The third is the cleanest and the largest. The first is what tonight would
reach for; the third is what next week would rather have.

## What to check either way

Whichever is chosen, the test is the one that found it:

    emacs -Q, install from the builder's block, C-c d bg, then M-: major-mode

`classicist-browser-mode` is right. `diogenes-browser-mode` means the
shadowing lost again.

And the same question applies to every name the suite redefines, not only the
browse commands: twenty-one of them, and the search and dump paths have the
same exposure. They have not been tested, because the browser was where a
header line made the difference visible.
