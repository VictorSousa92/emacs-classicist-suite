# Looking a word up

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

### Looking a word up from anywhere

A Greek or Latin word turns up in notes, in a LaTeX file, in a mail. `C-c l l`
looks it up and guesses the language, `C-c l g` forces Greek, `C-c l a` Latin,
`C-c l d` asks which dictionary, and `C-M-click` is the gesture. Under evil
these work in every state; in Doom and Spacemacs they are on the leader as
well, under `SPC o l`.

`classicist-global-keys` set to nil binds nothing — these are under `C-c`,
which is a reader's own space.

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

### The printed dictionaries

Twelve of them, in two kinds.

**As entries**, from TEI XML: Bailly, Georges, Gaffiot, the DGE, Pape. These
behave like the LSJ — a formatted entry, clickable citations, keys to every
other dictionary. Some need a one-off conversion from the source file, which
the relevant `-source-file` option points at.

> **The DGE wants New Athena Unicode for some glyphs.** It sets epigraphic
> letterforms in the **private-use area**, which by definition no other font
> can supply — twenty-two characters in all, and without that font they show
> as boxes. Fifteen occur only in quoted text; seven occur in lemmas, in
> thirty-eight entries.
>
> **What to add.** Install [New Athena Unicode][nau], then give Emacs that font
> for the private-use area alone — the block runs `E000`–`F8FF`:
>
> ```elisp
> (set-fontset-font t '(#xE000 . #xF8FF) "New Athena Unicode" nil 'prepend)
> ```
>
> Only for that range, so whatever you have chosen for Greek keeps the rest of
> the entry. `prepend` puts it ahead of anything already set for those
> characters.
>
> **Looking a word up works regardless**, and needs no font at all. Those seven
> are known by their epichoric value — `diogenes-dge-epichoric-substitutions`,
> each one vouched for by the DGE's own `xml:id`, which spells the character
> out: `διαιτατ<E1B4>ρ` is normalised to `διαιτατερ`. So the lemma is keyed
> correctly whether or not you can see the glyph. The font is for reading the
> entry, not for finding it.

**As pages**, from scans: the OLD, the TLL, Montanari, the CGL, BDAG, Passow,
the TGL, and the printed Gaffiot, Georges and Bailly. These open a PDF at the
page the headword is on, found through a prebuilt index where one exists.

Which appear is governed by `classicist-declared-dictionaries`, not by whether
the files are present — so a key tells you what to configure rather than doing
nothing. Set no dictionary paths at all and the suite offers what the base
does: the LSJ, Lewis & Short, the morphology and the corpora, with no links
line and no keys leading nowhere.

`diogenes-old-pdf-viewer` chooses the viewer: `pdf-tools`, the built-in
`doc-view`, or [EMuReader][emureader], which renders with MuPDF. The scans
are OCR'd to varying standards and their bookmarks are not always reliable, so
a lookup lands on the right page more often than on the right column.

> **EMuReader wants 0.4.0 or later.** It was called the Emacs Reader until that
> release, which renamed every symbol from `reader-` to `emureader-` and
> shipped **no obsolete aliases** — so no version answers to both, and the
> suite names the new ones. On 0.3 each of them is a void function. The
> repository moved with the name, to
> [codeberg.org/MonadicSheep/emureader][emureader]. The option's value stays
> `emacs-reader`, since that is the word a reader who set it will have set.
>
> **One thing it cannot do**: the reverse lookup `L`, which reads the word
> under point out of the PDF's text layer. EMuReader renders pages as images
> and exposes no text, so `L` wants `pdf-tools`. The forward openers — a
> lookup landing on the right page — work with every viewer.

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

[nau]: https://classicalstudies.org/publications-and-research/about-new-athena-unicode
[emureader]: https://codeberg.org/MonadicSheep/emureader
[orgreadme]: https://github.com/VictorSousa92/diogenes.el/tree/org-integration
[morpheus]: https://github.com/VictorSousa92/morpheus
