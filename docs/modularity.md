# Choosing what is awake

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

[phi]: https://github.com/brunocbr/phi-notes
