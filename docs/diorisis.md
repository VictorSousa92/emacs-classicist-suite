# The Diorisis corpus and the treebank

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

The tree is also drawn in Emacs, as an SVG. **An SVG cannot see Emacs' faces**,
so the Greek has to be named by family rather than inherited: if the drawing
comes out in boxes while the buffer's Greek is fine, that is why.
`treebank-svg-greek-fonts` is the order tried — New Athena Unicode, then Brill,
then GFS Porson — and all of them are offered to fontconfig at once, which
knows better than Emacs which are installed. A Greek font set in your own
configuration is preferred to any of them; `treebank-svg-greek-font` forces one
outright.

`tools/viewer` serves the tree to Arethusa in a browser, with `serve.py` —
which answers the tree by URL, accepts a write back, and binds to 127.0.0.1.
Its own README explains why `python3 -m http.server` is no longer enough.
