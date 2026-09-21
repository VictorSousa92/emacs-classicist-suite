# emacs-classicist-suite: the architecture

Third draft. The first was built on the assumption that `diogenes` is the
foundation; the require graph said otherwise. The second was built on
reading; this one is built on two extractions that were actually done, and it
corrects the second wherever the work contradicted it.

Everything below marked **done** has been byte-compiled by the author and the
numbers are his. Everything else has not.

## What the work established

**The decision holds.** Own two files, take the rest of upstream unmodified,
never `(require 'diogenes)`. Nothing in three extractions and thirteen
upstream patches has argued against it, and the specific obstacle is gone: the
Perl bridge read two variables and called two functions defined in the entry
point that requires it, so it could not be loaded alone.

**And that fix had to be made twice.** Upstream patches 11 and 12 did it on
the upstream branch, and were never ported to the fork -- so for several hours
the claim the whole architecture rests on was true where nobody was working
and false where everybody was. `diogenes-perl-interface.el` reported three
warnings compiled alone upstream and seventeen in the fork, and fourteen of
the difference was exactly this.

Nothing would have surfaced it. Not the per-file baseline, which records the
number without asking why; not the compile logs, which were clean; not the
end-to-end checks, which exercised the window layer and not the bridge. It
came out of reading `diogenes.el` for an unrelated reason.

**So: a fix applied upstream is not a fix applied where you work.** The rule
that follows is to demonstrate the claim rather than infer it --

```fish
emacs -Q --batch -L . \
  --eval "(setq diogenes-path \"/tmp/none\")" \
  --eval "(progn (require 'diogenes-perl-interface)
                 (message \"bridge alone: %S\"
                          (and (boundp 'diogenes-perl-executable)
                               (fboundp 'diogenes--include-server)
                               (fboundp 'diogenes--start-perl)
                               t)))"
```

-- which answers `t`, and is worth keeping beside
`advised: nil / page turn: t` as a check that can be rerun.

**`diogenes-lisp-utils.el` was the exception, and is one 90-line extraction
from being inheritable.** The second draft listed it among the nine to inherit
unmodified and the third said it could not be: forty-four of its forms were
the window layer and fifty-nine more were the fork's own.

It has since lost the window layer (44), the focus commands (8) and 51
obsolete aliases, and what remains is **upstream's twenty-two definitions
exactly, plus seven of the fork's own** — no more, none removed, none changed.

Those seven are one thing:

| | |
|---|---|
| `--loading-bundle` | is a bundle being loaded now |
| `--declared-at-load-p` | was this declared at load time |
| `--path-set-p`, `--source-set-p` | is the path configured |
| `--path-usable-p`, `--source-usable-p` | and does it work |
| `--require-path` | assert one, or explain how to set it |

`--require-path`'s docstring states the purpose: *"a missing one should say
what to set and how rather than failing somewhere downstream."*

**Eighteen files call them** — sixteen dictionary modules plus the lookup
layer plus this file — which makes it the suite's SECOND extension point. The
registry says what a dictionary is; this says whether it is usable and what to
tell the reader if not.

So `classicist-installation.el`, or some such, and then
`diogenes-lisp-utils.el` is upstream's file again and the nine can be
inherited as the plan says.

**Three extractions are out, and every new file compiles clean alone.**

| file | forms | lines | out of |
|---|---|---|---|
| `classicist-windows.el` | 52 | ~1,170 | `diogenes-lisp-utils.el` |
| `classicist-citation.el` | 19 | 384 | `diogenes-browser.el` |
| `classicist-windows-compat.el` | the advice layer | 172 | new |
| `classicist-groups.el` | the customize root | 46 | new |
| `classicist-obsolete.el` | 42 aliases, kept | — | new |
| `diogenes-lisp-utils-compat.el` | 26 aliases, to delete | — | new |
| `diogenes-browser-compat.el` | 2 aliases, to delete | — | new |

`diogenes-browser.el` is down from 1,487 lines to 1,217, and the window layer
gained the eight focus forms a closure walk had wrongly left behind.

**The per-file baseline: 182 at the session's start, 163 at its end**, with
every `classicist-*` file at zero. `diogenes-perseus.el` at 43 and
`diogenes-browser.el` at 25 are forty-two per cent of what remains, and those
are the two files the suite owns outright -- a consistent picture rather than a
coincidence. `diogenes-search.el` and `diogenes-corpora.el` at 17 each are
files the plan inherits unmodified, and worth a look: if their warnings are
the same upward-reference pattern the bridge had, there are more upstream
patches in them.

## Method, and this is the part the second draft lacked

Four rules, each of which cost time before it was written down.

### Transitive closure is the wrong tool for finding a module boundary

It answers *what could this reach*, and the question is *what does this
touch*. In a tightly-woven file one action-shaped function at the edge pulls
in the world:

- seeding the window closure with `diogenes--focus-role` gave 747 of a
  39-file package, because it calls the `diogenes-goto-*` commands, which
  reach every dictionary module;
- seeding the citation closure with `diogenes-open-passage` gave 793, because
  it calls `diogenes--browse-work`, which reaches the browser, then perseus,
  then everything;
- narrowing to what looked like pure data still gave 792, because
  `diogenes-browser-reference` mentions `diogenes-browse-tlg`.

**Ask instead for the direct edge, form by form.** One query, tabulated:

```
citation form                          calls into the rest of the browser
classicist-citation-to-key             (nothing)
classicist--browser-corpus             (nothing)
...
diogenes-browser-reference             diogenes-browser-mode
diogenes-open-passage                  diogenes--browse-work
```

Seventeen of nineteen touched nothing. The boundary was visible immediately,
and the two exceptions were the interesting part rather than noise.

### Quoted data is not a reference

Both blown-up closures were partly this. `(diogenes-browser-mode . browser)`
in a role table looks like a reference and is a symbol in an alist, matched
against `major-mode` at run time. The mode needn't be defined for the file to
compile. A closure walker that follows it leaves the module and never comes
back.

### A file's warning count is only trustworthy compiled alone

`batch-byte-compile` compiles alphabetically in one Emacs, and a `require`
loads the required file *as source*, which defines everything in it before
the compiler reaches it. So one file can silence another's warnings:

- upstream's `diogenes-forms.el` required `diogenes-perseus`, and being
  compiled first it loaded perseus and hid four `let`-nested functions that
  the compiler had never known about. Patch 5 removed that require and the
  warnings appeared, looking for all the world like a regression;
- `classicist-windows-compat.el` sorts before `classicist-windows.el`, loads
  it, and hid two forward references to options defined below their readers;
- `classicist-citation.el` sorts first of all, and hid fourteen references to
  `diogenes-perl-min-version` and `diogenes-perl-executable` — the very bug
  patches 11 and 12 then fixed.

Hence **the per-file baseline**, which does not drift as the require graph
changes, and which is the only count worth comparing against:

```fish
for f in *.el
    printf "%s %s\n" (emacs -Q --batch -L . -f batch-byte-compile $f 2>&1 \
                      | grep -c Warning) $f
end | sort -rn > per-file-baseline.txt
```

**182 warnings across 19 files** at the time of writing, saved beside the
repository. `diogenes-perseus.el` at 45 and `diogenes-browser.el` at 28 are
forty per cent of it, and those are the two files the suite owns outright —
which is a consistent picture rather than a coincidence.

### Read the function, do not list the functions

`classicist-windows-compat.el` decides whether to advise each base function
by reading its body:

```elisp
(defun classicist-windows-compat--needed-p (fn)
  (and (fboundp fn)
       (let ((body (prin1-to-string (indirect-function fn))))
         (and (string-match-p "pop-to-buffer\\|switch-to-buffer" body)
              (not (string-match-p "classicist-display-buffer" body))))))
```

