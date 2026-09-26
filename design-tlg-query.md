# A query builder for the TLG

What the TLG's own web interface calls ADVANCED PROXIMITY: three elements,
each a word index (`WI`), a lemma (`L`) or a grammatical category (`G`),
joined by *and*/*or*, within so many words. This is a design for the same
thing over Diogenes' corpora, without the limit of three, and it is
reachable from what the base already has.

## What already exists, and why this is not a large piece of work

**A Diogenes search takes a LIST of patterns.** Not one:

    :pattern-list   every pattern must appear
    :reject-pattern one that must not
    :context        "sent", "para", or a number of LINES
    :min-matches    how many of them in that context

That *is* the proximity mechanism. `diogenes--do-search` and
`diogenes--do-wordlist-search` both take it, and the second is what the TLG
uses. There is no three-element limit to lift: a list is a list.

**And a lemma expands into forms with no lemmatised corpus.**

    (diogenes--get-all-forms LEMMA LANG)
      => a list of entries, one per homograph
         (LEMMA RAW-LEMMA LEMMA-NR . ANALYSES)
         where each analysis is (FORM . (PARSE ...))

So the lemma is expanded on the LEMMA side, out of the Perseus word lists
and Morpheus, and the corpus is searched for the resulting forms. Nothing
about the corpus need be lemmatised. `diogenes--lemma-forms-list` already
wraps this, and `diogenes--morphological-search` already searches the TLG
with the result.

**Which means the analyses are in hand for filtering.** Each form comes with
its parse -- that is what the form-selection buffer annotates the candidates
with -- so `aorist participles of λέγω` is a filter over a list that has
already been fetched, not a second query.

## The four kinds of element

| | | how it becomes a pattern |
|---|---|---|
| `WI` | a form, or a regexp | itself |
| `L` | every form of a lemma | expand, join as `\|` alternation |
| `L`+`G` | the forms that match a parse | expand, FILTER, then join |
| `not` | a form that must not appear | `:reject-pattern` |

Each element is one pattern; every pattern goes into `:pattern-list`; the
proximity is `:context` with `:min-matches`.

### Pure `G` is not possible on the TLG, and that is the boundary

`any aorist participle` needs every token in the corpus parsed. That is what
Diorisis IS and what the TLG is not. So:

* `G` qualified by a lemma  -> the whole TLG, by filtered expansion
* `G` unqualified           -> Diorisis, where every token carries its parse

The builder should say this rather than offer a `G` that silently means
something narrower. A line in the buffer -- *a category alone wants
Diorisis; press `D`* -- and an offer to hand the query over.

## What Diorisis already does, and where each belongs

`diorisis-query` is this builder for the Diorisis corpus and is STRICTLY MORE
CAPABLE than the TLG's interface: unlimited elements; form, lemma,
morphology and punctuation; and distance measured in WORDS **or in
syntactic nodes**, which no TLG interface can do.

So the two are complements, not rivals:

* **the TLG** -- a hundred million words, no parse. `WI`, `L`, `L`+`G`,
  proximity by sentence, paragraph or line.
* **Diorisis** -- ten million words, every token parsed and in a tree. Any
  combination, and distance in nodes.

The builder should be able to send the same query to either, and say what is
lost in each direction: a `G` element cannot go to the TLG, and the TLG's
sub-corpus of forty authors cannot go to Diorisis, whose `--text` takes one
author or one work.

## One honest mismatch

The TLG says *within 5 words*. Diogenes counts **sentences, paragraphs and
lines** -- `:context` takes `"sent"`, `"para"` or a number, and the number is
lines. Words are not available on that side.

So the builder offers what the engine has. A reader who wants words is in
Diorisis' territory, where `:count` and `:scope` already measure both words
and nodes.

## Sub-corpora

* **The TLG side is the strong one.** `diogenes--search-select-authors`
  builds a custom corpus of any authors and works, and the search takes it as
  `:author-nums`. Combining works of different authors already works.
* **Diorisis is the weak one.** `--text` takes one author, or one work of
  one author, and nothing more. A LIST of texts is the addition wanted
  there, and it is a change to `diorisis--where` rather than to the builder.

## What to build, in order

1. **The element reader.** Four kinds; for `L` and `L`+`G`, expand and show
   the count -- *`λέγω`: 447 forms* -- because a reader should see the size of
   what they have asked for before it is searched.
2. **The morphology filter.** Over the analyses already fetched. The feature
   vocabulary is the one `diorisis-read-morphology' uses, which asks one
   feature at a time and drops what cannot go with what has been chosen.
3. **The query buffer.** `diorisis-query`'s, which is written and works:
   elements listed, `a` to add, `d` to delete, `c` to clear, `RET` to run.
   Worth sharing the buffer rather than writing a second one.
4. **The assembly.** Patterns into `:pattern-list`, the negative into
   `:reject-pattern`, the proximity into `:context` and `:min-matches`.
5. **The hand-over to Diorisis**, for a query the TLG cannot answer.

## Two things to verify before writing

* Whether `:pattern-list` patterns are REGEXPS on the Perl side. The whole
  design rests on an alternation being a legal pattern, and nothing read so
  far says it in as many words. `diogenes--do-search` passes them to the Perl
  module; the module's own documentation is the authority.
* How large an alternation the search will take. `λέγω` has hundreds of
  forms; a common verb may have thousands, and a regexp of a thousand
  alternatives may be slower than the corpus read it is meant to save.
  Worth measuring before promising it, and worth a limit with a word to the
  reader if it is.
