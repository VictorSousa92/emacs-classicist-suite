# Tools for reading Greek and Latin in Emacs

Browse and search the TLG and the PHI, look a word up in a dozen dictionaries,
parse it, read the Perseus editions as TEI, search ten million lemmatised words
of Greek, annotate a sentence as a dependency tree, and keep notes joined to the
passages they are about — without leaving Emacs.

**On Windows?** Read [`INSTALLING.md`'s Windows section][windows] before you
begin. Most of what goes wrong there fails without saying why.

## What it adds

Eleven features, and you name the ones you want — see
[Modularity](docs/modularity.md). The default is the two that
match what `diogenes.el` itself does.

| | |
|---|---|
| **Diogenes' corpora** | browsing and searching the TLG, the PHI, the papyri, the inscriptions — including [queries of several elements](docs/searching.md#a-query-of-several-elements) |
| **The LSJ and Lewis & Short** | a word looked up, parsed, and every form it is attested in |
| **Lemma completion** | a lemma prompt completing on the word list: 63,718 Greek lemmata with their frequencies, matched by beta code or Greek with the diacritics optional |
| **The printed dictionaries** | Bailly, the OLD, the TLL, Montanari, the DGE, the Cambridge, BDAG, Passow, the TGL, Gaffiot, Georges, Pape |
| **The Diorisis corpus** | ten million lemmatised words of Greek, searched by lemma, form, morphology and date |
| **Treebank annotation** | a sentence as a dependency tree, as ALDT or CoNLL-U |
| **Editions as TEI** | Perseus, the First Thousand Years of Greek, the CSEL |
| **Books by their own names** | a work opened at one of its books by the letter a classicist uses — *Theta* and not `1045b27`. The corpora do not know books; the text carries their titles, and this reads them |
| **Notes in org** | a note on the passage in hand, and what has been said about these lines |
| **Notes in phi-notes** | the same three things in Bruno Conte's `phi-notes` instead — markdown, a YAML-ish frontmatter, wikilinks. An **alternative** to the org notes and not an addition: a reader keeps one Zettelkasten, not two. Wants that package, which is its own |
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
  [Installing](#the-base-wants-its-corrections).
- **sqlite**, built into Emacs 29 and later, for Diorisis. `(sqlite-available-p)`
  says whether you have it.
- **Python 3** on `PATH`, for reading TEI.
- **A font with polytonic Greek.** Beta code is ASCII and always renders, but
  the corpus text, the dictionary entries and the lemma prompts are accented
  Greek, and a font without polytonic coverage gives you empty boxes.
  [New Athena Unicode][nau], Brill and GFS Porson all have it. Emacs is told
  which to use for the Greek script, not by this package:

      (set-fontset-font t 'greek "New Athena Unicode")

  **New Athena Unicode in particular** if you want the DGE: it sets epigraphic
  letterforms in the private-use area, which by definition no other font can
  supply. Looking a word up works without it — see
  [The printed dictionaries](docs/dictionaries.md#the-printed-dictionaries).
- Optional: Ghostscript or poppler for the scanned dictionaries, and
  [Morpheus][morpheus] if you want a parser beyond the shipped word lists —
  it is source only, so you build it yourself; see
  [Morpheus](docs/dictionaries.md#morpheus-for-the-forms-neither-table-names).

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

### The base wants its corrections

The suite relies on corrections to `diogenes.el` that are not yet in the
original, and several it cannot do without. Until they are merged, install the
base from [`VictorSousa92/diogenes.el`][fork], branch `classicist-base`.

Some are plain defects — a function called under a name it does not have, a
format string given two arguments for one field. Others are **extension
points**: the Perl variables and include flags moved into the Perl interface,
the word lists given a file of their own, a way for a caller to place its own
buffer. The suite inherits those files rather than replacing them, so it calls
into them rather than surviving without them.

    M-x classicist-check-base

is the authority on whether a given installation will do. It probes the ones
that fail *quietly* — where the wrong answer looks like no answer — rather
than trusting a version number, which is also why no count is quoted here:
the branch grows as things are found, and a figure in a README goes stale
while the probe does not.

Everything in that branch is a fix or an extension point, not a rewrite: the
intention is that it becomes unnecessary.

### Then read INSTALLING.md

**[`INSTALLING.md`][installing]** has the rest: what to run first whichever
Emacs, the per-distribution notes, and a section each for Linux, macOS and
Windows.

> **On Windows, read [the Windows section][windows] first.** Not as a
> formality: three of the things it records cost an evening each to find, and
> none of them fails in a way that points at its cause. A backslash in a path
> is dropped silently and the error names a directory that looks almost right.
> MSYS2's `$HOME` is not the Windows home, so Doom and Spacemacs look where
> nothing is, fail during startup, and leave what appears to be a plain Emacs
> with no error in sight. And a search that takes thirty seconds is usually
> Windows Defender scanning the index rather than anything to do with Emacs.
>
> It also wants MSYS2 with its native `mingw64` Emacs, `git` and Python, and
> four settings that answer for the Perl Diogenes bundles and for a GUI Emacs
> inheriting no shell environment. The builder writes those four when you tick
> the Windows box; the rest is reading.

## The documentation

| | |
|---|---|
| [Choosing what is awake](docs/modularity.md) | which of the eleven features you want, and what each wants in turn |
| [Searching the corpora](docs/searching.md) | a query of several elements, and what a result does |
| [Reading a text](docs/reading.md) | the browser, `C-c C-c` on anything, the TEI editions |
| [Looking a word up](docs/dictionaries.md) | the dictionaries, the scans, and what to do when an analysis is wrong |
| [The Diorisis corpus and the treebank](docs/diorisis.md) | ten million parsed words, and a sentence as a tree |
| [Notes joined to passages](docs/notes.md) | org-roam or phi-notes, filed by author and work |
| [The keys, and evil](docs/keys.md) | finding a key you have forgotten, and the Emacs-state buffers |
| [Where the windows go](docs/windows.md) | behaviours, presets, and the configuration builder |
| [Where the data comes from](docs/data.md) | every corpus, dictionary and scan, and where to get it |
| [Developing](docs/developing.md) | the gates, the base's corrections, the files that are Neidhart's |

The same pages are published as [the wiki][wiki], generated from `docs/` by
`tools/publish-wiki.sh` — so the two cannot disagree. **Edit `docs/`**: a wiki
edited by hand loses its edits at the next push, and a wiki is a repository of
its own, so a change there could never be in the same commit as the code it
describes.

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
[nau]: https://classicalstudies.org/publications-and-research/about-new-athena-unicode
[morpheus]: https://github.com/VictorSousa92/morpheus
[installing]: docs/installing.md
[wiki]: https://github.com/VictorSousa92/emacs-classicist-suite/wiki
[windows]: docs/installing.md#windows
[builder]: https://victorsousa92.github.io/emacs-classicist-suite/tools/classicist-builder.html