Against the fork this should report nothing, and it reported
`diogenes--debug-perl` — a `switch-to-buffer` the extraction had missed,
after the extraction had been checked three ways. The second draft's
capability section recommended `fboundp` and version numbers; those would not
have found it. A probe that reads the body also needs no maintenance when a
base is halfway between two states, which is the case the whole compat layer
exists for.

The one place a version cannot be read is the Perl script, and there the
probe reads the script:

```elisp
(defun classicist-base-page-turn-p ()
  (and (fboundp 'diogenes--browse-interactively-script)
       (let ((script (ignore-errors
                       (diogenes--browse-interactively-script
                        '(:type "tlg") '("0086" "010")))))
         (and (stringp script)
              (string-match-p "/\\^F\\$/" script)
              t))))
```

`and ... t` because `string-match-p` answers with a position, and a predicate
should answer `t`. Reported `page turn: 1820` until it did.

## Mechanics that bit, and the rules that follow

**Aliases go in a file of their own.** An extraction leaves
`define-obsolete-*-alias` forms behind, and then the call-site rename is a
`sed` over the same files. Twice a blanket `sed` turned every alias into a
symbol aliased to itself — `(define-obsolete-function-alias 'classicist-x
'classicist-x)` — which is an infinite loop on first call and not a warning.
Bounding the `sed` above the alias block works and is fragile. **The
extraction scripts should write the aliases to `<file>-compat.el`**, and then
the situation cannot arise. Not yet done; the `diorisis-` and `treebank-`
renames will have far more than nineteen aliases.

**Commit the extraction before touching call sites.** They are two changes,
and in one unstaged tree a single `git checkout` undoes the wrong half. It
did.

**Variable aliases are silent.** `define-obsolete-variable-alias` warns on
nothing when a variable is merely read. The citation rename had fifty real
references and eleven warnings: the five buffer-locals were invisible, 24 of
them in `diogenes-browser.el` alone. **For any rename touching buffer-locals
or defcustoms, `grep` is the worklist and the compiler is the confirmation.**

**Count parens with a scanner, not with `find("\n(")`.** Several docstrings
hold examples beginning at column zero — `diogenes-role-regexps` has an
`add-to-list` — so a form terminated at the next newline-paren is cut inside
its docstring and the tail left behind. Parens still balance; the file
compiles as something else. `check-elisp-balance.py` caught it, which is the
argument for running it after every scripted edit.

**Only wrap lines inside docstrings.** A flush-left `(require 'x) ; comment`
looks exactly like long prose, and cutting it at column 80 leaves a bare
symbol at top level.

**An alias must be declared before its referent.** `define-obsolete-variable-alias`
placed after the `defcustom` it points at draws a warning and gets the two
out of step.

## The load graph

```
classicist.el                        ← the entry point, replaces diogenes.el
├── diogenes-perl-interface          upstream + patches 11-13; stands alone
├── diogenes-lisp-utils, -utils      [PENDING] a reading pass first
├── diogenes-user-interface          upstream
├── diogenes-corpora                 upstream            (17 warnings)
├── diogenes-lemmata                 upstream, from patch 5
├── diogenes-forms, -search          upstream            (5, 17)
├── diogenes-archive, -legacy        upstream
│
├── classicist-windows               done, clean
├── classicist-windows-compat        done, clean
├── classicist-citation              done, clean
├── classicist-browser               [PENDING] 1,217 lines, 28 warnings
├── classicist-variants              [PENDING] ┐ the four perseus
├── classicist-lexicon               [PENDING] │ successors
├── classicist-lookup                [PENDING] │
├── classicist-morphology            [PENDING] ┘
│
├── the dictionaries                 bailly, gaffiot, georges, pape, dge,
│                                    tgl, tll, montanari, bdag, passow,
│                                    cambridge, + pdf drivers
├── diorisis-*                       [PENDING] was tei-diorisis
├── treebank-*                       [PENDING] was tei-diorisis
├── tei-*                            genuinely TEI; keeps its prefix
└── diogenes-org, diogenes-roam
```

`diogenes--path` is the one remaining upward reference from the Perl bridge,
and it should stay: it reads `diogenes-path`, the single setting a reader must
provide, and where the installation lives is the entry point's business. One
`declare-function` says so.

## The roles, now open

`classicist-role-regexps` was already a defcustom; `classicist-role-modes`
was a defconst and now is not, so a module registers its own modes as well as
its own names. `classicist-display-actions` holds an action for any role,
consulted after the four per-role options so that nobody's existing setting
changes.

```elisp
(add-to-list 'classicist-role-modes '(diorisis-results-mode . diorisis-results))
(add-to-list 'classicist-window-behaviour '(diorisis-results . split))
```

Flat role symbols, not a family-and-kind pair. Two-level roles would let a
reader place every search-like thing in one line where flat roles need three;
it is real machinery in `classicist--behaviour-for` and nobody wants it yet.

## What the citation extraction changed for the TEI packages

`tei-browser.el` and `tei-diorisis.el` depended on `diogenes-browser.el` —
1,487 lines, a Perl process, a stream filter — to ask how a passage is named.
Their real dependency is `classicist-citation.el`, 384 lines of conversion.

They still call the old names, which work through the aliases. When they are
converted they need `(require 'classicist-citation)` and the same rename, and
then `diogenes-open-passage` behind `fboundp` is their only browser
dependency — which is the right shape, because opening a passage in the
browser is browser work.

Two things to know about that module:

**It is not Perl-free**, which the second draft would have assumed.
`classicist--browser-labels` falls back to `diogenes--get-work-labels` when
the buffer-local is unset. `tei-browser.el` and `tei-diorisis.el` set that
local themselves and never take the fallback; a reader should not have to
learn that from a stack trace, so it is declared and documented.

**Four outward calls are declared, not required** — `--get-work-labels`,
`--select-passage`, `diogenes-abbreviations`, `diogenes-browse-tlg` — because
`diogenes-browser.el` requires this file and `diogenes.el` requires that, so
requiring back closes a circle.

## The upstream series: fourteen commits

Ready on a branch, unpushed. Suggested grouping, because thirteen at once is
not a review:

| branch | commits | pitch |
|---|---|---|
| `fixes-that-error` | `y-or-n-q`, `copy-list`, `uft8-to-beta`, `--select-passage`, `format` | five things that go wrong when reached. Lead with these |
| `fixes-cosmetic` | obsolete macros, `require-match` | |
| `licence-notices` | the GPL boilerplate | settles GPL-3.0-only versus -or-later |
| `loading-in-pieces` | `diogenes-lemmata`, the Perl variables, the `-I` flags, the two declaration commits | one observation in five commits |
| `browser-page-turn` | `F` and `B` | |

`git cherry-pick` onto fresh branches off `upstream/main` splits a chain;
`git am` cannot, which is how the first attempt failed.

**Four of the thirteen are one observation**: things defined in `diogenes.el`
and read from the files it requires. `--perseus-path`, the two Perl
variables, the two `-I` builders, `--get-info`. That is the framing for the
pull request, because it is a structural point about loading the package in
pieces rather than four unrelated tidyings.

**Five are genuine bugs**, and every one was found by a compiler or a checker
rather than by reading:

- `y-or-n-q` — a prompt that errors instead of asking
- `copy-list`, four times — not an Emacs function
- `--select-passage` — an empty level string kills the Perl process, exit
  255, leaving a browser buffer that looks well and can do nothing
