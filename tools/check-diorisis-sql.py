#!/usr/bin/env python3
"""check-diorisis-sql.py -- run the elisp's own SQL against a fixture.

WHY THE SQL IS READ OUT OF THE ELISP.  A test holding its own copy of the
queries tests the copy: the elisp could be renamed, mistyped or rewritten and
the test would go on passing.  So every fragment here is EXTRACTED from
`diorisis.el' by name -- the two defconsts whole, and the literal pieces
of each query function -- and assembled the way the elisp assembles it.  What
is duplicated is the ASSEMBLY, which is four lines of `concat'; what is
tested is the SQL, which is where the mistakes are.

What this catches: a column that does not exist, a join written wrong, a GLOB
that does not mean what it looks like, a clause that binds the wrong number
of values.  What it cannot catch: whether the elisp calls these functions
correctly.  That wants Emacs.

    python3 tools/check-diorisis-sql.py
"""

import os
import re
import sqlite3
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ELISP = os.path.join(ROOT, "diorisis.el")

FAILURES = []


def report(name, detail=""):
    print("   %-52s %s" % (name, detail))


def fail(name, detail):
    FAILURES.append((name, detail))
    print("   %-52s FAILED: %s" % (name, detail))


# ----------------------------------------------------------------------
# READING THE ELISP
# ----------------------------------------------------------------------

def elisp():
    with open(ELISP, encoding="utf-8") as handle:
        return handle.read()


def unescape(text):
    r"""An elisp string literal's body as its value.

    Only the escapes the queries use: `\"', `\\', and a backslash before a
    newline, which is how a long SQL string is broken across lines without a
    newline going into it."""
    out = []
    i = 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == "\n":
                i += 2
                continue
            out.append({"n": "\n", "t": "\t", '"': '"',
                        "\\": "\\"}.get(nxt, nxt))
            i += 2
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def strings_in(text):
    """Every string literal in TEXT, in order, unescaped."""
    found = []
    i = 0
    while i < len(text):
        if text[i] == ";":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        if text[i] == "?" and i + 1 < len(text) and text[i + 1] == "\\":
            i += 3
            continue
        if text[i] == '"':
            j, body = i + 1, []
            while j < len(text):
                if text[j] == "\\":
                    body.append(text[j:j + 2])
                    j += 2
                    continue
                if text[j] == '"':
                    break
                body.append(text[j])
                j += 1
            found.append(unescape("".join(body)))
            i = j + 1
            continue
        i += 1
    return found


