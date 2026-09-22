# Handover: four configurations, and what installing taught

Two days ago the suite did not install. It now installs and works on four
configurations. Nothing in this file is inference: everything in it was found
by starting an Emacs, or opening the builder, and looking.

## Where it stands

    Doom / Linux         everything below
    Spacemacs / Linux    everything, with helm rather than vertico
    Doom / macOS         everything, from a LOCAL clone of the suite
    vanilla / Linux      everything, the suite by :load-path
    Spacemacs / macOS     as a LAYER, the suite from the share
    vanilla / macOS      in progress -- see the open item below
    Windows              never tried

Ten features, seven gates, twenty-three patches on `classicist-base`.

## The one sentence worth keeping

**The gates check what the code says; installing checks what it does, and
almost every fault of these two days lived in the gap.** Every one that took
more than one attempt was invisible to seven checks and obvious to one
question asked of a running Emacs, or one look at a page.

## [OPEN] The thing to pick up first

**The builder is not emitting `:rev :newest` on the vanilla recipes**, though
it emits the comment explaining it -- so a downloaded config still stops with
`Version must be a string`. The note went in and the four recipe lines did
not, or a revert took them. First thing to check:

    grep -n ":rev :newest" tools/classicist-builder.html

Four emit lines should carry it: the base with and without a branch, roam, and
the suite. Without it `:vc` installs the last RELEASE, neither repository has
a tag, `package-desc` gets a nil version, and `version-to-list` is handed
`(0)`.