- `uft8-to-beta` — two letters transposed, so the `STR` branch of
  `diogenes-utf8-to-beta` has never run; only its interactive paths work,
  which is why nobody noticed. Its docstring described the other direction.
- `format` given two arguments for one field — `(or name)` with the default
  outside it, so renaming an unnamed corpus prompted `Rename nil to:`. Line
  175 of the same file gets it right.

Still unfixed and worth telling him: `diogenes-perseus-action` is defined
twice in `diogenes-perseus.el`, and the second silently wins.

## Perseus, done: four files where there was one

Four files, not three, and a stack rather than a cycle. The cross-reference
graph of the 133 new definitions:

```
caller \ callee   variants  lexicon  lookup  morph
variants                10        2       0      0
lexicon                  2        3       8      0
lookup                   3        4      62      7
morph                   12        4      10     35
```

**DONE.** 4,173 lines became four files, one direction, with three
`declare-function`s back for what the dispatcher calls at a keypress.

| | forms | lines | warnings |
|---|---|---|---|
| `classicist-variants` | 28 | 578 | 0 |
| `classicist-lexicon` | 28 | 406 | 0 |
| `classicist-lookup` | 71 | 1,363 | 5 |
| `classicist-morphology` | 66 | 1,650 | 12 |

```
variants -> lexicon -> lookup -> morphology
```

What follows is what each cut cost, because the design was right in shape and
wrong in detail every single time, and the details are the record worth
keeping.

### `variants`: the claim was checked twice and wrong twice

**28 forms, 578 lines, and no outward dependencies within perseus** — which
was the design's claim, and I corrected the document AWAY from it before
correcting it back.

The first closure reported `--latin-assimilations` calling
`--assimilated-offset`, which is a sentence in its docstring: "Nothing is
decided here -- every candidate is offered, and
`diogenes--assimilated-offset' keeps whichever the dictionary actually has."
Eleventh docstring read as code in a day, from a script that strips comments
and not strings — lesson one, written in this very document and not applied.

**And "no outward dependencies" was true only of perseus.** The module reaches
`--strip-diacritics` in `diogenes-utils`, `--ascii-alpha-only` in
`diogenes-lisp-utils`, and `ucs-normalize-NFD-string` in Emacs. Two closures
and the forms checker's "every function it calls, it defines" all agreed there
were none, because every one of them reads a single file. **Only compiling the
file alone found it**, which is what the ratchet does and nothing else in the
toolchain did.

### `lexicon`: nine-tenths private, and a bug the comment predicted

**28 forms, 406 lines, 27 of them private** — the shape of a layer nobody
needs to reach into: you ask it for an entry and it reads the file.

**The sense stack was broken.** A `let` binds `--dict-sense-stack` to nil with
the comment *"ONE ENTRY, ONE STACK. Otherwise the senses of the last entry
shown would still be in force at the top of the next"* — and its `defvar` sat
four hundred lines below. Under lexical binding a `let` on a symbol not yet
declared special binds it LEXICALLY, so `--dict-process-elt` read the global
and never saw the reset. **The fault the comment warns of is the one that was
happening.**

**And six dictionaries broke in a way `make check` could not see.** Bailly,
DGE, Gaffiot, Georges, Pape and the old one call `--binary-search`,
`--xml-key-fn` and the two sort functions, which are private and so got no
aliases. Every one of those files compiled clean, because their
`declare-function` forms told the compiler the functions existed. Only
`check-declare` knew.

### `lookup`: the one with consumers

**71 names in 69 top-level forms**, 23 public, and 25 files following the
rename. The registry among them: `classicist-lookup-register-dictionary` is
called by fifteen dictionary modules and is the suite's extension point.

**Two closures move whole.** A `defun` inside a `let` is a closure over that
binding, so the unit of movement is the top-level form and not the definition.
Cutting one out leaves the `let` unbalanced. It is also why this file declares
`--lookup-insert-xml`, which it defines itself, and why the morphology declares
five things it used to declare for its own closures.

**Six more variables defined.** `--lookup-buffer`, `--lookup-entry-id`,
`--lookup-bufstart`, `--lookup-bufend`, `--lookup-file` and `--lookup-lang`
were `setq`'d and declared nowhere — so five of them kept the old prefix
through the rename, because a cut renames what a file DEFINES and these were
defined nowhere. The warnings came out in two prefixes, which is the fault
made visible.

### `morphology`: a rename, and no shim needed

Sixteen `with-eval-after-load 'diogenes-perseus` forms in fifteen dictionary
modules waited on that feature for the REGISTRY — which is
`classicist-lookup`'s now. **Repointing them first, as a correction rather
than a rename**, meant nothing was left waiting and the rename needed no shim
`provide`. The browser rename needed one because two repositories could not
change together.

### And the section headers lied a fourth time

Fifty-nine of `lookup`'s seventy-one sit under `;;; ... in a dedicated NXML
buffer`, which names a BUFFER and not a layer. The document's own matrix put
them in lookup and the header put them on their own; the matrix was right.
Fourth section header in this project to mislead, after two in
`tei-diorisis.el` and one in `diogenes-browser.el`.

**Eight edges broke the stack until they were read.** `lookup -> morphology`
came to eight, which no stack allows. Six were one function —
`--lookup-lemma-of`, which is named `lookup-` and does nothing but parse, so
it went to the morphology. The other two were `diogenes-lookup-keys` naming
commands in a TABLE: symbols in data, matched at a keypress, which is not a
call.

The stack that came out of it:

```
variants → lexicon → lookup → morphology
```

one direction, no `declare-function` needed between them. `morphology`'s
entry commands get `;;;###autoload`, so a reader who opens Bailly loads three
files and a reader who presses `RET` on a word gets the fourth.

Split directly into four, not via an intermediate `-ext.el`: the point of
splitting is to find out whether the lexica can load without the morphology,
and a single intermediate file makes every cross-reference internal, so the
compiler proves nothing.

### Sixteen variables created by assignment

`setq` on a symbol nothing has declared special makes a global on first use,
so the code works and the compiler says `assignment to free variable`.
**Sixteen of them in this package**, every one found because something made it
visible — a cut, a rename, or a compile log somebody finally read.

**Three idioms produce them**, and the first is much the commonest:

| idiom | where |
|---|---|
| `make-local-variable` in a mode body, and no `defvar` | the browser ×2, the form buffer ×2, the search buffer ×3, the corpus editor ×1 |
| nothing at all, just `setq` | the browser ×1, the lookup buffer ×5 |
| a `defvar` whose docstring claims buffer-local | `--lookup-lang`, `--lookup-headword` |

**`make-local-variable` looks like a declaration and is not.** It makes a
binding buffer-local without telling the compiler the symbol is special, so
`setq` still creates a global and the compiler still warns. Five files reached
for it. `defvar-local` does both jobs at once, at definition rather than at
mode start, and the `make-local-variable` calls become redundant.

**One was defined twice, in two files, differently.**
`--lookup-headword` was `defvar-local` in the lexicon and a plain `defvar` in
perseus, both docstrings claiming buffer-local. Which won depended on load
order. Nine other files declared it by hand with comments saying where they
thought it was. That is `tools/check-elisp-duplicates.py` and a gate now,
because nothing else looks: the forms checker reads one file, the compiler
takes whichever loaded last, `check-declare` reads declarations, and a
reference walker asks who CALLS a name.

### And a `boundp` guard that goes vacuous

The corpus editor asked

```elisp
(unless (boundp 'diogenes--corpus-edit-callback)
  (error "I do not know what to do, since the continuation function is not
          properly defined!"))
```

and once the variable is `defvar-local` that `boundp` is always true, so the
check can never fire — a guard that reads as protective and is not. It tests
the value now, which is what its error message describes.

