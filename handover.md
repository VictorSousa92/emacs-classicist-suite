# Handover: four configurations, and what installing taught

Two days ago the suite did not install. It now installs and works on four
configurations. Nothing in this file is inference; everything in it was found
by starting an Emacs, or opening the builder, and looking.

## Where it stands

    Doom / Linux         everything below
    Spacemacs / Linux    everything, with helm rather than vertico
    Doom / macOS         everything, from a LOCAL clone of the suite
    vanilla / Linux      everything, the suite by :load-path
    Windows              never tried

The corpora browse with a header line and citations beside the text; six
printed dictionaries answer a word; 3,283 TEI texts are indexed portably and
read in both Perseus vintages; Diorisis and the word list complete on beta
code under either completion framework; thirty existing notes are found by
author and work.

**Ten features, seven gates, twenty-three patches on `classicist-base`.**

## The one sentence worth keeping

**The gates check what the code says; installing checks what it does, and
almost every fault of these two days lived in the gap.** Every one that took
more than one attempt was invisible to seven checks and obvious to one
question asked of a running Emacs, or one look at a page.

## The three patches that mattered most

**Patch twenty-one: a binary search whose comparison disagreed with its
file's order.** `ei)sh/|ei` could not be parsed while sitting in
`greek-analyses.txt` at line 412004, verified byte by byte.
`diogenes--ascii-sort-function` strips the diacritics -- which is what lets a
reader type `muw` and find `mu/w` -- and the file is sorted by the FULL beta
string, where `|` is codepoint 124 and sorts above every letter:

    ei)sh/esan   stripped eishesan   line 411916
    ei)sh/|ei    stripped eishei     line 412004

Stripped, `eishei` belongs before `eishesan`; in the file it is ninety lines
after. So the search converged on the wrong line and gave up. Neither
comparison is wrong -- one navigates the file, the other forgives the reader
-- so the exact one is a FALLBACK, tried only where the forgiving one found
nothing AND the query carries a diacritic the stripping removes. Every Greek
word with a subscript where another form has a letter had been quietly
returning a neighbour: most datives, most subjunctives.

**Patches twenty-two and twenty-three: the base was uninstallable by
`package-vc`.** A blank comment line between `Keywords:` and `Version:` ends
the library header block, so `lm-header` never saw `Version:` or
`Package-Requires:`; and `Package-Requires` read `(cl-lib thingatpt seq
transient)` -- a bare list of symbols where the header wants
`((NAME VERSION) ...)`, on which `package-buffer-info` fails outright. Either
alone gives `:version nil`, `version-to-list` is handed `(0)`, and the init
file stops with *Version must be a string*.

**Nothing else would ever have found these.** straight, quelpa and
`:load-path` ignore those headers entirely. Only `package-vc` reads them, and
only a reader installing into vanilla uses that -- which is exactly why
vanilla was on the list.

## The load-order problem, in six shapes

It came up six times and wants six different answers. Read this before
touching anything the base also defines.

**A command: advise it.** `advice-add ... :override` needs only that the base
has loaded. Thirty-one commands work this way now.

**A definition: defer the definition.** A `transient-define-prefix` is not a
call, so advice cannot reach it, and whichever file defines it last wins.
`(symbol-file 'diogenes 'defun)` said `diogenes.elc` on Spacemacs and
`classicist.el` on Doom: package.el activates alphabetically, straight does
not. The prefix lives in `classicist-define-menu`, called from a hook that by
definition runs after.

**And a `require` makes it worse.** Loading this file when the base loads makes
our definition run EARLIER -- the base is part way through its own file. The
same form in our own autoloads can fire before `provide` and recurse.

**Something appended: publish a hook.** Defining a prefix discards every
appended suffix. `classicist-menu-defined-hook` runs at the end of the
definition. **When order matters, say it; do not infer it from a load.**

**A file's own requires run before its own code.** `classicist.el` requires a
dozen of the base's libraries and one pulls in `diogenes.el`. So `:demand t`
in a reader's configuration cannot help: the base is not loaded after us, it
is loaded DURING us.

