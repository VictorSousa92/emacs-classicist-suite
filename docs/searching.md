# Searching the corpora

### A query of several elements

`q`, inside any SEARCH entry. What the TLG's own interface calls an advanced
proximity search, without its limit of three: a word, a lemma, a lemma
narrowed by morphology, a lemma whose forms you pick by hand, or a word that
must **not** appear — as many as you like, within a sentence, a paragraph, or
so many lines.

    a   add an element        f   show what it expanded to
    d   delete the one at point
    n   how near they must be
    RET search                D   take it to the Diorisis corpus
    S   save                  l   load a saved one

A lemma needs nothing lemmatised. It is expanded into its attested forms out
of the Perseus word lists, and the corpus is searched for those — so the TLG's
hundred million words are searchable by lemma although not a word of them is
tagged. `f` shows you what an element became: the forms, the Greek beside the
beta code, and the pattern the search engine is actually given.

Three ways to narrow a lemma, and they compose. Every form; or by morphology,
asked as a hierarchy — part of speech, then for a verb whether it is finite, a
participle or an infinitive, and only then the categories that can still
apply, a participle having no person and an infinitive neither person nor
case; or by hand, in the same checkbox buffer the base uses, which can say
what a filter cannot: a dialect form, an elision, this aorist and not that.
Nothing is required at any step, so the plurals of a word whether participle
or finite is three answers.

**One boundary.** A morphology with no lemma — *any aorist participle* — wants
every token in the corpus parsed, which is what the Diorisis corpus is and the
TLG is not. `D` hands the query there, where every token carries its parse and
distance can be counted in syntactic nodes; ten million words against a
hundred, which is the trade.

Queries are saved beside the other searches, one `.eld` to a search in
`diorisis-saved-directory`, and `l` lists them.

### In a search result

A result has two kinds of line, and they now behave differently. A click on
the header — the author, work, edition and citation — opens the passage, that
being the one thing in a result that names where to go. `C-M-click` anywhere
looks the word up. `C-c C-c` browses, as before.

The match itself is coloured rather than left between the arrows Diogenes
sends (`->Eu<-melos`), and is marked for Emacs either way so a command can
find it: `diogenes-search-mark-matches` set to `arrows` gives the old
appearance back.

`classicist-search-header-links`, `classicist-search-mouse-keys`,
`classicist-search-double-click` and `classicist-search-keys` adjust all of
this, and the builder's *Clicking a word* section sets them without editing
elisp.