**The distinction matters**, because there are eight other `boundp` guards on
variables defined during this work and all eight are fine:

| | |
|---|---|
| a `boundp` guard paired with a value test | survives the variable being defined |
| a `boundp` guard alone | becomes a check that cannot fail |

`classicist--browser-buffer-p` asks `boundp` on three variables *and then*
their values, so defining them made three clauses vacuous and left the
predicate sound. Its docstring even says why the `boundp`s were there: an
older upstream had no such variables. Seven of the nine are that kind; one was
not, and the whole class had been called harmless.

### Definition order, seven times

| file | what |
|---|---|
| `classicist-windows.el` | 19 options below their readers |
| `classicist-browser.el` | the state cluster, 400 lines below |
| `classicist-lookup.el` | six variables, and one still prefixed `diogenes--` |
| `classicist-lexicon.el` | the sense stack |
| `diogenes-forms.el` | two |
| `diogenes-search.el` | three |
| `diogenes-tgl.el` | four constants, read 305, 749 and 1,124 lines above their definitions |

The last is what a file grown by **appending** looks like: each new constant
went at the end regardless of where it was wanted.

**And it is not always cosmetic.** In the lexicon a `let` bound
`--dict-sense-stack` to nil with the comment *"ONE ENTRY, ONE STACK.
Otherwise the senses of the last entry shown would still be in force at the
top of the next"* — and its `defvar` sat four hundred lines below. Under
lexical binding a `let` on a symbol not yet declared special binds it
LEXICALLY, so the function called inside read the global and never saw the
reset. The fault the comment warns of is the one that was happening.

### Keyword functions, and `t`

Three functions in this package take `&key` arguments and no
`declare-function` can describe them honestly:
`diogenes-lookup-register-dictionary` (fourteen keywords, declared in fifteen
dictionary modules and flagged in every one), `classicist-display-buffer`, and
`org-roam-capture-`. The last is `(defun ... (&key ...))` rather than a
`cl-defun`, so Emacs counts seven positional slots and objects to the ten
arguments five keywords make — the call being correct as org-roam intends it.

`t` in place of the arglist means *defined there, arglist unspecified*, and is
the only true thing that can be said.

## Diorisis and the treebank: two packages, stacked

The reading pass is done. `tei-diorisis.el` is 9,013 lines and **two**
packages, not three: `tei-browser.el` was always a separate file and is not
touched by any of this.

| | defs | lines |
|---|---|---|
| `diorisis-` — database, query, results, reading, saved searches | 230 | 4,250 |
| `treebank-` — annotation, trees, the viewer's server, the workbook | 156 | 3,732 |

```
treebank -> diorisis     96 edges
diorisis -> treebank     13
```

**The counts moved three times**, and each time because the definer list
grew: 364 without the transients, 386 with them and `defvar-keymap`, and the
back-edges 6 then 7 then 13 as the corrections list caught up. The last
figure is from a run whose definer list was checked against the file's own
top-level forms, and the walker reports nothing undeclared in either file, so
it is the first one worth trusting.

**They stack.** `treebank-` annotates Diorisis sentences: it calls `--select`
six times, `--hit-at` four, `--levels` three, plus `--db`, `read-lemma` and
`--work-number`. That is not incidental coupling, it is what a treebank is.

The single edge back is `--insert-hit` asking `annotation-for` whether a hit
has an annotation, so it can mark it. An `fboundp` guard, and then `diorisis-`
loads and works with no treebank at all and gains the marking when there is
one. The same pattern `tei-diorisis.el` already uses around
`diogenes-open-passage`, and worth writing as a check the way
`advised: nil / page turn: t` is: load `diorisis-` alone, search, and the hit
list should come up with no annotation column.

### No aliases, and this is the one place that is right

**386 symbols renamed outright** — 174 public, 56 of them defcustoms. Against
19 for the citation layer and 51 for the windows, where aliases were plainly
owed.

Here they are not. Nothing outside this repository calls these names: the
author's own config mentions not one of them, and the only other holder is the
README, edited in the same commit. A package with no external consumers and no
settings in the wild gets exactly one chance at a clean break, and it ends the
moment somebody else installs it.

Which also makes this split simpler than the citation one: no compat files, no
alias blocks, no bounded seds, no self-aliasing hazard.

**The on-disk names are already right** — `diorisis-treebank/`,
`diorisis-workbooks/`, `diorisis-searches/`, `diorisis-lemmata.tsv`,
`annotations.tsv`. No saved tree, search or workbook moves.

### The shared vocabulary folds in rather than becoming a module

The ALDT morphology vocabulary — `--feature-glosses`, `--feature-groups`,
`--features-left`, `--uninflected-features`, `--inflectional-group-p`,
`relations`, `--postag-places`, `--postag-places-latin`, `postag-style`,
`language` — is wanted by both: the query needs it to build morphology WHERE
clauses, the annotation to emit postags.

It looks like a third module and should not be one. Two hundred lines existing
so that one of its two consumers can avoid loading the other buys nothing,
because nobody wants the treebank without the corpus. **The test:** would
anyone ever require it alone? `classicist-citation` passes that test —
`tei-browser` and `diogenes-org` genuinely want citations without a browser.
This does not.

### Eleven corrections, because the headings lie

Third file where this has happened, after "Browser process filter" holding the
whole citation layer and "Let the user handle corrupt XML" holding 53
definitions about anything else.

| under the heading | belongs to | why |
|---|---|---|
| `--morph-clauses` | diorisis | builds WHERE clauses |
| `--places` | diorisis | four query functions call it |
| `read-morphology` | diorisis | reads a query spec |
| `--postag-places`, `-latin`, `language`, `postag-style`, `relations`, `--feature-glosses`, `--feature-groups`, `--features-left` | diorisis | the shared vocabulary |
| `annotation-for` | treebank, and stays | the one edge back |

And two whole sections are mislabelled. **`;;;; BUILDING ONE`** builds a
*query* — `query-add`, `query-run`, `query-save`, `what-is-there` — and follows
"READING A DIORISIS TEXT", which is what made it look like a treebank.
**`;;;; SEARCHES KEPT, AND ANNOTATIONS FOUND AGAIN`** holds only saved
searches and touches no annotation at all.

### The count was wrong three times, and each time the regexp was short

**364, then 386, and the back-edges 6 then 7 then 13.**
`transient-define-prefix` and `-argument` were missing from the definer
regexp -- fourteen forms, and two names in the README looked undefined as a
result. Then `defvar-keymap` was missing -- eight mode maps, and those held
the keymap seam, which no earlier count could see. The transients held two
more seams after that.

Every one of those three counts was reported with confidence. The last is the
first to have been checked against the file's own top-level forms, and it is
the only one worth quoting.

**Check a definer regexp against the file's own top-level forms** before
believing its total:

```python
pat = re.compile(r"^\((?!;)", re.M)          # every top-level form
# anything matching this and NOT matching DEFINER is either interstitial
# code or a definer you have forgotten
```

That check also turned up four lines at 4457, 4458, 4851 and 4922 that begin
with `(` at column zero and are docstring prose about postags. Sixth reading
of prose as code, and the reason a paren-counting scanner is needed rather
than line matching.

### The twenty-seven forms that define nothing, placed

The partition and the rename are mechanical; these are not. Each is a
judgement, and they are written down here so that the writing need not make
them again.