**And top-level code cannot be reached at all.** The base validates at load;
every `with-eval-after-load` fires later. The only remedy is to set the value
it reads -- which is what patch twenty does, in the base.

## The ten commands the override table left racing

`classicist--overridden-commands` was built from a LOOP over three families of
seven -- browse, search, dump -- and ten more commands were redefined under
the base's names and never in it: the lookups, the parses, the forms, the
lemmata. `(symbol-file 'diogenes-lookup-greek 'defun)` said `diogenes.elc`,
so the base's lookup ran, its buffer matched no `classicist-role-regexps`
entry, and every entry got fresh placement -- a new frame for each word looked
up.

**The table was built from a pattern and everything outside the pattern was
silently left racing.** It is now a list of what the suite actually redefines.
A gate would have caught all ten and does not exist.

## Completion: the candidate is the only thing every framework sees

**Not in an annotation.** The Diorisis prompt had accented Greek as candidates
and the beta in an `annotation-function`, and nothing matches an annotation.
It worked only because vertico passes an unmatched string through to
`diorisis--approximate`; helm offers it as an `Unknown candidate` instead.

**Not in a completion style either.** `diogenes-complete.el` does all its
matching in a style registered for its own category -- and helm uses no
styles, while Doom sets `completion-category-overrides` after we do:
`(alist-get 'diogenes-lemma completion-category-overrides)` is nil there and
`completion-styles` is `(orderless basic)`.

**And not in the ordering a style computes.** With the candidates matching at
last, `leg` showed `a)le/gw` before `le/gw`. Frequency is not available -- the
word list's second field is an offset into the analyses, not a count -- so the
candidates are sorted SHORTER FIRST, a compound always being longer than what
it compounds.

**A style is a request; the candidate list is a fact.**

## Caches, and where each belongs

    a cache of what a program COMPUTED   with the program
                                         classicist-books.eld, under
                                         user-emacs-directory: right as it is

    a cache ABOUT FILES                  with the files, naming them RELATIVE
                                         to their own root

    a cache of CONTENT                   either way
                                         diorisis-vocabulary.eld is beta code

`tei-index.eld` held absolute paths, so an index built on Linux named nothing
a Mac could open -- `/mnt/archive` and `/Volumes/shared` being the same disk.
It now records paths relative to the directory it was built from.

**The trap in that fix:** `os.path.exists` on a relative path asks the working
directory, so storing before checking made every text fail as
declared-and-absent and the index came out empty -- 0 of 3,283, which the
counts showed at once. Check the real path, store the portable one.

## Two machines, one disk

**9p is fine for reading a text and hopeless for compiling a package.**
`doom sync` sat twenty-five minutes on `Building classicist...` with zero
`.elc` files written -- not slow, blocked -- and finished in 6.7 seconds once
the recipe pointed at a local clone.

    the code        a local clone on each machine, pulled
    the corpora     on the share
    the databases   on the share
    the caches      per the rule above

**And a bulk read is what a slow mount handles worst.** The Diorisis lemma
prompt reads 63,718 rows; with no `diorisis-vocabulary.eld` beside the
database it does that every session, across the mount. It is portable, so
building it once on the fast machine serves both.

## macOS, in particular

`~/.config/emacs` is Doom, `~/.config/doom` its config,
`~/.config/emacs/.local/straight/` the packages. Emacs is MacPorts' at
`/Applications/MacPorts/Emacs.app/Contents/MacOS/emacs`, on no shell PATH by
default -- three package managers have left binaries there and `which emacs`
found none until the export went into `.zshrc`.

Diogenes is at `~/Downloads/Diogenes.app/Contents`, with `dependencies/`
directly under `Contents` and no `Resources`. All the data is present.

Three launchers exist in `~/Applications`: Doom Emacs, Spacemacs, Vanilla
Emacs, each a minimal bundle running `emacs --init-directory` against its own
tree.

## The builder, which now emits four shapes

    vanilla             one box, :rev :newest, diogenes-path above the forms
    Doom                two boxes: packages.el, then config.el
    Spacemacs blocks    two boxes: additional-packages, then user-config
    Spacemacs layer     a switch, a name to paste, a file to download

