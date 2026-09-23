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
- [Where the data comes from](#where-the-data-comes-from)
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

Eleven features, and you name the ones you want — see
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

**Nothing you did not ask for.** The suite is one package of eleven features,
and you name the ones you want:

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
| `phi-notes` | the same three things in [phi-notes][phi] instead — markdown, a frontmatter and wikilinks. An **alternative** to `notes`, not an addition |
| `windows` | the suite placing buffers, rather than leaving that to whatever you have arranged |

### Four want another

Seven of the eleven stand alone. Four do not:

- **`treebank`** wants **`diorisis`** — it annotates that corpus's sentences,
  reads its file, and puts its keys in its results buffer.
- **`dictionaries`** wants **`lexica`** — the printed ones are reached from the
  banner at the head of an LSJ or Lewis & Short entry.
- **`notes`** wants **`texts`** or **`tei-corpora`** — a note is about a
  passage, and either browser will do.
- **`phi-notes`** wants the same, for the same reason — and the phi-notes
  package itself, which is its own and installed separately.

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

Two note systems, and they are alternatives rather than additions: a reader
keeps one Zettelkasten, not two. `notes` wakes the org commands, `phi-notes`
the markdown ones.

**In org.** `diogenes-org-note` writes a note about the passage in hand and
`diogenes-org-notes` shows what has been said about these lines. A note carries
an org link back, so the passage and the note each reach the other.

**In [phi-notes][phi].** For a reader whose Zettelkasten is already markdown,
a YAML-ish frontmatter and `[[0002]]` wikilinks. Five commands, all from a
browser buffer:

| | |
|---|---|
| `C-c n n` | a note on the passage in hand |
| `C-c n l` | list the notes on this work, and open one |
| `C-c n w` | the work's own note |
| `C-c n i` | write the index of this work into that note |
| `C-c n s` | show it beside the text, and hide it again |

A note comes out as one of his, in his own `tlg-text` type, with the citation
already in the fields:

    ---
    title: "A.R. 1.23-1.24"
    id:    0002
    ref_tlg: 0001:001
    section: 1
    line:    23-24
    tags: #π #A.R. #Arg. #tlg0001.001
    ...

    △[[0001]]

so everything of his reads it without knowing this exists — `phi-backlinks`,
`helm-phi-find`, the tag search, the wikilinks. His `ref_tlg` spelling is kept
exactly; the other corpora follow the pattern through
`classicist-phi-ref-fields`.

**The work's note is the index.** `0001` above is a note for the
*Argonautica* as a whole, and every passage note links to it as parent, so
`phi-backlinks` on it lists everything said about that text. `C-c n i` also
writes the list into it, ordered by citation:

    <!-- classicist:index -->
    - [[0003]] 1.1
    - [[0004]] 1.5-1.6
    - [[0002]] 1.23-1.24
    <!-- /classicist:index -->

Only what lies between those markers is replaced, and only when both are
found — a note without them gets no index and no complaint, and `C-c n i`
offers to add them rather than guessing where in a reader's prose an index
belongs. It is written by hand and not by a save hook, deliberately: a hook
that rewrites a buffer while it is being typed in should be opted into after
the writing is trusted.

`C-c n s` puts that note in a side window on an edge you pick, and a second
press hides it. The buffer is left alone either way, so nothing is asked about
saving.

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

## Developing

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

## Where the data comes from

Everything named here is free to download, and none of it ships with the
suite. The corpora Diogenes reads are licensed separately and are its own
business; what follows is what the other features want.

### Corpora

| | |
|---|---|
| **Diorisis Ancient Greek Corpus** | <https://doi.org/10.6084/m9.figshare.6187256> — ten million lemmatised words, Vatri and McGillivray's own release |
| **Diorisis as DuckDB** | <https://zenodo.org/records/11261146> — the same corpus already in a database, which is what to point the merge at rather than parsing the XML afresh |
| **First Thousand Years of Greek** | <https://github.com/opengreekandlatin/First1KGreek> |
| **Perseus Greek** | <https://github.com/PerseusDL/canonical-greekLit> |
| **Perseus Latin** | <https://github.com/PerseusDL/canonical-latinLit> |

The last three are TEI and are what `tei-directory` expects.

### Dictionaries

The LSJ and Lewis & Short come with Diogenes. The rest are other people's
digitisations, and the source decides how much work is involved.

**Already TEI, and built directly:**

- **The DGE** — <https://github.com/dge-csic/xdge_xml>, the CSIC's own XML,
  one file per volume, 112 MB in all. `classicist-dge-source-file` takes a
  file, a directory or a list.
- **Gaffiot** — <https://digital-gaffiot.sourceforge.net/>, needing no
  conversion but proofread as far as **F** only, some 28,000 entries.

**Databases, which have to be turned into TEI first:**

- **Pape, Gaffiot and Georges** — the FDB databases published by the Institut
  für Klassische Philologie at Zürich,
  <https://www.iaka.uzh.ch/de/klph/it/mls.html>. More work than the TEI above,
  and the Gaffiot among them is **complete, A–Z**, which is the trade.
- **Bailly** — built from the GoldenDict version at
  <https://chaerephon.e-monsite.com/pages/litterature/grec-ancien/bailly2020.html>.

**Scans, for the page lookups.** Supply your own; nothing is shipped. And
*which* copy matters, because the page is found from the PDF's own bookmarks
and every edition bookmarks itself differently. The copies these were written
against:

| | Copy | How its pages are found |
|---|---|---|
| **OLD** | a first edition | the PDF outline, whose bookmarks are the printed running heads. This is what the upstream Diogenes build tools rely on |
| **TLL** | | the same |
| **Montanari** | | an interval per page, `288: άραιρη- – Άραυάκαι`, some pages a single word. OCR'd, so accents cannot be trusted and comparison ignores them |
| **BDAG** | 4th ed., [Isidore's Calibre library][bdag] | an interval, `2: ἀβροχία - ἀγαθός`; letter-openings and long entries carry one word. Clean accented Greek, so compared strictly |
| **CGL** | | **one** guide word per page, `3: άγακτίμενος`, numbered sequentially — and which word it is depends on the **parity** of that number: even gives the page's first headword, odd its last, except the first odd bookmark of a letter, which opens the letter |
| **Georges** | 1913, [zeno.org][georges] | one bookmark per page naming **every** entry on it — `Bd1_Sp0005-0006_a-3_abacinus_abactio_…` — some 43,000 headword-to-page pairs |
| **Bailly** | typeset *Bailly 2020 – Hugo Chávez*, [Gérard Gréco][bailly] | its bookmarks name a word *somewhere* on the page rather than its bounds, so the index comes from the **running heads** instead, read from the text layer |
| **TGL**, **Passow** | OCR'd MDZ volumes, [Bavarian State Library][mdz] | the TGL's bookmarks are the least reliable of any here, so the page is reconstructed from the column numbers instead — a folio prints two columns, so `left-column = 2 × page + b` |

Each regexp is an ordinary option, so a copy bookmarked differently can be
read by adjusting one: group 1 the first headword, group 2 the last, and for
the CGL group 1 the number and group 2 the word.
`M-x diogenes-montanari-show-bookmarks` and its equivalents print what the
package can read from your PDF, which is the quickest way to find out whether
a copy will work at all.

These are scans of old print books. Expect dropped letters, misread
diacritics, columns out of order and wrong bookmarks — a lookup lands on the
right page more often than on the right column.

### Annotation

- **Arethusa** — <https://github.com/alpheios-project/arethusa/>, the tree
  editor `tools/viewer` serves a sentence to.
- **The Ancient Greek and Latin Dependency Treebank** is the format the
  treebank feature reads and writes.

### And the programs underneath

- **Diogenes** — <https://d.iogen.es/>, and its source at
  <https://github.com/pjheslin/diogenes>.
- **`diogenes.el`** — <https://github.com/nitardus/diogenes.el>.
- **Morpheus** — <https://github.com/VictorSousa92/morpheus>, source only, and
  [built yourself](#morpheus-for-the-forms-neither-table-names).
- **phi-notes** — <https://github.com/brunocbr/phi-notes>.

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
[phi]: https://github.com/brunocbr/phi-notes
[bdag]: https://isidore.co/CalibreLibrary/Bauer,%20Walter/A%20Greek-English%20Lexicon%20of%20the%20New%20Testament%20and%20Other%20Early%20Christian%20Literature%20(BDAG%204th%20ed%20(10226)/
[georges]: http://www.zeno.org/Georges-1913
[bailly]: http://gerardgreco.free.fr/spip.php?article24&lang=fr
[mdz]: https://www.digitale-sammlungen.de/en/
[installing]: INSTALLING.md
[builder]: https://victorsousa92.github.io/emacs-classicist-suite/tools/classicist-builder.html