def form(kind, name):
    """The text of the top-level (KIND NAME ...) form, parens balanced."""
    text = elisp()
    # A NEWLINE COUNTS AS THE SPACE.  A defconst whose value is a long string
    # puts the name on its own line, and looking for `(defconst NAME ' found
    # nothing while the form sat there.
    found = re.search(r"\(%s\s+%s\s" % (re.escape(kind), re.escape(name)),
                      text)
    if not found:
        raise SystemExit("no (%s %s ...) in diorisis.el" % (kind, name))
    start = found.start()
    depth, i, in_string = 0, start, False
    while i < len(text):
        c = text[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == ";":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    raise SystemExit("(%s %s ...) is not closed" % (kind, name))


def defconst(name):
    """A defconst whose value is one string literal."""
    return strings_in(form("defconst", name))[0]


def literals(function):
    """The string literals in a defun, less its docstring."""
    found = strings_in(form("defun", function))
    return found[1:] if found else []


# ----------------------------------------------------------------------
# THE FRAGMENTS, AS THE ELISP HOLDS THEM
# ----------------------------------------------------------------------

# ASSEMBLED AS `diorisis--select-clause' assembles it, with the branch
# that does NOT name `tlg_work_id': the column is added after the fact by
# `diorisis-tlg-numbers.py', and the query has to work either way.
SELECT = (defconst("diorisis--select-columns")
          + ",\n       NULL"
          + defconst("diorisis--select-joins"))
DATED = defconst("diorisis--dated")

# `diorisis--where' pushes a clause at a time.  Each is a literal in the
# function, either whole or as a `format' template with the operator in it.
WHERE_PIECES = literals("diorisis--where")
# `diorisis--order' holds the two orderings.
ORDER_PIECES = literals("diorisis--order")
# `diorisis-count' HAS TWO OPENING LINES and only one belongs in a query.
# A plain search counts rows; a query of several elements counts DISTINCT hits,
# the joins otherwise multiplying a sentence that satisfies them several ways.
# Joining every literal in the function put both SELECTs in one string.
COUNT_PIECES = [piece for piece in literals("diorisis-count")
                if "COUNT(DISTINCT" not in piece]
DISTRIBUTION_PIECES = literals("diorisis-distribution")
VOCABULARY_PIECES = [piece for piece in literals("diorisis--build-vocabulary")
                     if "SELECT" in piece]
COLUMN_PIECES = [piece for piece in literals("diorisis--column")
                 if "SELECT" in piece]
TEXT_PIECES = [piece for piece in literals("diorisis-read-text")
               if "SELECT" in piece]
# `diorisis--token' reads the tokens of one sentence, to find what the
# corpus records for the word under point.  Its columns are UNQUALIFIED, so
# the alias check below cannot see them and this is the only thing that will.
TOKEN_PIECES = [piece for piece in literals("diorisis--token")
                if "SELECT" in piece]
# `diorisis-lemmata-of-form' turns a form into the lemma the corpus
# assigns it, which is how a form typed at the lemma prompt is settled.
FORM_PIECES = [piece for piece in literals("diorisis-lemmata-of-form")
               if "SELECT" in piece]


# `diorisis--elements' writes one JOIN per element after the first, and
# `diorisis--element-conditions' the conditions.  Both are format
# templates, so they come out of the elisp whole.
ELEMENT_PIECES = literals("diorisis--elements")
CONDITION_PIECES = literals("diorisis--element-conditions")
# `diorisis--scopes' is a defconst whose value is an alist of templates,
# so every string in it is wanted except the docstring -- which is the last,
# not the first, and `literals' drops the first.
SCOPE_PIECES = [piece for piece in strings_in(form("defconst",
                                                   "diorisis--scopes"))
                if "%s" in piece]
DISTANCE_PIECES = literals("diorisis--distance")


def element_join(alias, table, distance):
    """The JOIN the elisp writes for one element."""
    template = [p for p in ELEMENT_PIECES if "JOIN %s %s ON" in p]
    if not template:
        raise SystemExit("no JOIN template in diorisis--elements")
    return template[0] % (table, alias, alias, alias, alias, distance)


def condition_template(shape):
    """The condition template of SHAPE, from the elisp.

    The templates name no column of their own -- the column is an argument,
    `COALESCE(%s.%s, \'\') = ?\' -- so they are found by their SHAPE and filled
    here the way the elisp fills them."""
    for piece in CONDITION_PIECES:
        if shape in piece:
            return piece
    raise SystemExit("no condition template like %r" % shape)


def equals(alias, column):
    """ALIAS.COLUMN equal to a bound value, as the elisp writes it."""
    return condition_template("'') = ?") % (alias, column)


def mark_is(alias):
    """ALIAS being a particular punctuation mark."""
    return condition_template(".mark = ?") % alias


def clause(fragment):
    """The WHERE fragment the elisp pushes for one dimension.

    Matched by its column so that renaming a clause here is not needed when
    the elisp reorders them."""
    for piece in WHERE_PIECES:
        if piece.startswith(fragment):
            return piece
    raise SystemExit("no clause beginning %r in diorisis--where"
                     % fragment)


def where(clauses):
    """CLAUSES joined as `diorisis--where' joins them."""
    return "\n  AND ".join(clauses) if clauses else "1"


def hits_query(clauses, order):
    """Assembled as `diorisis-hits' assembles it."""
    return (SELECT + "\nWHERE " + where(clauses)
            + "\nORDER BY " + order + "\nLIMIT ?")


def count_query(clauses):
    """Assembled as `diorisis-count' assembles it."""
    return "".join(COUNT_PIECES) + where(clauses)


def distribution_query(clauses):
    """Assembled as `diorisis-distribution' assembles it."""
    joined = "".join(DISTRIBUTION_PIECES)
    at = joined.index("WHERE ") + len("WHERE ")
    return joined[:at] + where(clauses) + joined[at:]


# ----------------------------------------------------------------------
# THE FIXTURE
# ----------------------------------------------------------------------

def fixture():
    path = os.path.join(tempfile.mkdtemp(), "diorisis-fixture.db")
    subprocess.run([sys.executable,
                    os.path.join(HERE, "make-diorisis-fixture.py"), path],
                   check=True, stdout=subprocess.DEVNULL)
    return sqlite3.connect(path)


def main():
    db = fixture()
    run = lambda query, values=(): db.execute(query, values).fetchall()

    print("   the fragments, read out of diorisis.el")
    report("select clause", "%d chars" % len(SELECT))
    report("date guard", DATED[:44] + " ...")
    report("where clauses", "%d" % len(WHERE_PIECES))

    print()
    print("   every column the elisp names exists")
    # WHAT THIS CATCHES.  `o.words' for `s.words' -- the sentence is on the
    # sentences table and the word count on texts -- would be a query that
    # runs and answers wrongly in the one case and not at all in the other.
    known = {}
    for table in ("texts", "sentences", "occurrences"):
        known[table] = set(row[1] for row in
                           run("PRAGMA table_info(%s)" % table))
    aliases = {"o": "occurrences", "t": "texts", "s": "sentences"}
    named = set()
    for piece in ([SELECT, DATED] + WHERE_PIECES + ORDER_PIECES
                  + COUNT_PIECES + DISTRIBUTION_PIECES + VOCABULARY_PIECES
                  + COLUMN_PIECES + TEXT_PIECES):
        named |= set(re.findall(r"\b([ots])\.([a-z_]+)\b", piece))
    for alias, column in sorted(named):
        if column not in known[aliases[alias]]:
            fail("%s.%s" % (alias, column),
                 "no such column in %s" % aliases[alias])
    report("%d qualified columns" % len(named), "all present")

    print()
    print("   the queries run, and answer")

    lemma = clause("o.lemma") % "="
    # THE MORPH CLAUSE COMES FROM ITS OWN FUNCTION NOW.  It used to be pushed
    # in `diorisis--where' as one `LIKE' for the whole phrase; it is built
    # by `diorisis--morph-clauses', one `LIKE' per feature, so that the
    # order a reader types the features in does not matter.  Read from there,
    # so that this still tests the elisp's own SQL and not a copy of it.
    # THE MORPH CLAUSE COMES FROM ITS OWN FUNCTION NOW.  It used to be pushed
    # in `diorisis--where' as one `LIKE' for the whole phrase; it is built
    # by `diorisis--morph-clauses', one `LIKE' per feature, so that the
    # order a reader types them in does not matter.  Read from there, so that
    # this tests the elisp's own SQL and not a copy of it.
    morph = [piece for piece in literals("diorisis--morph-clauses")
             if piece.startswith("COALESCE(%s.morph")]
    if not morph:
        raise SystemExit("no morph clause in diorisis--morph-clauses")
    morph = morph[0] % "o"
    pos = clause("o.pos")
    form_clause = clause("o.form") % "="
    genre = clause("t.genre")
    confidence = clause("(o.confidence IS NULL OR")
    unambiguous = clause("o.confidence IS NULL")
    from_year = clause("CAST(t.date AS INTEGER) >=")
    to_year = clause("CAST(t.date AS INTEGER) <=")
    corpus_order, date_order = ORDER_PIECES[0], ORDER_PIECES[1]
    # `diorisis--order' writes the date ordering as three literals round
    # the date guard, so it is assembled the way the elisp does.
    if len(ORDER_PIECES) > 2:
        # The corpus ordering is the last literal -- the `else' of the `if' --
        # and the date ordering is everything before it, with the date guard
        # in the hole after `CASE WHEN '.
        corpus_order = ORDER_PIECES[-1]
        date_order = ORDER_PIECES[0] + DATED + "".join(ORDER_PIECES[1:-1])

    rows = run(hits_query([lemma], corpus_order), ("mu/w", 20))
    if len(rows) != 7:
        fail("lemma mu/w", "7 expected, %d back" % len(rows))
    else:
        report("lemma mu/w", "%d hits, in corpus order" % len(rows))

    # THE LEFT JOIN.  Sentence 21 of the Aelian is in no row of `sentences'
    # and the hit must still be listed, with nothing to show for it.
    # COLUMN 13 AND NOT THE LAST.  The last is the TLG work number, which is
    # NULL for every row in the branch under test, so `row[-1]' called every
    # hit sentenceless and the check passed for the wrong reason.
    missing = [row for row in rows if row[13] is None]
    if len(missing) != 1:
        fail("the hit whose sentence is missing",
             "1 expected, %d back" % len(missing))
    else:
        report("the hit whose sentence is missing", "listed, words NULL")

    rows = run(hits_query([lemma, morph], corpus_order),
               ("mu/w", "%perf part%", 20))
    if len(rows) != 5:
        fail("+ morph like perf part", "5 expected, %d back" % len(rows))
    else:
        report("+ morph like perf part", "%d hits" % len(rows))
    # MATCHING THE MIDDLE.  Two of the four hold `perf part' as one analysis
    # among several, which is the whole reason for LIKE rather than `='.
    if not any(" | " in (row[8] or "") for row in rows):
        fail("morph matches one analysis of several",
             "no hit with several analyses came back")
    else:
        report("morph matches one analysis of several", "yes")

    rows = run(count_query([lemma]), ("mu/w",))
    if rows[0][0] != 7:
        fail("count", "7 expected, %d back" % rows[0][0])
    else:
        report("count", "%d, without joining the sentences" % rows[0][0])

    # THE DATE GUARD.  The Anonymus carries `1.51' -- the JSON release's
    # version, not a year -- and must not be read as the first century; the
    # other Anonymus has no date at all.
    rows = run(hits_query([lemma, DATED, from_year, to_year], date_order),
               ("mu/w", 100, 300, 20))
    authors = sorted(set(row[0] for row in rows))
    if authors != ["Achilles Tatius", "Aelian", "Aristides"]:
        fail("A.D. 100 to 300", "got %s" % authors)
    else:
        report("A.D. 100 to 300", ", ".join(authors))
    if rows and rows[0][0] != "Achilles Tatius":
        fail("oldest first", "%s came first" % rows[0][0])
    else:
        report("oldest first", "A.D. 150 before A.D. 230")

    # `texts t' because the guard is written with the alias the
    # queries use.
    dates = run("SELECT date FROM texts t WHERE " + DATED)
    if ("1.51",) in dates or (None,) in dates:
        fail("the version string is not a date", "%s" % dates)
    else:
        report("the version string is not a date",
               "%d of 7 texts are dated" % len(dates))

    # CONFIDENCE, AND NULL AS THE CERTAIN CASE.
    rows = run(count_query([lemma, confidence]), ("mu/w", 0.8))
    if rows[0][0] != 4:
        fail("confidence at least 0.8", "4 expected, %d back" % rows[0][0])
    else:
        report("confidence at least 0.8",
               "%d, the unambiguous among them" % rows[0][0])
    rows = run(count_query([lemma, unambiguous]), ("mu/w",))
    if rows[0][0] != 2:
        fail("unambiguous only", "2 expected, %d back" % rows[0][0])
    else:
        report("unambiguous only", "%d" % rows[0][0])

    # A WILDCARD ON THE LEMMA.
    like = clause("o.lemma") % "LIKE"
    rows = run(count_query([like]), ("a)%",))
    if rows[0][0] != 5:
        fail("lemma like a)%", "5 expected, %d back" % rows[0][0])
    else:
        report("lemma like a)%", "%d" % rows[0][0])

    rows = run(count_query([form_clause]), ("memuko/tos",))
    if rows[0][0] != 1:
        fail("form memuko/tos", "1 expected, %d back" % rows[0][0])
    else:
        report("form memuko/tos", "%d" % rows[0][0])

    # Four in the Aelian: the perfect of `e)mfu/w' and three of `mu/w'.  Its
    # nouns are nouns and are not counted, which is the point of the clause.
    rows = run(count_query([pos, genre]), ("verb", "Technical"))
    if rows[0][0] != 4:
        fail("verbs in Technical prose", "4 expected, %d back" % rows[0][0])
    else:
        report("verbs in Technical prose", "%d" % rows[0][0])

    # THE OTHER BRANCH OF `diorisis--select-clause': the column named
    # rather than NULL, which is what a reader has once
    # `diorisis-tlg-numbers.py' has run.  The Hecuba is 040 in Diorisis and
    # 007 in the TLG, and 007 is what the browser must be asked for.
    with_tlg = (defconst("diorisis--select-columns")
                + ",\n       t.tlg_work_id"
                + defconst("diorisis--select-joins")
                + "\nWHERE " + where([lemma, clause("o.author_id")])
                + "\nORDER BY " + corpus_order + "\nLIMIT ?")
    try:
        got = run(with_tlg, ("mu/w", "0006", 5))
        if got and got[0][16] == "007" and got[0][3] == "040":
            report("the TLG number, where it differs from ours",
                   "ours 040, the TLG's %s" % got[0][16])
        else:
            fail("the TLG number, where it differs from ours", "%s" % (got,))
    except sqlite3.Error as error:
        fail("the TLG number, where it differs from ours", "%s" % error)

    # THE TOKENS OF ONE SENTENCE.  The Aelian's sentence 19 holds four
    # lemmatised words, `memuko/tos' among them, and the lookup finds a word
    # by matching against these.
    for piece in TOKEN_PIECES:
        try:
            got = run(piece, ("0545", "001", 19))
            forms = sorted(row[0] for row in got)
            if "memuko/tos" in forms and len(forms) == 4:
                report("the tokens of one sentence",
                       "%d, including memuko/tos" % len(forms))
            else:
                fail("the tokens of one sentence", "%s" % (forms,))
        except sqlite3.Error as error:
            fail("the tokens of one sentence",
                 "%s -- %s" % (error, piece.replace("\n", " ")))

    # A FORM SETTLED INTO ITS LEMMA.  `memuko/tos' is a form of `mu/w' and of
    # nothing else in the fixture, so the corpus answers with one lemma.
    for piece in FORM_PIECES:
        try:
            got = run(piece, ("memuko/tos",))
            if got == [("mu/w", 1)]:
                report("a form settled into its lemma",
                       "memuko/tos -> %s" % got[0][0])
            else:
                fail("a form settled into its lemma", "%s" % (got,))
        except sqlite3.Error as error:
            fail("a form settled into its lemma", "%s" % error)

    # A QUERY OF TWO ELEMENTS.  `le/wn' followed within 2 words by a form of
    # `mu/w': the Aelian's `o( de\ le/wn, memuko/ta ...', where the two are
    # one word apart and -- the comma between them -- two nodes apart.  The
    # same query counting nodes with a scope of 1 must find nothing, which is
    # what `(ignore punctuation)' means.
    scope_within = [p for p in SCOPE_PIECES if "BETWEEN 1 AND" in p]
    if not scope_within:
        fail("the scope templates", "no `within' template found")
    else:
        for by, limit, wanted in (("word_index", 2, 1),
                                  ("node_index", 1, 0),
                                  ("node_index", 2, 1)):
            distance = scope_within[0] % ("(e2.%s - o.%s)" % (by, by), limit)
            query = (SELECT + "\n"
                     + element_join("e2", "occurrences", distance)
                     + "\nWHERE " + where([equals("o", "lemma"),
                                           equals("e2", "lemma")])
                     + "\nORDER BY " + corpus_order + "\nLIMIT ?")
            try:
                got = run(query, ("le/wn", "mu/w", 20))
                name = "le/wn + mu/w within %d %s" % (limit, by[:4])
                if len(got) == wanted:
                    report(name, "%d hit%s" % (len(got),
                                               "" if len(got) == 1 else "s"))
                else:
                    fail(name, "%d expected, %d back" % (wanted, len(got)))
            except sqlite3.Error as error:
                fail("a query of two elements",
                     "%s -- %s" % (error, query.replace("\n", " ")))

    # AND THE PUNCTUATION AS AN ELEMENT: a comma within 2 nodes after `le/wn'.
    distance = scope_within[0] % ("(e2.node_index - o.node_index)", 2)
    query = ("SELECT o.form, e2.mark FROM occurrences o\n"
             + "JOIN texts t ON o.author_id=t.author_id"
             + " AND o.work_id=t.work_id\n"
             + element_join("e2", "punctuation", distance)
             + "\nWHERE " + where([equals("o", "lemma"),
                                   mark_is("e2")]))
    try:
        got = run(query, ("le/wn", ","))
        if got == [("le/wn", ",")]:
            report("punctuation as an element", "le/wn then a comma")
        else:
            fail("punctuation as an element", "%s" % (got,))
    except sqlite3.Error as error:
        fail("punctuation as an element", "%s" % error)

    # IGNORING DIACRITICS, which is what the bare columns are for.
    query = (SELECT + "\nWHERE "
             + where([equals("o", "lemma_bare")])
             + "\nORDER BY " + corpus_order + "\nLIMIT ?")
    try:
        got = run(query, ("muw", 20))
        if len(got) == 7:
            report("ignoring diacritics", "muw finds all %d" % len(got))
        else:
            fail("ignoring diacritics", "7 expected, %d back" % len(got))
    except sqlite3.Error as error:
        fail("ignoring diacritics", "%s" % error)

    rows = run(distribution_query([lemma]), ("mu/w",))
    if not rows or rows[0][1] != "De natura animalium" or rows[0][3] != 3:
        fail("by text", "%s" % (rows[:1],))
    else:
        report("by text", "Aelian 3, then the rest")
    if any(row[4] is None for row in rows):
        fail("by text, per ten thousand words",
             "a text came back with no word count to divide by")
    else:
        report("by text, per ten thousand words", "word counts present")

    for name, pieces in (("vocabulary", VOCABULARY_PIECES),
                         ("genres, for completion", COLUMN_PIECES),
                         ("authors and works", TEXT_PIECES)):
        for piece in pieces:
            query = piece
            values = ()
            if "%s" in query:
                query = query % (("genre",) * query.count("%s"))
            if "?" in query:
                values = ("0059",)
            try:
                got = run(query, values)
                report(name, "%d rows" % len(got))
            except sqlite3.Error as error:
                fail(name, "%s -- %s" % (error, query.replace("\n", " ")))

    # THE READER'S OWN LAYOUT, printed rather than tested: the width and the
    # `citation only where it changes' rule are the two things that decide
    # whether a marker can be told from the text, and looking at a page of it
    # is the only check for that worth having.
    print()
    print("   the text reader, as it would set the Aelian")
    width = 12
    last = None
    for sentence, location, words in run(
            "SELECT sentence, location, words FROM sentences"
            " WHERE author_id='0545' AND work_id='001' ORDER BY sentence"):
        citation = (location or "").strip("'\"")
        marker = citation if citation != last else ""
        last = citation
        print("   |%-*s|%s" % (width, marker, words[:44]))

    # THE POSTAG TABLE, against the examples `treebank-react' documents.  Nine
    # places of single letters is the sort of table one letter goes wrong in,
    # and a wrong postag is a tree annotated on a false analysis.
    print()
    print("   the ALDT postag, against the format's own examples")
    # THE POSTAG TABLES ARE THE TREEBANK'S.  A postag is how ALDT encodes
    # morphology in a tree file, so the split sent these across; everything
    # else this checker reads is the corpus's query builders.
    tb = open(os.path.join(ROOT, "treebank.el"), encoding="utf-8").read()
    block = tb[tb.index("(defconst treebank--postag-places"):]
    block = block[:block.index('"The nine places')]
    letters = dict(re.findall(r'\("([a-z_0-9]+)" \. "([a-z0-9])"\)', block))
    places = [["noun", "verb", "adjective", "adverb", "article", "particle",
               "conjunction", "preposition", "pronoun", "numeral",
               "interjection", "punctuation", "proper"],
              ["1st", "2nd", "3rd"], ["sg", "pl", "dual"],
              ["pres", "imperf", "perf", "plup", "futperf", "fut", "aor"],
              ["ind", "subj", "opt", "inf", "imperat", "part"],
              ["act", "mid", "pass", "mp"], ["masc", "fem", "neut"],
              ["nom", "gen", "dat", "acc", "voc"], ["comp", "superl"]]

    def postag(values):
        return "".join(next((letters[name] for name in place
                             if name in values), "-") for place in places)

    for values, wanted, word in (
            (["verb", "2nd", "sg", "pres", "imperat", "act"],
             "v2spma---", "xai=re"),
            (["interjection"], "i--------", "w)"),
            (["noun", "sg", "masc", "voc"], "n-s---mv-", "ko/sme"),
            (["verb", "perf", "part", "act", "masc", "gen", "sg"],
             "v-srpamg-", "memuko/tos")):
        got = postag(values)
        if got == wanted:
            report("postag for %s" % word, got)
        else:
            fail("postag for %s" % word, "%s, wanted %s" % (got, wanted))

    print()
    if FAILURES:
        print("   %d FAILED" % len(FAILURES))
        return 1
    print("   the SQL is sound")
    return 0


if __name__ == "__main__":
    sys.exit(main())