| form | goes to | why |
|---|---|---|
| `cl-lib`, `seq`, `subr-x` | both | |
| `transient`, `text-property-search` | both | |
| `ucs-normalize` | diorisis | `NFD` folding, in the beta-code conversion |
| `xml`, `svg`, `color`, `filenotify` | **treebank** | the corpus comes from SQL; it is the ALDT and CoNLL-U writing that parses XML, the tree that is drawn in SVG, and the viewer's directory that is watched |
| `--beta-to-utf8`, `--utf8-to-beta`, `open-passage`, `lookup-greek`, `parse-and-lookup-greek`, `--display-buffer` | diorisis | six of the seven foreign declarations |
| `--parse-word` | **treebank** | the seventh: filling a word's morphology from Diogenes |
| `defgroup tei-diorisis` | becomes two | `diorisis` and `treebank`, each under the same parent |
| the two `add-to-list` completion registrations | diorisis | the lemma completion style and its category |
| `with-eval-after-load 'diogenes` (the lemma prompts) | diorisis | |
| `with-eval-after-load 'evil` | diorisis | the option is diorisis', and the treebank adds its mode |
| `with-eval-after-load 'diogenes` (the menu) | **splits** | `bD` for a Diorisis text, `sa` for the trees |
| `with-eval-after-load 'diogenes-browser` | diorisis | the mouse keys in the hit list |
| `provide` | becomes two | |

**`xml` being the treebank's was the surprise**, and the reason is worth
stating properly: **no elisp in this repository parses a corpus's XML.**
`tei-browser.el` requires only `seq` — the TEI is read by `tei-index.py` and
`tei-read.py`, and the elisp reads what Python wrote. The Diorisis corpus is
likewise XML on disk and SQLite by the time elisp sees it.

So the XML in `tei-diorisis.el` is all on the way OUT: a dependency tree
written as ALDT for Arethusa. Which is why `(require 'xml)` goes with the
treebank, along with `svg` for drawing the tree, `color` for keeping its
labels legible, and `filenotify` for noticing when the viewer has saved.

The corpora arrive as XML; the elisp never sees it.

### The five seams, with their precedents

| seam | mechanism | the file already does this |
|---|---|---|
| `--insert-hit` → `annotation-for` | **already guarded** by `ignore-errors`, which swallows a void-function too | |
| `results-mode-map`, six keys | `treebank-install-results-keys` | `install-mouse-keys`, retried at every mode start |
| `evil-emacs-state-modes` → `tree-mode` | `add-to-list` | `classicist-role-modes` |
| `diorisis-search`, two rows | `transient-append-suffix` after `"D"` | five existing appends |
| the Diogenes menu, `sa` | the function splits in two | itself |

**The six keys, which planning got wrong:** `T` export-sentence, `A` annotate,
`c` collect, `C` collect-all, `b` workbook, `C-c C-t` export-hits. From memory
I had `w` for workbook and `E` for export-hits — and `w` is `open-work`, the
corpus reader's. Generated from that, the treebank would have taken a key from
the reader and bound another to nothing, and **`make check` would have passed**,
because a keymap holding a wrong symbol compiles perfectly.

### Five seams, and two of them nobody had seen

| seam | mechanism | precedent already in the file |
|---|---|---|
| `--insert-hit` → `annotation-for` | `fboundp` | the guard around `diogenes-open-passage` |
| `results-mode-map`, six keys | `treebank-install-results-keys` | `install-mouse-keys` |
| `evil-emacs-state-modes` → `tree-mode` | `add-to-list` | `classicist-role-modes` |
| **`diorisis-search`, two rows** | `transient-append-suffix` after `"D"` | the five existing appends |
| **the Diogenes menu, the `sa` entry** | the function splits in two | itself |

**The first is already done.** The call reads

```elisp
(when (ignore-errors (tei-diorisis-annotation-for hit))
  (insert (propertize "  [tree]" 'face 'tei-diorisis-form-face)))
```

and `ignore-errors` swallows a void-function as readily as anything else, so
`diorisis-` degrades correctly with no treebank present today. An `fboundp`
would be clearer -- it names which absence is expected instead of catching
all of them -- but it is not a fix.

**The fourth and fifth were invisible until the definer list included
transients.** `diorisis-search` carries two treebank rows in its "And then"
group --

```elisp
("L" "Annotated trees"                     tei-diorisis-annotations-menu)
("b" "The workbook of collected sentences" tei-diorisis-workbook)
```

-- between `"D"` and `"c"`, so `treebank-` appends them back after `"D"`, a
key that stays in `diorisis-`. And `--add-to-diogenes-menu` appends `sa` for
the trees, hanging from Diogenes' own `sm` rather than from `sD`, for the
reason its comment gives: `sD` may not be there. So that function splits in
two, each package appending its own entry.

### And the key table was wrong, which is the argument

Planning the seam from memory gave six keys, and two were wrong:

| key | what it really is | what the plan said |
|---|---|---|
| `T` | `export-sentence` | ✓ |
| `A` | `annotate` | ✓ |
| `c` | `collect` | ✓ |
| `C` | `collect-all` | ✓ |
| `b` | `workbook` | said `w` |
| `C-c C-t` | `export-hits` | said `E` |

`w` is `open-work`, which is the CORPUS READER'S. Generated from the plan,
the treebank would have taken a key from the reader and bound `E` to nothing
-- and both would have passed `make check`, because a keymap holding a wrong
symbol compiles perfectly.

**Which is the shape of failure this work produces: not the kind a gate
catches.** The partition and the rename are mechanical and can be scripted.
The five seams want the buffer open and a person reading each one.

### The transients do not straddle

**The evil options.** `evil-emacs-state-modes` lists four modes, three from
diorisis and `tree-mode` from the treebank. The option goes to `diorisis-` and
`treebank-` extends it with `add-to-list` — the pattern
`classicist-role-modes` settled: one package owns the table, another adds to
it.

**The results keymap, and this is the real one.**
`diorisis-results-mode-map` binds six treebank commands: `export-sentence`,
`export-hits`, `collect-all`, `annotate`, `workbook`, `collect`. The results
buffer has keys for annotating what it found, which is not a misfiling --
`export-sentence` is defined at line 4674 inside `;;;; TOWARDS A TREEBANK` --
but the two packages genuinely meeting at a keymap.

`defvar-keymap` builds the map at load, and keymaps hold symbols rather than
functions, so it compiles and loads either way. But pressing `A` in a results
buffer with no treebank gives a void-function rather than a message.

**The file already has the answer twice over.**
`tei-diorisis-install-mouse-keys` iterates two maps, reads an option, guards
each cell, and is retried at every mode start -- its docstring records why:
the option it follows is defined by a file the reader may not have loaded, so
the first attempt found the variable unbound and the gestures were silently
absent. `diogenes-lookup-keys` does the same for the dictionaries.

So: `diorisis-results-mode-map` stops naming the six, a `treebank-results-keys`
option holds them, and `treebank-install-results-keys` -- modelled line for
line on `install-mouse-keys` -- puts them in when the treebank loads and at
every mode start.

**Fourteen transients, and they divide on the line number.** Eleven
`--arg-*` arguments (3313–3410) and `search` (3438) are diorisis; `tree-menu`
(7421) and `annotations-menu` (8704) are treebank. The README's "under SEARCH
rather than" describes where `annotations-menu` is *reached from*, not where it
is defined — so `treebank-` appends it to `diorisis-search`.

`transient-define-prefix|argument` is not matched by the obvious definer
regexp, so the first count of 364 was short by fourteen and two README names
looked undefined. Worth adding to any such regexp before trusting its total.

**The append pattern is already right and used five times**, at lines 8914 to
9003, each guarded with `fboundp` and asking `transient-get-suffix` first. The
comment at 8935 records why: asked twice it appends twice, and that showed as
duplicate menu lines. The file already knows how; the split needs only to do
it twice.

