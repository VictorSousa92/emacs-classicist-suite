# Tools for reading Greek and Latin in Emacs

A suite built on Michael Neidhart's [diogenes.el][base], which drives Peter
Heslin's [Diogenes][diogenes]. Eight things, and you choose which are awake:

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

**The last two corpora want no Diogenes data.** Diorisis and the TEI editions
read their own, so a reader with no CD-ROMs can set two paths and have a Greek
corpus search and a reader for the editions.

## Installing

Two packages, and a configuration builder that writes the block for you:

    tools/classicist-builder.html

Open it in a browser. It asks which Emacs you run, whether you want the fixes
only or everything, and which features you want; it writes the `use-package`
form and the paths. Nothing is uploaded — it runs in the page.

`INSTALLING.md` has what to try first on each of plain Emacs, Doom, Spacemacs
and Windows.

### The base wants nine patches

The suite extends `diogenes.el` and relies on nine fixes not yet in the
original. Until they are merged, install the base from
[`VictorSousa92/diogenes.el`][fork] branch `classicist-base`.

    M-x classicist-check-base

says whether a given installation will do. It probes the three that fail
*quietly* rather than trusting a version number.

## What is awake

    (setq classicist-features '(texts lexica))

is the default, and is what Diogenes itself does: a browser and a dictionary.
Everything else is loaded and asleep — no keys, no menu entries, nothing
offered. Three of the eight want another:

    M-x classicist-check-features

says so if one does not have what it wants.

## Presets

A preset is where the windows go, kept in a file you load when you want it
rather than in your init file. Four ship — `defer`, `reuse`, `split`,
`frames` — and the builder's second tab writes your own, with a simulator that
shows what each does to a frame.

## Two packages kept beside it

[`diogenes-books`][books] answers which of an author's works you own.
[`diogenes-roam`][roam] files a passage note under its author and its work,
and keeps an index of them — branch `classicist-roam` for the version that
works with this suite. Neither is required; both are noticed where present.

## Building it

    make check

runs six gates: the compile ratchet per file, every `declare-function` against
its definition, anything defined in more than one file, every symbol the
builder emits, and the SQL — which is extracted from `diorisis.el` and run
against a forty-sentence fixture, so what is tested is the elisp's own queries
and not a copy that could drift from them.

`classicist-architecture.md` is why the code is arranged as it is, including
the mistakes.

## Licence

GPL-3.0-or-later, as `diogenes.el` is.

[base]: https://github.com/nitardus/diogenes.el
[diogenes]: https://d.iogen.es/
[fork]: https://github.com/VictorSousa92/diogenes.el/tree/classicist-base
[books]: https://github.com/VictorSousa92/diogenes-books
[roam]: https://github.com/VictorSousa92/diogenes-roam/tree/classicist-roam
