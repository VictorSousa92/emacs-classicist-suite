# Reading a text

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

### Editions as TEI

`bt` browses editions that are not Diogenes': Perseus, the First Thousand Years
of Greek, the CSEL. Point `tei-directory` at a tree of TEI files and it lists
the corpora, then the works, then the versions of a work. Reading is done by
`tei-read.py`, which needs Python on `PATH`.

Citations in a dictionary entry can open here as well as in Diogenes' own
corpora — `classicist-lookup-open-greek-with` sets the order in which the three
are tried.