### Computed names: the rule, and the refinement

**Before renaming, grep for `intern`.** A rename is textual and `intern` is
not, and this is the only fault of the day that would have broken silently at
run time rather than noisily in analysis.

```fish
grep -rn "intern (format\|intern (concat\|intern-soft\|make-symbol" *.el
```

Eight sites in the fork, and the rule that sorts them is narrower than the
grep: **a computed name is dangerous when something else must produce the
same string independently.**

- `diogenes-browser.el:924` was dangerous. A remap table paired an evil
  command with a bare suffix and put `diogenes-browser-` on at load, so the
  definitions would have been renamed and the assembly would not. The arrows
  would have stopped paging, with no error and nothing in the compile. Fixed
  by putting whole symbols in the table.
- `diogenes-browser.el:533` was safe and made literal anyway. It built
  `diogenes-parse-and-lookup-greek`, which is not moving -- but a language
  that was neither gave a backtrace, and a `pcase` says what went wrong.
- The advice names in `classicist-windows-compat.el` and
  `tei-diorisis.el` are safe: the adding and the removing are both assembled,
  in one file, from one format string. Rename the prefix and both follow.
- `diogenes-corpora.el:757` is a macro generating four
  `transient-define-argument` forms with `(intern (format "diogenes--tlg-%s"
  category))`. Those four names appear nowhere in the source, so no textual
  search can find them -- a category no wider regexp would help with.

### A fifth reading of prose as code

`diorisis-language -> annotate-region` appeared as an edge and is a docstring
mention: the option explains what the language is for and names the command
that uses it. Following it would have moved a defcustom into the wrong package.

The four before it: `diogenes--focus-role` reaching every dictionary module
through a docstring; the major modes quoted in the role tables; `pdf-search`
naming a function in a docstring; and `diogenes-browser-reference` mentioning
`diogenes-browse-tlg`. **A reference walker must skip docstrings as well as
comments**, and none of the ones written here did.


## The Perl API, which is the real dependency

Item 7 was written as "the facade: 35 sites destructuring Perl data shapes,
the only insurance against a marshalling change." Reading it says otherwise.

**There are sixteen consumers, not thirty-five**, and everything inbound
passes through ONE function:

```elisp
(defun diogenes--read-info (script)
  (read (with-temp-buffer ... (buffer-string))))
```

Whatever the Perl prints becomes lisp, unnormalised and unvalidated. So there
is one seam, not thirty-five, and a facade over the consumers would be
guarding the wrong place.

**Four shapes, and all four are stable.** Author lists and TLG categories are
keyword-keyed plists, which `--assoc-cadr`, `--keyword->string` and
`--string->keyword` already hide in ten places — a partial facade that exists
and was never finished. Work labels are a flat list of strings.

**And the `vectorp` test is not what it looks like.** `diogenes-corpora.el`
reads a works value with

```elisp
(cond ((vectorp works) ...these works...)
      ((eql works 1)   "")        ; all of them
      (t (error "Illegal value %s for author %s" works author)))
```

which is a **deliberate two-valued encoding**, not a defence against
inconsistent marshalling: a vector means *these works*, `1` means *all of
them*, and the `error` says those are the only two. Normalising vectors to
lists on the way in would destroy the distinction and break corpus selection.

So there is nothing to normalise, and the first instinct — one function in
`--read-info` to map vectors to lists — was a bug waiting to be introduced.
The `vectorp` is load-bearing. The other one, in `--list->perl`, is outbound
and also stays.

### And what breaks if Diogenes itself changes

The exposure is not the elisp shapes. It is the Perl API the generated
scripts call, and that is small enough to write down:

| module | used by |
|---|---|
| `Diogenes::Base` | `--define-corpus-script`, `--get-filter-file-script` |
| `Diogenes::Browser` | the two browse scripts, and the author, work and label lists |
| `Diogenes::Indexed` | the two search scripts, `--get-wordlist-matches-script` |
| `Diogenes::Search` | the same three, and `--get-tlg-categories-script` |

| method | where |
|---|---|
| `new` | every script |
| `select_authors` | `--search`, `--indexed-search`, `--get-tlg-categories`, `--define-corpus` |
| `do_search`, `read_index` | `--indexed-search-script`; `read_index` also in `--get-wordlist-matches` |
| `seek_passage` | both browse scripts |
| `browse_forward` | both browse scripts |
| `browse_backward` | `--browse-interactively-script` |
| `browse_half_backward` | `--browser-script` |
| `browse_authors`, `browse_works`, `browse_location` | the three list scripts |

**Twelve methods and four modules.** When Diogenes updates, that is the list
to diff — and most of what could change announces itself:

| change | how it shows |
|---|---|
| a method renamed, or its arguments changed | the script dies, Perl exits non-zero, and `--read-info` errors with "Perl exited with errors, no data received!" — **loudly** |
| a module renamed | `use` fails, same path |
| the data layout moved | `diogenes-path` finds nothing, loudly |
| **a return shape changed** | `(read ...)` gets a different datum, and **possibly nothing says so** |

The loud cases need no insurance; the existing error names the problem. The
silent case is the one to watch, and there is nothing to be done about it in
advance beyond knowing which twelve methods can produce it.

**This list is the insurance.** Thirty-five accessors would guard against a
rewrite nobody is doing — the suite's whole plan is to KEEP this bridge — and
would not have told anyone where to look when something did change.

## The gates, and the tools

Every check was a command somebody typed, until it was not.  `tei-browser`
had a thorough `make check`; the fork had nothing, while carrying 154
warnings and a per-file baseline in a text file with nothing enforcing it.

**Both trees now have a gate.**

| | `tei-browser` | the fork |
|---|---|---|
| warnings | fails on ONE | fails on WORSE than the baseline |
| declarations | `make declare` | `make declare` |
| the rest | forms, SQL, postags, pairing | the balance checker |

**A ratchet and not a zero, in the fork.** It began at 182 across 39 files,
mostly inherited, and a gate demanding zero gets switched off within a day.
**It is at 69 now**, and every one of the 69 is a long docstring or an unused
binding: nothing that is a fault. Each file is compared against `per-file-baseline.txt` and
may get better but not worse — which makes that file the ratchet, committed,
with the instruction to read its diff written into the target.

**Per file and never for the tree.** `batch-byte-compile` works
alphabetically in one Emacs, and a `require` loads the required file as
source, so one file silences another's warnings. That happened three times
during the extractions, once hiding the bug two upstream patches then fixed.

**And almost nothing was suppressed.** The 113 that went were:

| | |
|---|---|
| 16 variables defined | three idioms, six files |
| 7 files' definition order fixed | one of them a real bug |
| 4 real bugs | the Georges lookup, the sense stack, `format` two-for-one, a `:prompt` saying genre |
| 3 keyword functions declared `t` | the only true thing that can be said of them |
| 1 macro line | eight warnings, because it generates four functions |
| 1 dead file taken out of the build | twelve warnings about functions that no longer exist |

The ratchet only ever went down because something was wrong and got fixed.
`diogenes-search.el` went 17 to 0, `diogenes-corpora.el` 15 to 1,
`diogenes-perseus.el` 43 to 14 and then out of existence.

### `make duplicates`

`tools/check-elisp-duplicates.py`, and it exists because
`classicist--lookup-headword` was defined twice in two files and nothing
looked. A bare `(defvar x)` is a declaration and is skipped; a name that is
both a variable and a function in ONE file is left alone, which
`classicist-browser-header-line` legitimately is.

A duplicate is visible while both copies sit in one file — there the forms
checker calls it "defined twice" — and **invisible the moment a cut separates
them.** So it runs after every cut and not once.