**And the vanilla config the builder writes is a fragment, not an init.el.**
It lacks the preamble, which only vanilla needs:

    (require 'package)
    (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
    (package-initialize)

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
`((NAME VERSION) ...)`, on which `package-buffer-info` fails outright.

**Nothing else would ever have found these.** straight, quelpa and
`:load-path` ignore those headers entirely. Only `package-vc` reads them, and
only a reader installing into vanilla uses that.

## The load-order problem, in six shapes

**A command: advise it.** `advice-add ... :override` needs only that the base
has loaded. Thirty-one commands work this way now.

**A definition: defer the definition.** A `transient-define-prefix` is not a
call, so advice cannot reach it, and whichever file defines it last wins.
`(symbol-file 'diogenes 'defun)` said `diogenes.elc` on Spacemacs and
`classicist.el` on Doom. The prefix lives in `classicist-define-menu`, called
from a hook that by definition runs after.

**And a `require` makes it worse** -- our definition then runs EARLIER, the
base being part way through its own file; and the same form in our own
autoloads can fire before `provide` and recurse.

**Something appended: publish a hook.** Defining a prefix discards every
appended suffix. `classicist-menu-defined-hook` runs at the end of the
definition. **When order matters, say it; do not infer it from a load.**

**A file's own requires run before its own code.** `classicist.el` requires a
dozen of the base's libraries and one pulls in `diogenes.el`. So `:demand t`
cannot help: the base is not loaded after us, it is loaded DURING us.

**And top-level code cannot be reached at all.** The base validates at load;
every `with-eval-after-load` fires later. The only remedy is to set the value
it reads -- patch twenty, in the base.

## The ten commands the override table left racing

`classicist--overridden-commands` was built from a LOOP over three families of
seven -- browse, search, dump -- and ten more were redefined under the base's
names and never in it: the lookups, the parses, the forms, the lemmata. So the
base's lookup ran, its buffer matched no `classicist-role-regexps` entry, and
every entry got fresh placement -- a new frame for each word looked up.

**The table was built from a pattern and everything outside it was silently
left racing.** A gate would have caught all ten and does not exist.

## Completion: the candidate is the only thing every framework sees

**Not in an annotation** -- the Diorisis prompt had the beta in one, and
nothing matches an annotation; vertico passed the unmatched string through and
helm did not.

**Not in a completion style** -- helm uses none, and Doom sets
`completion-category-overrides` after we do: `(alist-get 'diogenes-lemma
completion-category-overrides)` is nil there.

**And not in the ordering a style computes** -- `leg` showed `a)le/gw` before
`le/gw`. Frequency is not available (the word list's second field is an offset
into the analyses, not a count), so candidates are sorted SHORTER FIRST.

**A style is a request; the candidate list is a fact.**

## Caches, and where each belongs

    a cache of what a program COMPUTED   with the program
    a cache ABOUT FILES                  with the files, RELATIVE to their root
    a cache of CONTENT                   either way

`tei-index.eld` held absolute paths, so an index built on Linux named nothing
a Mac could open. It now records them relative to the directory it was built
from. **The trap:** `os.path.exists` on a relative path asks the working
directory, so storing before checking made every text fail as
declared-and-absent -- 0 of 3,283. Check the real path, store the portable one.

`passow-index.eld` and `tgl-index.eld` still hold absolute paths, five and six
-- see `lexicon-index-paths.md`.

## Two machines, one disk

**9p is fine for reading a text and hopeless for compiling a package.**
`doom sync` sat twenty-five minutes on `Building classicist...` with zero
`.elc` files written -- not slow, blocked -- and finished in 6.7 seconds once
the recipe pointed at a local clone.

    the code        a local clone on each machine, pulled
    the corpora     on the share
    the databases   on the share

**And quelpa's `:fetcher file` is a COPY, not a live tree**: editing the share
does not reach Spacemacs until `SPC f e U`. Doom's `:local-repo` and
Spacemacs' `:location local` with a symlink are the live kind.

**`diorisis-vocabulary.eld` was absent on the Mac**, so every lemma prompt read
63,718 rows across the mount. It is portable -- build it once on the fast
machine.

## macOS, in particular

`~/.config/emacs` is Doom, `~/.config/doom` its config,
`~/.config/spacemacs-emacs` Spacemacs with its dotfile at `~/.spacemacs`, and
`~/.config/emacs-vanilla` vanilla. Emacs is MacPorts' at
`/Applications/MacPorts/Emacs.app/Contents/MacOS/emacs`, on no shell PATH by
default -- three package managers have left binaries there.

Diogenes is at `~/Downloads/Diogenes.app/Contents`, with `dependencies/`
directly under `Contents` and no `Resources`. All the data is present, and the
Greek lexicon is `grc.lsj.xml` rather than Logeion's longer name -- which
patch twenty fixed in the base.

**The suite is private and the base is public**, so the base can be fetched
over HTTPS with no key and only the suite needs a local path. Eleven
interruptions today came from an ssh agent missing in one process; the
permanent answer is

    ssh-add --apple-use-keychain ~/.ssh/id_ed25519

with `AddKeysToAgent yes` and `UseKeychain yes` in `~/.ssh/config`.

Three launchers exist in `~/Applications`: Doom Emacs, Spacemacs, Vanilla
Emacs, each a minimal bundle running `emacs --init-directory`.

## The builder, which now emits four shapes

    vanilla             one box  [and see the OPEN item above]
    Doom                two boxes: packages.el, then config.el
    Spacemacs blocks    two boxes: additional-packages, then user-config
    Spacemacs layer     a switch, a name to paste, a file to download

**The two-box split cuts on `;; ---- in ... ----`**, a line the emit writes
itself -- which is what makes it safer than the layer's transform, which
re-wraps by pattern. The layer's output is verified by `check-parens`.

**The layer's transform has been wrong twice and both are instructive.** It
hooked into the PRESET's emit rather than the configuration's, so the switch
did nothing for four attempts; and it ended a `use-package` body at `/^\S/`,
which a comment at column zero matches -- so the tail of the settings landed
outside the form and a `:bind` at top level gave `Wrong type argument: listp,
diogenes`. Both fixed. **Its failure mode is silence**, so compare the two
outputs setq by setq after any change to the emit.

## [PENDING] What is left

**Windows.** `INSTALLING.md` has five questions; the first is whether
`diogenes-perl-executable` finds the bundled Perl (pending patch sixteen).
Expect `python3` to be `python` or the Store stub, and `epdfinfo` to want
MSYS2.

**Two builder faults.** `diogenes-roam` is emitted BEFORE the suite, and
org-roam pulls magit-section and cond-let: a stale MELPA entry for either is a
loading error, which stops the init file. Three starts lost the suite that
way. The fix is NOT to move the recipe below the suite's form -- all three
branches converge on `(use-package classicist` and `:init`, so anything after
is inside that body -- but to emit it after the whole form closes, past the
emit function's tail. And `org-roam-directory` has no box: no default, Doom's
org module supplies one, and a config ported from Doom reads a variable nobody
was asked for -- a message on every file opened.

**Two gates.** Every `define-minor-mode` and every member of
`classicist-features` against what the builder mentions; and a
variable-declaration check, a bare `(defvar NAME)` being unverified.

**A note on a marked stretch.** `diogenes-org-note`'s docstring promises it
and `classicist-browser-reference` returns `:from` and `:to`, but
`diogenes-org--reference-string` reads only `:key`.

## How to work on this

`make check` runs seven gates and is the first thing after any edit.
`python3 tools/check-elisp-balance.py FILE` after any scripted change to
elisp, because **paren counting is the only method that has worked**: three
attempts at one file cut into a neighbouring docstring, whose prose then
compiled as code -- ninety-two warnings about a free variable named `THE`.

**A docstring holds blank lines and lines at column zero**, so neither is the
end of a form. Count parens with a string-and-comment state machine.

**And `tools/classicist-builder.html` has three parallel branches that look
alike.** A search that crosses them finds the wrong one -- eight times in one
evening, once removing Doom's roam recipe while meaning to move vanilla's.
Anchor inside a branch by its own bounds, or read the whole function first.

Edits are made by Python scripts with asserts. **A script that writes nothing
when its assert fires has cost nothing; one that writes half a change has cost
an hour**, and there were four of those.

When something does not work, ask the running Emacs before reading the source:

    (symbol-file 'NAME 'defun)          which file defined what is running
    major-mode                          what this buffer really is
    (boundp 'NAME)   (featurep 'NAME)   whether the new code is even loaded
    (alist-get ... completion-category-overrides)
    classicist-display-debug            the display log
    check-parens                        on any generated elisp
    (package-desc-version (package-buffer-info))   whether a package is
                                                   installable at all

That last answered in two seconds what seven restarts could not. And for the
builder, a screenshot or one line in the browser's console settles in one look
what inference gets wrong repeatedly.