**`:rev :newest` was the one that stopped an install outright**: `:vc`
installs the last RELEASE by default and neither repository has a tag.

**The two-box split cuts on `;; ---- in ... ----`**, a line the emit writes
itself -- which is what makes it safer than the layer's transform, which
re-wraps by pattern and can drop a line it does not recognise. The layer's
output is verified by `check-parens` and not by reading.

**And one of three shows, decided in one place.** `renderLayer` and
`renderSplit` were both writing `c-out`, and switching from a layer back to
blocks left all three visible.

## [PENDING] What is left

**Windows.** Never tried. `INSTALLING.md` has five numbered questions and the
first is whether `diogenes-perl-executable` finds the bundled Perl, which is
pending patch sixteen. Expect two more: `python3` may be `python` or the Store
stub, and `epdfinfo` wants MSYS2, which the nine scanned dictionaries depend
on and nothing else does.

**Two builder faults.** `diogenes-roam` is emitted BEFORE the suite, and
org-roam pulls magit-section and cond-let: a stale MELPA entry for either is a
loading error, which stops the init file, so the suite never loads. Three
starts in a row lost it that way. The fix is NOT to move the recipe below the
suite's form -- all three branches converge on `(use-package classicist` and
`:init`, so anything after is inside that body -- but to emit it after the
whole form closes, which is past the emit function's tail and not yet read.

And `org-roam-directory` has no box at all: it has no default, Doom's org
module supplies one, and a config ported from Doom reads a variable nobody was
asked for -- a message on every file opened.

**Two lexicon indexes still hold absolute paths.** `passow-index.eld` five,
`tgl-index.eld` six, one per scanned volume. `lexicon-index-paths.md` has the
fix and the reasoning.

**Two gates.** Every `define-minor-mode` and every member of
`classicist-features` against what the builder mentions -- the `lemmata`
feature and `diogenes-roam-index-global-mode` were both absent, so a reader
got a configuration that worked and did less than it could. And a
variable-declaration check: a bare `(defvar NAME)` says a name is defined
elsewhere and nothing verifies it, which is how six dictionaries pushed onto a
variable that had been renamed.

**A note on a marked stretch.** `diogenes-org-note`'s docstring promises "a
note on the passage in hand, or on the stretch that is marked", and
`classicist-browser-reference` already returns `:from` and `:to`. But
`diogenes-org--reference-string` reads only `:key`, so the range is thrown
away. The docstring is the specification; the wiring is missing.

## How to work on this

`make check` runs seven gates and is the first thing after any edit.
`python3 tools/check-elisp-balance.py FILE` after any scripted change to
elisp, because **paren counting is the only method that has worked**: three
attempts at one file cut into a neighbouring docstring, whose prose then
compiled as code -- ninety-two warnings about a free variable named `THE`.

**A docstring holds blank lines and lines at column zero**, so neither is the
end of a form. Count parens with a string-and-comment state machine, or do not
find the end at all.

**And `tools/classicist-builder.html` has three parallel branches that look
alike.** A search that crosses them finds the wrong one -- which it did eight
times in one evening, once removing Doom's roam recipe while meaning to move
vanilla's. Anchor inside a branch by its own bounds, or read the whole
function first.

Edits are made by Python scripts with asserts on what they expect. **A script
that writes nothing when its assert fires has cost nothing; one that writes
half a change has cost an hour**, and there were four of those.

When something does not work, ask the running Emacs before reading the source:

    (symbol-file 'NAME 'defun)          which file defined what is running
    major-mode                          what this buffer really is
    (boundp 'NAME)   (featurep 'NAME)   whether the new code is even loaded
    (alist-get ... completion-category-overrides)
    classicist-display-debug            the display log
    (package-desc-version (package-buffer-info))   whether a package is
                                                   installable at all

That last answered in two seconds what seven restarts could not. And for the
builder, a screenshot or one line in the browser's console settles in one look
what inference gets wrong repeatedly.
