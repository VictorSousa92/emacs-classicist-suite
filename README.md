# Tools for reading Greek and Latin in Emacs

Browse and search the TLG and the PHI, look a word up in a dozen dictionaries,
parse it, read the Perseus editions as TEI, search ten million lemmatised words
of Greek, annotate a sentence as a dependency tree, and keep notes joined to the
passages they are about — without leaving Emacs.

- [What this is, and whose work it stands on](#what-this-is-and-whose-work-it-stands-on)
- [What it adds](#what-it-adds)
- [Requirements](#requirements)
- [Tested on](#tested-on)
- [Installing](#installing)
  - [The base wants nine patches](#the-base-wants-nine-patches)
  - [Then read INSTALLING.md](#then-read-installingmd)
- [Modularity: choosing what is awake](#modularity-choosing-what-is-awake)
- [Using it](#using-it)
  - [Reading a text](#reading-a-text)
  - [Looking a word up](#looking-a-word-up)
  - [In a lookup buffer](#in-a-lookup-buffer)
  - [`C-c C-c`, or `RET`, on anything](#c-c-c-c-or-ret-on-anything)
  - [The printed dictionaries](#the-printed-dictionaries)
  - [When an analysis is wrong](#when-an-analysis-is-wrong)
    - [Forms with no analysis](#forms-with-no-analysis-extra-lemmata)
    - [Analyses that are wrong](#analyses-that-are-wrong-analysis-corrections)
    - [Morpheus](#morpheus-for-the-forms-neither-table-names)
  - [The Diorisis corpus](#the-diorisis-corpus)
  - [Treebank annotation](#treebank-annotation)
  - [Editions as TEI](#editions-as-tei)
  - [Notes joined to passages](#notes-joined-to-passages)
  - [Forgetting the keys](#forgetting-the-keys)
  - [Under evil](#under-evil)
- [Where the windows go](#where-the-windows-go)
- [One package kept beside it](#one-package-kept-beside-it)
- [Which files are Michael Neidhart's, modified](#which-files-are-michael-neidharts-modified)
- [Developing](#developing)
- [Licence and credits](#licence-and-credits)

---

## What this is, and whose work it stands on

Three names, and it matters which is which.

**Peter Heslin's [Diogenes][diogenes]** is the program underneath all of it. It
reads the TLG, PHI and DDP databases, ships the LSJ and Lewis & Short, and
carries the morphological tables that parse a Greek or Latin form. Everything
here that touches a corpus ultimately asks Diogenes' Perl to do it. Without
Diogenes there is nothing to build on.

**Michael Neidhart's [diogenes.el][base]** is the Emacs interface to it, and is
the direct ancestor of this suite — not merely an inspiration. It established
the Perl bridge, the corpus browser, the dictionary lookup, the transient menu,
and the shape of nearly every command a reader here will type. This suite is
**built on top of it and requires it installed**; five of the files here are
modified versions of his, and they are listed
[below](#which-files-are-michael-neidharts-modified).

**This suite** adds to that: eleven more dictionaries, the Diorisis corpus, TEI
editions, treebank annotation, org notes joined to passages, window management,
and a set of corrections to the base. It does not replace `diogenes.el`; it
extends it, and it is the poorer relation of the two in the sense that matters —
the hard part, making Emacs talk to Diogenes at all, was already done.

If you want the base alone, install [`diogenes.el`][base] and stop there. It is
a complete and well-made thing, and this suite exists because it was good enough
to build on.

## What it adds

Ten features, and you name the ones you want — see
[Modularity](#modularity-choosing-what-is-awake). The default is the two that
match what `diogenes.el` itself does.

| | |
|---|---|
| **Diogenes' corpora** | browsing and searching the TLG, the PHI, the papyri, the inscriptions |
| **The LSJ and Lewis & Short** | a word looked up, parsed, and every form it is attested in |
| **The printed dictionaries** | Bailly, the OLD, the TLL, Montanari, the DGE, the Cambridge, BDAG, Passow, the TGL, Gaffiot, Georges, Pape |
| **The Diorisis corpus** | ten million lemmatised words of Greek, searched by lemma, form, morphology and date |
| **Treebank annotation** | a sentence as a dependency tree, as ALDT or CoNLL-U |
| **Editions as TEI** | Perseus, the First Thousand Years of Greek, the CSEL |
| **Notes in org** | a note on the passage in hand, and what has been said about these lines |
| **Windows and frames** | where a buffer lands, and whether a perspective claims it |

**Two of those want no Diogenes data at all.** Diorisis and the TEI editions
read their own files, so a reader with no CD-ROMs can set two paths and still
have a Greek corpus search and a reader for the editions.

## Requirements

- **Emacs 28.1** or later for the code; **30** or later if you install with
  `use-package`'s `:vc`, which the builder writes by default.
- **A working Diogenes installation**, from [d.iogen.es][diogenes]. The corpora
  themselves (TLG, PHI, DDP) are licensed separately and are not needed for the
  Diorisis or TEI features.
- **`diogenes.el`**, from the branch described under
  [Installing](#the-base-wants-nine-patches).
- **sqlite**, built into Emacs 29 and later, for Diorisis. `(sqlite-available-p)`
  says whether you have it.
- **Python 3** on `PATH`, for reading TEI.
- Optional: Ghostscript or poppler for the scanned dictionaries, and
  [Morpheus][morpheus] if you want a parser beyond the shipped word lists —
  it is source only, so you build it yourself; see
  [Morpheus](#morpheus-for-the-forms-neither-table-names).

## Tested on

Three Emacs distributions on three operating systems:

| | plain Emacs | Doom | Spacemacs |
|---|---|---|---|
| **Linux** | yes | yes | yes |
| **macOS** (Sequoia) | yes | yes | yes |
| **Windows** (MSYS2) | yes | yes | yes |

Emacs 30 throughout. Earlier versions should run the code — the package declares
28.1 — but `use-package`'s `:vc`, which the builder writes, needs 30.

Windows needs four settings that no other platform does, and one trap that has
nothing to do with this suite — [`INSTALLING.md`][installing] has both.

## Installing

**Use the configuration builder.** [Open it here][builder] — or, from a clone,
`tools/classicist-builder.html` in any browser.

It asks which Emacs you run, which operating system, which features you want
and where your files are, and writes a configuration that is correct for the
answers. Nothing is uploaded: one HTML file, no network calls, which is also
why it works offline from a clone.

Writing the block by hand is possible and not advised. There is more to get
right than there looks — which of the three distributions takes `:vc`, which
takes a straight recipe and which takes a list you edit; which settings must
come before the `use-package` forms; and, on Windows, four more that no other
platform needs.

### The base wants nine patches

The suite relies on nine fixes to `diogenes.el` that are not yet in the
original. Until they are merged, install the base from
[`VictorSousa92/diogenes.el`][fork], branch `classicist-base`.

    M-x classicist-check-base

says whether a given installation will do. It probes the three patches that
fail *quietly* — where the wrong answer looks like no answer — rather than
trusting a version number.

Everything in that branch is a fix or an extension point, not a rewrite: the
intention is that it becomes unnecessary.

### Then read INSTALLING.md

**[`INSTALLING.md`][installing]** has the rest: what to run first whichever
Emacs, the per-distribution notes, and a section each for Linux, macOS and
Windows.

Windows is the one that needs reading before you start. It wants MSYS2 with its
native `mingw64` Emacs, `git` and Python, and four settings that answer for the
Perl Diogenes bundles and for a GUI Emacs inheriting no shell environment — the
builder writes those four when you tick the Windows box, and `INSTALLING.md`
explains the two traps that fail in ways which do not look like their cause.

## Modularity: choosing what is awake

**Nothing you did not ask for.** The suite is one package of ten features, and
you name the ones you want:

```elisp
(setq classicist-features '(texts lexica))
```

That default is deliberate — it is what Diogenes itself does. A reader who
installs this and reads no further gets a browser and a dictionary and nothing
else. The eight features that are new here are opted into, one at a time.

**Asleep is not absent.** Every file is loaded; a feature not named installs no
keys, adds no menu entry, and offers nothing. So the menu is as small as your
configuration, and turning something on is one symbol rather than an install.

| Feature | What it wakes |
|---|---|
| `texts` | browsing and searching Diogenes' own corpora |
| `lexica` | the LSJ and Lewis & Short, the parse, every attested form |
| `lemmata` | completing a lemma prompt on the word list — 63,718 Greek lemmata with their frequencies, matched by beta code or Greek with the diacritics optional |
| `dictionaries` | the printed ones; *which* of them is `classicist-declared-dictionaries` |
| `diorisis` | searching the Diorisis corpus of lemmatised Greek |
| `treebank` | annotating one of its sentences as a dependency tree |
| `tei-corpora` | the CSEL, the Patrologia Latina, Corpus Corporum, anything published as TEI XML |
| `books` | a work opened at one of its books — *Theta*, not `1045b27`. The corpora do not know books; the text carries their titles, and this reads them |
| `notes` | the org commands: a note on a passage, and what has been said about the lines in front of you |
| `windows` | the suite placing buffers, rather than leaving that to whatever you have arranged |

### Three want another

Seven of the ten stand alone. Three do not:

- **`treebank`** wants **`diorisis`** — it annotates that corpus's sentences,
  reads its file, and puts its keys in its results buffer.
- **`dictionaries`** wants **`lexica`** — the printed ones are reached from the
  banner at the head of an LSJ or Lewis & Short entry.
- **`notes`** wants **`texts`** or **`tei-corpora`** — a note is about a
  passage, and either browser will do.

<!-- -->

    M-x classicist-check-features

says so when one does not have what it wants, rather than leaving you to
wonder why a key does nothing.

### And not every corpus is Diogenes'

`diorisis` and `tei-corpora` read their own files and want nothing of the
CD-ROMs. So

```elisp
(setq classicist-features '(diorisis tei-corpora))
```

with no `diogenes-path` at all is a working answer: a lemma search over ten
million words of Greek, and a reader for the TEI editions. Worth knowing if you
have no TLG licence.

## Using it

Everything is under one menu:

    C-c d

which is the base's `diogenes` transient with this suite's entries added to it.
Entries appear only for features that are awake, so the menu is as small as
your configuration.

| | SEARCH | BROWSE | DUMP |
|---|---|---|---|
| Greek TLG | `sg` | `bg` | `dg` |
| Latin PHI | `sl` | `bl` | `dl` |
| Duke Documentary Papyri | `sd` | `bd` | `dd` |
| Classical inscriptions | `si` | `bi` | `di` |
| Christian inscriptions | `sc` | `bc` | `dc` |
| Miscellaneous PHI | `sm` | `bm` | `dm` |
| **Diorisis, by lemma** | `sD` | `bD` | |
| **The annotated trees** | `sa` | | |
| **Other corpora (TEI)** | | `bt` | |

Morphology and dictionaries: `lg` looks a Greek word up in the LSJ, `ll` a
Latin one in Lewis & Short, `pg` and `pl` parse first, `mg` and `ml` open the
morphology tools. `c` manages custom corpora.

### Reading a text

In a browser buffer, `n` and `p` turn the page, `RET` follows a citation, and a
click looks a word up. Hyphenation across a line break is joined for a lookup
and put back when you leave.

With the `books` feature awake, a work can be opened at one of its books —
*Theta* rather than 1045b27. Two ways, and not every work: Aristotle prints
his book titles in the text and those are found by reading; Plato does not, so
the *Republic*, the *Laws* and the *Letters* are declared outright. Other
authors have not been tried, and one that gives nothing gives nothing rather
than a wrong answer.

### Looking a word up

Four commands, and the distinction matters: parse first for text you are
reading, look up directly when you already know the lemma.

| Command | Does |
|---|---|
| `classicist-parse-and-lookup-greek` | analyse an inflected form, then look its lemma up |
| `classicist-parse-and-lookup-latin` | the same, for Latin |
| `classicist-lookup-greek` | the LSJ, by headword |
| `classicist-lookup-latin` | Lewis & Short, by headword |

Greek input works in Unicode or in beta code. Everything becomes beta code
internally, so beta code is occasionally the more reliable of the two. With no
exact match the nearest entry is shown, and a message says so.

**`C-c C-o`** — `classicist-lookup-in-dictionary` — is the same thing with the
dictionary asked for rather than assumed. For a word the default dictionary
does not carry, for a sense Bailly gives and the LSJ does not, or for reading a
Greek word in German. The word at point is parsed first, so an inflected form
still reaches its lemma; a prefix argument prompts for the word instead. Every
registered dictionary of that language is offered, configured or not — so this
is also how you reach one whose paths you have not set, and it will tell you
what to set.

### In a lookup buffer

The entry is formatted from its TEI XML, citations are clickable, and every
dictionary is reachable from every entry by its key or its link.

| Key | Latin | Key | Greek |
|---|---|---|---|
| `o` | OLD | `m` | Montanari |
| `t` | TLL | `c` | CGL |
| `g` | Gaffiot — entry, or the page past F | `b` | BDAG |
| `G` | Georges | `d` | DGE (α–ἐπ) |
| `l` | Lewis & Short, the way back | `p` | Passow |
| | | `t` | TGL |
| | | `B` | Bailly |
| | | `P` | Pape |
| | | `l` | LSJ, the way back |

`C-c C-n` and `C-c C-p` page between entries; `q` quits. A key acts on the
entry the cursor is in, recomputed at each keypress. Inside a dictionary's own
entry its link becomes the way back, and where that dictionary also has a scan,
`[PDF]` joins it — so `B` inside a Bailly entry opens that word in the printed
edition.

All of these are set by `classicist-lookup-keys` and
`classicist-lookup-dictionary-keys`, so any of them can be moved, and nil
unbinds one.

### `C-c C-c`, or `RET`, on anything

This is how you move while reading. It does something different according to
what is under the cursor:

| Under the cursor | What happens |
|---|---|
| a citation | opens that passage in the browser |
| a dictionary link — `[OLD]`, `[TGL]` | opens that dictionary at this entry's page |
| a Greek or Latin word | parses it and shows its entry |
| an English gloss in an LSJ entry | nothing, which avoids a spurious parse |

The language is decided in that order: a word tagged Latin or Greek in the XML
is parsed as such; otherwise a word in Greek script is Greek; otherwise the
entry's own language is used. The third rule is what makes a Latin word inside
a Lewis & Short entry work, since the body Latin there is untagged.

**The cost of that third rule**: an *English* word in a Lewis & Short entry is
untagged too, so `C-c C-c` on one gives a spurious Latin entry. An LSJ entry
does not have this problem — there, untagged Latin-script words are treated as
glosses and left alone.

It also asks whether to open the result in the same window. Either way a fresh
buffer is used, so the entry you came from stays reachable.

### The printed dictionaries

Twelve of them, in two kinds.

**As entries**, from TEI XML: Bailly, Georges, Gaffiot, the DGE, Pape. These
behave like the LSJ — a formatted entry, clickable citations, keys to every
other dictionary. Some need a one-off conversion from the source file, which
the relevant `-source-file` option points at.

**As pages**, from scans: the OLD, the TLL, Montanari, the CGL, BDAG, Passow,
the TGL, and the printed Gaffiot, Georges and Bailly. These open a PDF at the
page the headword is on, found through a prebuilt index where one exists.

Which appear is governed by `classicist-declared-dictionaries`, not by whether
the files are present — so a key tells you what to configure rather than doing
nothing. Set no dictionary paths at all and the suite offers what the base
does: the LSJ, Lewis & Short, the morphology and the corpora, with no links
line and no keys leading nowhere.

`diogenes-old-pdf-viewer` chooses between `pdf-tools` and `doc-view`. The scans
are OCR'd to varying standards and their bookmarks are not always reliable, so
a lookup lands on the right page more often than on the right column.

### When an analysis is wrong

Diogenes' morphology is a batch run of Morpheus over wordlists harvested from
the corpora it indexes. That makes it very good and not complete, and the gaps
come in four kinds which want four different answers.

| The form | What happens | What to set |
|---|---|---|
| is spelled a way the file does not use | the variants machinery resolves it | nothing; `classicist-latin-try-spelling-variants` governs it |
| has no analysis, and you know the headword | say so | `classicist-latin-extra-lemmata`, `classicist-greek-extra-lemmata` |
| has no analysis, and you would rather not name one | Morpheus is asked | `classicist-morpheus-directory` |
| is analysed, and analysed wrongly | say what it is instead | `classicist-latin-analysis-corrections`, `classicist-greek-analysis-corrections` |

**Both languages have both tables.** The Greek data is wrong more often than
the Latin rather than less — Morpheus knows less Greek, and the LSJ keys some
headwords differently from the form Morpheus gives — so a reader who has worked
out what a form actually is should be able to record it.

#### Forms with no analysis: `extra-lemmata`

An alist of form and headword, consulted **only** when the analyses file has
nothing at all, so it adds and never overrides:

```elisp
(setq classicist-latin-extra-lemmata
      '(("valde"      . "validus")     ; the adverb, and its comparison:
        ("valdius"    . "validus")     ;   Morpheus' stems carry `valde'
        ("valdissime" . "validus")     ;   without `valdius' or `valdissime'
        ("gnaviter"   . "naviter")     ; the older spelling
        ("illidant"   . "illido")))    ; its other fourteen forms are there

(setq classicist-greek-extra-lemmata
      '(("οὑτοσί" . "οὗτος")           ; deictic
        ("ταὐτόν"  . "αὐτός")))         ; crasis
```

The value is a headword and not a file offset, so an entry survives a rebuild
of the Perseus data. Matching ignores case and the spelling conventions, so one
Latin entry answers for `ualdissime` as well as `valdissime`; Greek entries are
compared as the rest of the Greek lookup compares them, so an unaccented entry
answers for the accented form.

Deictic and crasis forms are what the Greek table is mostly for, and gaps in
harvested wordlists what the Latin one is for. The gaps are not random:
`illidant` is the present subjunctive of `illido`, whose fourteen other forms
are all there, and it parsed as nothing and fell through to a search for
itself, which found `illico`. The `valde` family is a different gap again —
Morpheus' stems carry the adverb without its comparative and superlative — so
those three earn their place even on a machine with Morpheus built.

#### Analyses that are wrong: `analysis-corrections`

Keyed by the form, with three keys:

```elisp
(setq classicist-latin-analysis-corrections
      '(("superstite" :lemma "superstes")))   ; Morpheus says `super-sto'

(setq classicist-greek-analysis-corrections
      '(("ᾖ" :info "pres subj act 3rd sg")))
```

`:info` replaces the morphology, `:lemma` the headword — and the dictionary
entry the keys open follows the corrected lemma — and `:add` shows further
readings alongside the file's own. For Latin, `:info` also takes an alist of
old and new, for a form with several analyses of which one is wrong.

By default a corrected analysis is marked ` [corr.]`, so what you are reading
is never silently other than what the shipped data says.
`classicist-latin-mark-corrections` turns that off.

#### Morpheus, for the forms neither table names

Morpheus generates paradigms from stems rather than harvesting a corpus, so it
knows forms no text happened to use. It is source only and you build it
yourself.

**Use [this fork][morpheus]**, which has the more complete stems and is the one
the suite was tested against:

```sh
git clone https://github.com/VictorSousa92/morpheus
cd morpheus/src && make CC="gcc -std=gnu17 -fpermissive" && make install
cd ../stemlib/Latin && env PATH="$PWD/../../bin:$PATH" MORPHLIB="$PWD/.." make
```

Then:

```elisp
(setq classicist-morpheus-directory "/path/to/morpheus")
```

- Consulted **only** after the shipped analyses and the `extra-lemmata` table
  have both missed, so leaving it unset changes nothing.
- The directory must hold `bin/cruncher` and `stemlib/`; one without them
  counts as unset.
- `classicist-morpheus-timeout` (10 seconds) bounds the wait.
- A lemma Morpheus returns is resolved against the dictionary's own keys,
  Morpheus having no notion of file offsets. Found, the entry is shown as
  usual; not found, the morphology is still shown, with the caveat that the
  headword is a guess.

Nothing here requires that particular build — any Morpheus laid out the same
way is run the same way — but another one must print the `<NL>…</NL>` output
the parser reads, and must spell its lemmata as Lewis & Short keys them.

The [org-branch README][orgreadme] works through all four cases with more
examples.

### The Diorisis corpus

Ten million lemmatised words of Greek, with its own database and no need for
any Diogenes data. `sD` searches by lemma; `bD` reads a text.

The search is by lemma, by form, by morphology, by date range and by genre, and
combinations of those — *this lemma, as a perfect participle, in prose of the
second century AD*. Results are a hit list you can page through, open at the
passage, or count: `d` gives the distribution by text **per ten thousand
words**, since raw counts say more about the length of a text than about the
word.

Two words within *n* words, or within *n* nodes of the dependency tree, are
both askable.

### Treebank annotation

With `treebank` awake and Diorisis beside it, a sentence can be annotated as a
dependency tree and exported as ALDT or CoNLL-U. `sa` searches the trees you
have already made.

`tools/viewer` serves the tree to Arethusa in a browser, with `serve.py` —
which answers the tree by URL, accepts a write back, and binds to 127.0.0.1.
Its own README explains why `python3 -m http.server` is no longer enough.

### Editions as TEI

`bt` browses editions that are not Diogenes': Perseus, the First Thousand Years
of Greek, the CSEL. Point `tei-directory` at a tree of TEI files and it lists
the corpora, then the works, then the versions of a work. Reading is done by
`tei-read.py`, which needs Python on `PATH`.

Citations in a dictionary entry can open here as well as in Diogenes' own
corpora — `classicist-lookup-open-greek-with` sets the order in which the three
are tried.

### Notes joined to passages

With `notes` awake, `diogenes-org-note` writes a note about the passage in hand
and `diogenes-org-notes` shows what has been said about these lines. A note
carries an org link back, so the passage and the note each reach the other.

### Forgetting the keys

    M-x diogenes-cheatsheet

shows them in a floating panel that vanishes at the next keystroke. It is read
from the **live keymaps**, so it lists what this installation actually has —
the dictionaries you configured and nothing that would decline. The current
buffer's keys come first, then the other buffers', then the commands that get
you into one. On a terminal frame, where there are no child frames, it falls
back to an ordinary help window.

Worth binding, since it is the one command that tells you the rest:

```elisp
(with-eval-after-load 'classicist-lookup
  (keymap-set classicist-lookup-mode-map "?" #'diogenes-cheatsheet))
```

### Under evil

Doom and Spacemacs users, and anyone else with evil: the single-letter
dictionary keys collide with evil's normal state. `diogenes-evil.el` puts them
where they do not, and is loaded when evil is present.

## Where the windows go

A preset is a window arrangement kept in a file you load when you want it,
rather than in your init file. Four ship — `defer`, `reuse`, `split`,
`frames` — and the builder's second tab writes your own, with a simulator that
shows what each does to a frame before you commit to it.

    (setq diogenes-preset "split")

## One package kept beside it

[`diogenes-roam`][roam] files a passage note under its author and its work and
keeps an index of them — branch `classicist-roam` for the version that works
with this suite. It wants org-roam, which is why it is separate. Not required;
noticed where present.

## Which files are Michael Neidhart's, modified

Six files here are derived from his, and the table says from which.

`diogenes.el` and `diogenes-browser.el` were modified in place:

| This file | Modified from | Shared definitions |
|---|---|---|
| `classicist.el` | `diogenes.el` | 43 of 53 |
| `classicist-browser.el` | `diogenes-browser.el` | 22 of 62 |

The figures are shared definition names, counted after allowing for this
suite's `classicist-` prefix, so they measure how much of each file is his
design rather than how many lines are untouched.

**`diogenes-perseus.el` became four files.** 4,173 lines, cut into a stack that
runs in one direction, with three `declare-function`s back for what the
dispatcher calls at a keypress:

    variants -> lexicon -> lookup -> morphology

| This file | Forms | Lines | What it does |
|---|---|---|---|
| `classicist-variants.el` | 28 | 578 | spellings a dictionary file does not use |
| `classicist-lexicon.el` | 28 | 406 | reading a dictionary file |
| `classicist-lookup.el` | 71 | 1,363 | the buffer an entry is shown in |
| `classicist-morphology.el` | 66 | 1,650 | the morphological analysis |

`classicist-architecture.md` records what each cut cost, which is worth reading
before moving anything: the design was right in shape and wrong in detail every
time.

Three further files exist only to keep his names working —
`diogenes-browser-compat.el`, `diogenes-lisp-utils-compat.el` and
`classicist-windows-compat.el` — so that configuration written against
`diogenes.el` continues to load.

Every one of these carries his copyright in its header alongside any later one.
The remaining files are this suite's own, and the base's own files are not
vendored here at all: `diogenes.el` is a dependency, installed separately, and
this suite requires six of its files at load.

## Developing

    make check

runs six gates: the per-file compile ratchet, every `declare-function` against
the definition it names, anything defined in more than one file, every symbol
the configuration builder emits, and the SQL — which is extracted from
`diorisis.el` itself and run against a forty-sentence fixture, so what is tested
is the elisp's own queries rather than a copy that could drift from them.

`classicist-architecture.md` is the reasoning, including the things that turned
out to be wrong.

## Licence and credits

GPL-3.0-or-later, as `diogenes.el` is.

- **Peter Heslin**, for [Diogenes][diogenes] — the databases, the Perl, the
  morphology, and thirty years of it.
- **Michael Neidhart**, for [diogenes.el][base] — the Emacs interface this suite
  is built on and extends, and the author of the five files named above.
- The **Diorisis Ancient Greek Corpus** (Vatri & McGillivray), the **Perseus
  Digital Library**, the **First Thousand Years of Greek** project, and the
  **Ancient Greek and Latin Dependency Treebank**, whose data the corresponding
  features read.
- The scanned and encoded dictionaries are the work of their own editors and
  digitisers; this suite only opens them.

[diogenes]: https://d.iogen.es/
[base]: https://github.com/nitardus/diogenes.el
[fork]: https://github.com/VictorSousa92/diogenes.el/tree/classicist-base
[roam]: https://github.com/VictorSousa92/diogenes-roam/tree/classicist-roam
[orgreadme]: https://github.com/VictorSousa92/diogenes.el/tree/org-integration
[morpheus]: https://github.com/VictorSousa92/morpheus
[installing]: INSTALLING.md
[builder]: https://victorsousa92.github.io/emacs-classicist-suite/tools/classicist-builder.html
