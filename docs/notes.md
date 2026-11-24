# Notes joined to passages

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

Everything here is configurable. `M-x customize-group classicist-phi-notes`
lists every option, each with the reasoning in its docstring.

**With `window-purpose` loaded, `classicist-phi-purpose` is what decides
where a note goes** — and nothing else does. Purpose advises `display-buffer`
and answers before any action of the suite's is consulted, so neither the
behaviour, nor a preset, nor `classicist-phi-display-action` is reached. A
note it has never heard of is filed under `general` and shown in the window
you were reading in, which is why notes are given a purpose of their own.

**A wikilink in one of our notes is followed by us**, not by phi-notes, and
that is `classicist-phi-own-buttons`. His own action for a `[[0002]]` ends
`(if phi-sidebar-persistent-window (delete-other-windows))` — which suits a
sidebar that stays and one note filling the space beside it, and clears the
browser along with everything else. Set the option to nil to keep his
arrangement. Either way only notes carrying one of the reference fields are
touched, so a Zettelkasten of notes about other things behaves as it always
did.

[phi]: https://github.com/brunocbr/phi-notes
