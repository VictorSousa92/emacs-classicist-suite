# Where the data comes from

Everything named here is free to download, and none of it ships with the
suite. The corpora Diogenes reads are licensed separately and are its own
business; what follows is what the other features want.

### Corpora

| | |
|---|---|
| **Diorisis Ancient Greek Corpus** | <https://doi.org/10.6084/m9.figshare.6187256> — ten million lemmatised words, Vatri and McGillivray's own release. `tools/diorisis-index.py` turns its XML into the database `diorisis-database` names |
| **Diorisis as DuckDB** | <https://zenodo.org/records/11261146> — Bilby's compilation of the same corpus, and the input to the merge described below |
| **First Thousand Years of Greek** | <https://github.com/opengreekandlatin/First1KGreek> |
| **Perseus Greek** | <https://github.com/PerseusDL/canonical-greekLit> |
| **Perseus Latin** | <https://github.com/PerseusDL/canonical-latinLit> |

The last three are TEI and are what `tei-directory` expects;
`tools/tei-index.py` builds the index the browser reads them through.

### Two Diorisis databases, and why

The corpus is published as XML and as a DuckDB compilation, and they hold
different things. Ours — built from the XML by `tools/diorisis-index.py` — has
the **citation**, which is what makes a hit a passage you can open. Bilby's has
the morphology decomposed into a column per category, and two things nothing
else here carries: the **dialect** (Attic, Epic, Ionic) and the **prosody**
(proclitic, enclitic). What it does not have is a citation: its `location` is
the place of composition, and its word table has sentence and word ids and
nothing that says `1.19.5`.

    python3 tools/diorisis-merge-duckdb.py DIORISIS.DUCKDB DIORISIS.DB

carries theirs onto ours. Ours is the spine and theirs is what comes across,
rather than the other way about — a hit must remain a passage, which is the
whole argument for doing any of this in an editor.

**The pairing is positional and checked.** Both releases were made from the
same TEI, and the arithmetic bears it out: their word rows less their
punctuation rows give the corpus's published count to the digit. So tokens are
paired sentence by sentence in document order — and then verified, because
positional pairing is only as good as its check. For each sentence the counts
must agree, and each pair's forms must agree as skeletons, the Greek letters
with the diacritics and breathings thrown away. A sentence that fails is
skipped and counted; a text that mostly fails is skipped whole and named.
Being short of the dialect for one text is nothing; attaching the wrong
analysis to the right citation would be worse than either database alone, and
would be invisible.

Set `diorisis-merged-database` to the result and turn on
`diorisis-use-merged` to search the extra columns. Neither is
required: the plain database is the whole corpus and answers every search in
[The Diorisis corpus](diorisis.md#the-diorisis-corpus) above.

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
| **OLD** | [the first edition at the Internet Archive][old] | the PDF outline, whose bookmarks are the printed running heads. This is what the upstream Diogenes build tools rely on, and that copy carries them |
| **TLL** | [the open-access fascicles from the BAdW][tll] | the same, one file per fascicle |
| **Montanari** | | an interval per page, `288: άραιρη- – Άραυάκαι`, some pages a single word. OCR'd, so accents cannot be trusted and comparison ignores them |
| **BDAG** | 4th ed., [Isidore's Calibre library][bdag] | an interval, `2: ἀβροχία - ἀγαθός`; letter-openings and long entries carry one word. Clean accented Greek, so compared strictly |
| **CGL** | | **one** guide word per page, `3: άγακτίμενος`, numbered sequentially — and which word it is depends on the **parity** of that number: even gives the page's first headword, odd its last, except the first odd bookmark of a letter, which opens the letter |
| **Georges** | 1913, [zeno.org][georges] | one bookmark per page naming **every** entry on it — `Bd1_Sp0005-0006_a-3_abacinus_abactio_…` — some 43,000 headword-to-page pairs |
| **Bailly** | typeset *Bailly 2020 – Hugo Chávez*, [Gérard Gréco][bailly] | its bookmarks name a word *somewhere* on the page rather than its bounds, so the index comes from the **running heads** instead, read from the text layer |
| **Passow** | the four half-volumes at the MDZ: [1.1][pa1], [1.2][pa2], [2.1][pa3], [2.2][pa4] | as Montanari, from the bookmarks |
| **TGL** | Estienne's five tomes at the MDZ: [I][tgl1], [II][tgl2], [III][tgl3], [IIII][tgl4], [V][tgl5] | its bookmarks are the least reliable of any here, so the page is reconstructed from the column numbers instead — a folio prints two columns, so `left-column = 2 × page + b` |

Each regexp is an ordinary option, so a copy bookmarked differently can be
read by adjusting one: group 1 the first headword, group 2 the last, and for
the CGL group 1 the number and group 2 the word.
`M-x diogenes-montanari-show-bookmarks` and its equivalents print what the
package can read from your PDF, which is the quickest way to find out whether
a copy will work at all.

**Passow and the TGL want a volume per subdirectory**, each holding the PDF
and, for the TGL, the OCR text the column reconstruction reads — the MDZ
download gives both. The identifiers above are the ones tested here; the MDZ
holds more than one digitisation of the TGL, and the page reconstruction was
written against these.

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
  [built yourself](dictionaries.md#morpheus-for-the-forms-neither-table-names).
- **phi-notes** — <https://github.com/brunocbr/phi-notes>.

[bdag]: https://isidore.co/CalibreLibrary/Bauer,%20Walter/A%20Greek-English%20Lexicon%20of%20the%20New%20Testament%20and%20Other%20Early%20Christian%20Literature%20(BDAG%204th%20ed%20(10226)/
[georges]: http://www.zeno.org/Georges-1913
[bailly]: http://gerardgreco.free.fr/spip.php?article24&lang=fr
[old]: https://archive.org/details/oxford-latin-dictionary
[tll]: https://thesaurus.badw.de/tll-digital/tll-open-access.html
[pa1]: https://www.digitale-sammlungen.de/en/view/bsb10808500
[pa2]: https://www.digitale-sammlungen.de/en/view/bsb10808501
[pa3]: https://www.digitale-sammlungen.de/en/view/bsb10808502
[pa4]: https://www.digitale-sammlungen.de/en/view/bsb10808503
[tgl1]: https://www.digitale-sammlungen.de/en/view/bsb11202465
[tgl2]: https://www.digitale-sammlungen.de/en/view/bsb11202466
[tgl3]: https://www.digitale-sammlungen.de/en/view/bsb11912165
[tgl4]: https://www.digitale-sammlungen.de/en/view/bsb11912166
[tgl5]: https://www.digitale-sammlungen.de/en/view/bsb11202469