### `make declare`, and what it found

`check-declare-directory` reads every `declare-function` and confirms the
named file defines that symbol with that arglist. **Nothing in this project
had ever run it.** In one pass:

- **a command that had never worked.** `diogenes-georges--locate`, declared
  and called and defined nowhere; the function is
  `diogenes-georges-pdf--locate`. So the Georges PDF lookup got a
  void-function at a keypress, and the evidence sat in every compile log as
  `not known to be defined` and was read as noise.
- **forty-one false declarations** across two repositories: six naming the
  wrong file, fifteen giving an arglist a `cl-defun` with keywords cannot
  have, one malformed with `nil` in the file slot, one naming an obsolete
  alias, and the rest arglists that had drifted.

`file not found` is filtered in both: pdf-tools, evil, org-roam and reader are
optional and not on the load-path, and those declarations are correct.

### The tools

| tool | what it encodes |
|---|---|
| `tools/check-elisp-balance.py` | a paren scanner, because a docstring can close a form early |
| `tools/check-elisp-forms.py` | defcustom shapes, and forward references |
| `tools/check-elisp-duplicates.py` | anything defined in more than one file |
| `tools/undeclared.py` | the five ways a reference walker lies |
| `tools/fix-declarations.py` | what a wrong declaration should have said |

**And two more the gate learned the hard way.** `compile` piped straight into
`grep -c Warning`, so a file that FAILED to compile counted as zero warnings
— less than its baseline — and the ratchet announced `better
diogenes-perseus.el: 40 -> 0` for a file that would not compile. Three at
once, reading as the best result of the evening, and inviting `make baseline`
to write the zeros down as the standard.

Then the fix for that matched `grep -qi error`, which matches
`rng-first-error` — a function name — so a file that compiled perfectly was
reported as broken. It matches `: Error: ` now, which is Emacs' own format and
cannot be a function name.

**Both were tested by breaking a file on purpose**, which is the only way to
know a gate works. Breaking `diogenes-utils.el` fails ten files, because nine
require it: one unbalanced paren cascades through the require graph.

`undeclared.py` is the one worth reading rather than running. Its docstring
lists the five causes and what each cost, because the walker is only as good
as the list: docstrings read as code, quoted data read as references, a
definer regexp too narrow, `declare-function` uncounted, transitive requires
uncounted. A sixth it names and cannot catch — a value expression constrains
the load order independently of the graph.

## [PENDING] Order of work

1. ~~**Merge what exists.**~~ **DONE.** Three branches merged with no
   conflicts, the branches deleted, one branch left.
2. ~~**The aliases into `-compat.el`.**~~ **DONE**, and split by audience
   rather than by file: 42 public to `classicist-obsolete.el`, 28 private to
   two `-compat.el` files, which are deleted when the fork and the TEI
   packages name the new ones. Five are double-dashed and public in fact,
   because `tei-diorisis.el` SETS them.
3. ~~**`diogenes-browser-show-citations` down.**~~ **DONE** — and it was not
   the last upward reference. `diogenes-browser.el:533` built
   `diogenes-parse-and-lookup-greek` with `intern`, which no walker could
   see; a `pcase` names it now.
4. ~~**`classicist-browser`**: the rename.~~ **DONE.** Sixty definitions,
   thirteen files in the fork and two in the TEI repository, sixty aliases,
   one feature name. What it cost to get there is the record worth keeping:
   a computed name in a remap table that would have stopped the arrows paging
   with no error; forty-one false `declare-function`s across two
   repositories; a user-facing command that had never worked; three variables
   the browser set and nothing defined; and two repositories' worth of names
   that had never followed two earlier renames.

   `(require 'diogenes)` is NOT yet stopped -- `diogenes.el` requires
   `classicist-browser`, which inverts the plan and is marked as temporary in
   the file. It stops when `classicist.el` exists to require both.
5. **`classicist-installation.el`**: seven forms, ~90 lines, eighteen
   consumers, out of `diogenes-lisp-utils.el`. Not a reading pass any more --
   the pass is done and the membership is above. After it that file is
   upstream's again.
6. ~~**Perseus into four.**~~ **DONE.** 4,173 lines into four files, one
   direction. See above for what each cut cost -- the design was right in
   shape and wrong in detail every time.
7. ~~**The facade**, and the 35-site conversion.~~ **DROPPED**, and replaced
   by a table rather than code -- see above. Sixteen consumers, not
   thirty-five; one seam, `diogenes--read-info'; four shapes, all stable; and
   the `vectorp' that looked like a defence against marshalling is a
   deliberate two-valued encoding that normalising would have broken.

   What is left is the Perl API table: twelve methods and four modules, which
   is what to diff when Diogenes updates. That is the insurance the facade was
   meant to be, and it says where to look.
8. **`tei-diorisis.el` into `diorisis-*` and `treebank-*`.** The reading pass
   is DONE and the design closed — see above. Two packages, 386 symbols
   renamed with no aliases, five seams of which one is already in place, the
   README's 45 names, and the Makefile.

   **Do the partition and the rename by script and the five seams by hand.**
   The first is mechanical and tested; the second is five small pieces of
   judgement against real code, and planning them from memory got two of six
   keymap entries wrong in a way `make check` would have passed.

   `make check` is green and gated, so each step has a net: split, check,
   seam, check.
9. **`classicist.el`** itself, written last, when the registry has real
   entries.

## [PENDING] Still not decided

- **The customize tree.** 19 defcustoms in `classicist-windows.el` and 2 in
  `classicist-citation.el` still say `:group 'diogenes`, and there is no
  `defgroup classicist` anywhere. Whether `classicist` is top-level with
  `windows` beneath it, or a child of `diogenes`, is a decision about how a
  reader browses the options.
- **The version string.** The aliases say `"0.1"`, which is a placeholder
  standing in for a numbering scheme the suite has not got.
- **`diogenes-search.el`'s six transitive references.** Reached through
  `diogenes-perseus` and `diogenes-corpora`, and not said. The same shape as
  `diogenes-forms.el`, which has been fixed; one `require` and three
  `declare-function`s, and it will not move the warning count for the same
  masking reason.
- **`.elc` files in upstream's repository.** Eleven are tracked and now stale
  against thirteen patches. A `.gitignore` line and `git rm --cached` is an
  obvious fourteenth patch; it is also why that worktree kept going dirty and
  why one compile read an out-of-date file.

## The Python scripts are unreachable from an installed package

A package manager builds .el files into a build directory and leaves
everything else in the checkout.  So tei-read.py, tei-index.py,
diorisis-index.py and the viewer's own files are all in straight/repos while
the package looks in straight/build -- and tei--script tries two places, both
inside the build.

A reader who INSTALLS rather than clones therefore has no TEI reading, no way
to make either index, and no viewer, until they name four paths by hand.
Found by installing on Doom, like everything else that mattered today.

WHAT IT WANTS is one classicist--script, asked by every file that runs a
script, with the fallback written once: the option if set, beside the library,
and then the source checkout that a build directory implies.  Four copies of
that logic is three too many, and tei--script currently has the first two and
not the third.

## An eighth gate: what the suite offers and the builder does not

Twice in one session the builder emitted a correct configuration that left
something switched off. The `lemmata` feature was not in its feature list;
`diogenes-roam-index-global-mode` was not turned on, so a reader who ticked
notes got an index that went stale on the first save.

The existing gate checks one direction -- every symbol the builder emits is a
real one -- and nothing checks the other. A list of every
`define-minor-mode`, and every member of `classicist-features`, against what
the builder mentions, would have caught both in a second.

