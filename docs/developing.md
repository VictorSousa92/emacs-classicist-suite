# Developing

    make check

runs six gates: the per-file compile ratchet, every `declare-function` against
the definition it names, anything defined in more than one file, every symbol
the configuration builder emits, and the SQL — which is extracted from
`diorisis.el` itself and run against a forty-sentence fixture, so what is tested
is the elisp's own queries rather than a copy that could drift from them.

Each gate exists because something got past the others. The compile ratchet is
per-file and records the count each file is allowed, so a new warning fails the
build while the existing ones are not a wall to climb before making a change.
The SQL is extracted from `diorisis.el` itself rather than copied, because a
copy drifts. And the builder check reads every symbol the configuration
generator emits and looks for its definition, because a generator that writes a
name which no longer exists produces a configuration that fails at load with no
clue where it came from.

Six files here are derived from his. Nothing of his is vendored: `diogenes.el`
is a dependency, installed separately, and this suite requires six of its files
at load. What follows is only what was done to the six copies.

### Two were modified in place

| This file | From | His definitions kept | New here |
|---|---|---|---|
| `classicist.el` | `diogenes.el` | 43 | 10 |
| `classicist-browser.el` | `diogenes-browser.el` | 22 | 41 |

**`classicist.el`** is his transient menu, extended so that other files can
add to it. His `diogenes` prefix became `classicist-define-menu`, which builds
the menu from whatever features are awake and runs `classicist-menu-defined-hook`
after — that hook is how `diorisis.el` and `tei-browser.el` add their own
entries without knowing about each other. The rest of what is new here is the
override machinery: `classicist-install-overrides` and its fellows, which point
his commands at this suite's versions where a feature is awake and leave them
alone where it is not.

**`classicist-browser.el`** keeps his Perl conversation and his page-turning
and adds most of what a reader touches: a word looked up from a click, a
citation followed, hyphenation joined across a line break and put back on
leaving, a header line, `goto-passage`, and the per-buffer state his version
kept in globals. Forty-one new definitions against twenty-two of his is the
measure of that — the file is his design carrying a great deal more.

### One became four

`diogenes-perseus.el` was 4,173 lines doing four jobs. It is now four files
that run in one direction, with three `declare-function`s back for what the
dispatcher needs at a keypress:

    variants -> lexicon -> lookup -> morphology

| This file | Lines | What it does |
|---|---|---|
| `classicist-variants.el` | 578 | spellings a dictionary file does not use |
| `classicist-lexicon.el` | 406 | reading a dictionary file |
| `classicist-lookup.el` | 1,363 | the buffer an entry is shown in |
| `classicist-morphology.el` | 1,650 | the morphological analysis |

The cut was made where the dependencies already ran one way. Reading a file
knows nothing of the buffer it will be shown in; the buffer knows nothing of
how a form was analysed. The one place that needed a link back is the
dispatcher — `RET` on a word has to decide between a citation, a dictionary
link and a form, and that decision needs all four — so it declares what it
calls rather than the files requiring each other in a circle.

### Nothing of his was removed

Where a name changed, the old one still works:
`diogenes-browser-compat.el`, `diogenes-lisp-utils-compat.el`,
`classicist-windows-compat.el` and `classicist-obsolete.el` hold obsolete
aliases, so configuration written against `diogenes.el` continues to load and
a reader's old key bindings keep working. Some of his definitions moved to a
different file in the split rather than changing name at all.

Every one of the six carries his copyright in its header alongside any later
one.

[`diogenes-roam`][roam] files a passage note under its author and its work and
keeps an index of them — branch `classicist-roam` for the version that works
with this suite. It wants org-roam, which is why it is separate. Not required;
noticed where present.

[roam]: https://github.com/VictorSousa92/diogenes-roam/tree/classicist-roam