Neither was a fault in the elisp. Both were a reader being handed a
configuration that worked and did less than it could, which is the hardest
kind to notice: nothing errors, and the feature simply is not there.

---

## Replacing something of the base's: which mechanism for which case

This suite replaces commands, a transient prefix, internal functions and a
display layer, all under the base's own names. Six times in one session that
went wrong, each time differently, and the answers are not
interchangeable.

**A command: advise it.** `advice-add ... :override` needs only that the base
has loaded, which `with-eval-after-load` guarantees. The twenty-one browse,
search and dump commands work this way, installed by
`classicist-install-overrides` and removable by
`classicist-remove-overrides` -- which a redefinition could never be.

**A definition: defer the definition.** A `transient-define-prefix` is not a
call, so advice cannot reach it, and whichever file defines it last wins.
`(symbol-file 'diogenes 'defun)` said `diogenes.elc` on Spacemacs and
`classicist.el` on Doom: package.el activates alphabetically, straight does
not, and the same commit behaved oppositely. The prefix lives in
`classicist-define-menu` now, called from a hook that by definition runs
after the base.

**And a `require` makes it worse, not better.** Loading this file when the
base loads makes our definition run EARLIER -- the base is part way through
its own file and defines its prefix after we have finished with ours. The
same form in our own autoloads can also fire before `provide` and recurse,
which a previous session diagnosed, wrote down, and which was reproduced
anyway.

**Something appended: publish a hook.** Defining a prefix replaces it whole
and discards every appended suffix. The appends had fired on a feature, which
is a guess about when the prefix is stable, and the guess became wrong the
moment the definition moved. `classicist-menu-defined-hook` is run at the end
of the definition and anything with something to append listens.

**When order matters, say it. Do not infer it from a load.**

**Top-level code: set the value, not the function.** The base validates its
lexicon at load. Every `with-eval-after-load` fires after that, so no advice
and no redefinition can affect what the validator reads. Three downstream
workarounds were tried and all were wrong; the fix was patch twenty, in the
base.

**And a file's own requires run before its own code.** `classicist.el`
requires a dozen of the base's libraries, one of which pulls in
`diogenes.el`. So anything that must precede the base has to precede the
`require` -- not merely be in the same file. `:demand t` in a reader's
configuration cannot help: the base is not loaded after us, it is loaded
during us.

---

## Where a cache belongs

Three kinds, and the distinction decides whether one file can serve two
machines.

**A cache of what a program computed** belongs with the program.
`classicist-books.eld` holds what Perl said about a work and sits under
`user-emacs-directory`, which is right: a new Emacs should build its own, and
it names no files.

**A cache about files** belongs with the files, and must name them RELATIVE to
their own root. `tei-index.eld` recorded absolute paths, so an index built on
Linux named nothing a macOS reader could open -- `/mnt/archive` and
`/Volumes/shared` being the same disk. It now records paths relative to the
directory it was built from, and `tei--resolve` joins them to
`tei-directory`.

`passow-index.eld` and `tgl-index.eld` still hold absolute paths, five and
six, one per scanned volume. See `lexicon-index-paths.md`.

**A cache of content** travels either way. `diorisis-vocabulary.eld` holds
beta code and nothing else, and has never cared where it sat -- which is
worth knowing, because reading it is what a slow mount makes expensive.

**And the trap in making a path relative**: check the real path and store the
portable one, in that order. `os.path.exists` on a relative path asks the
working directory, so storing before checking made every text fail as
declared-and-absent and the index came out with nothing in it.

---

## Completion: the candidate is the only thing every framework sees

Two prompts hid their matching where no framework could reach it, and both
now put everything in the candidate.

**Not in an annotation.** The Diorisis prompt had accented Greek as its
candidates and the beta code in an `annotation-function`, and nothing matches
an annotation. `le/gw` matched no candidate at all: the prompt worked only
because `diorisis-read-lemma` takes whatever was typed and hands it to
`diorisis--approximate` after the prompt closes -- which depends on the
framework letting a non-candidate through. Vertico does. Helm does not: it
offers it as an `Unknown candidate` source a reader must select.

**Not in a completion style either.** `diogenes-complete.el` does all its
matching in a style registered for its own category -- and helm uses no
styles at all, while Doom sets `completion-category-overrides` after we do:
`(alist-get 'diogenes-lemma completion-category-overrides)` is nil there and
`completion-styles` is `(orderless basic)`. So the style is dead code on that
path and its careful prefix-first ordering with it.

**And not in the ordering a style computes.** With the candidates matching at
last, `leg` showed `a)le/gw` before `le/gw`: the word list is alphabetical and
nothing was ranking. Frequency is not available -- the list's second field is
an offset into the analyses, not a count -- so the candidates are sorted
shorter first, which is a good proxy: a compound is always longer than what it
compounds.

**A style is a request; the candidate list is a fact.** Anything a reader
must be able to type belongs in the candidate, invisibly where it would be
noise: `λέγω  le/gw  legw`, with the bare letters propertized `invisible`.

---

## Two machines, one disk

The suite is developed on Linux and read on a macOS VM sharing one disk over
9p, which taught two things.

**9p is fine for reading a text and hopeless for compiling a package.**
`doom sync` sat twenty-five minutes on `Building classicist...` with zero
`.elc` files written -- not slow, blocked -- and finished in 6.7 seconds once
the recipe pointed at a local clone. So:

    the code           a local clone on each machine, pulled
    the corpora        on the share, read a file at a time
    the databases      on the share
    the caches         per the rule above

**And a bulk read is the pattern a slow mount handles worst.** The Diorisis
lemma prompt reads 63,718 rows; with no `diorisis-vocabulary.eld` beside the
database it does that every session, across the mount. Building the cache once
on the fast machine serves both -- it is portable -- provided both
configurations name the same physical database.

---

## [PENDING] A variable-declaration check

`make declare` verifies that every `declare-function` names a function that
exists. Nothing does the same for variables, and a bare `(defvar NAME)` says
exactly the same kind of thing: this name is defined elsewhere.

Six dictionary files pushed handlers onto
`diogenes--dict-xml-handlers-extra`, which a rename had made
`classicist--dict-xml-handlers-extra`. Twenty-three references, each with a
`(defvar)` above it silencing the compiler, and all six silent until a Bailly
entry was rendered.

And the same shape bit once more: a `declare-function` for
`diogenes--dict-file` satisfied the compiler while nothing in the file
required the library that defines it, so Doom would not boot. **A declaration
is a promise to the compiler and no help at all at runtime.**

---

## How to edit this suite

`make check` runs seven gates and is the first thing after any edit. After any
scripted change to elisp, `python3 tools/check-elisp-balance.py FILE` --
because paren counting is the only method that has worked. Three attempts at
one file cut into a neighbouring docstring, whose prose then compiled as code:
ninety-two warnings about a free variable named `THE`.

A docstring holds blank lines and lines at column zero, so neither is the end
of a form. Find the end by counting parens, with a string-and-comment state
machine, or do not find it at all.

Edits are made by Python scripts with asserts on what they expect. **A script
that writes nothing when its assert fires has cost nothing; one that writes
half a change has cost an hour**, and there were three of those.

And when something does not work, ask the running Emacs before reading the
source:

    (symbol-file 'NAME 'defun)          which file defined what is running
    major-mode                          what this buffer really is
    (boundp 'NAME)   (featurep 'NAME)   whether the new code is even loaded
    (alist-get ... completion-category-overrides)
    classicist-display-debug             the display log, which answers
                                         where a buffer went and why

Every one of those settled in seconds what reading had failed to settle in an
hour. The gates verify shapes; only a running Emacs verifies order.
