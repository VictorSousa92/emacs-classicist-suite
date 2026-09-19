#!/usr/bin/env python3
"""probe-diorisis-duckdb.py -- what is in Bilby's DuckDB Diorisis, and can it
be joined to ours.

WHY A PROBE AND NOT A CONVERTER.  The DuckDB compilation holds things ours
does not -- the morphology in COLUMNS rather than as a string, the dialect,
the metrical structure -- and lacks the one thing this whole package rests
on: a CITATION for each sentence.  Its `location' is the place of
composition, not a passage.  So the question is not whether to switch to it
but whether its columns can be carried across onto ours, and that turns on
three things nobody can know without opening the file:

  1. Does `sent_id' mean what our `sentence' means?  Both releases were made
     from the same TEI-XML, so the sentence ids ought to be the same numbers
     -- and if they are, our citations can carry the DuckDB's morphology.
  2. Are `self_form' and `self_lemma' beta code or Unicode?  The deposit says
     the forms were converted with beta-code-py.  If the LEMMA was converted
     too, the link to Diogenes' parser and to the LSJ has to be converted
     back, that word list being keyed on beta code.
  3. What shape is `comb_tlg_id'?  It is the TLG number conformed to GlauX's
     convention, and Diogenes wants `0059' and `018' separately.

It prints what it finds and says nothing about what to do.  Reading its
output is the next decision.

    pip install duckdb
    python3 tools/probe-diorisis-duckdb.py /path/to/Diorisis.duckdb \\
            --sqlite "/mnt/archive/Diogenes Data/Diorisis/diorisis.db"

If DuckDB refuses the file, it was built in May 2024 and so with 0.10.x:
`pip install "duckdb==0.10.3"'.  Later versions read 0.10 files, but not
every version has.
"""

import argparse
import os
import re
import sqlite3
import sys

MORPH_COLUMNS = ["self_pos", "self_person", "self_number", "self_tense",
                 "self_mood", "self_voice", "self_gender", "self_case",
                 "self_degree", "idiom", "prosody"]

GREEK = re.compile(r"[\u0370-\u03ff\u1f00-\u1fff]")
BETA = re.compile(r"[()/\\=|*+]")


def heading(said):
    print()
    print("== %s" % said)


def rows(db, query, values=None):
    return db.execute(query, values or []).fetchall()


def script_of(samples):
    """Whether SAMPLES look like Greek, like beta code, or like neither."""
    greek = sum(1 for one in samples if one and GREEK.search(one))
    beta = sum(1 for one in samples if one and BETA.search(one))
    if greek and not beta:
        return "Unicode Greek"
    if beta and not greek:
        return "beta code"
    if greek and beta:
        return "both -- %d Greek, %d with beta markers" % (greek, beta)
    return "neither, or empty"


def probe(duck, sqlite_file):
    heading("the tables")
    for (name,) in rows(duck, "SHOW TABLES"):
        count = rows(duck, "SELECT COUNT(*) FROM %s" % name)[0][0]
        print("   %-12s %12d rows" % (name, count))

    heading("the columns, as the file has them")
    for table in ("document", "word"):
        print("   %s" % table)
        for row in rows(duck, "DESCRIBE %s" % table):
            print("      %-18s %s" % (row[0], row[1]))

    heading("comb_tlg_id, and whether the TLG numbers can be got out of it")
    samples = [row[0] for row in
               rows(duck, "SELECT comb_tlg_id FROM document LIMIT 12")]
    for one in samples:
        print("   %s" % one)
    # WHAT DIOGENES NEEDS is `0059' and `018' -- four digits and three.  The
    # shapes are counted rather than assumed: GlauX writes `tlg0059.tlg018'
    # in some places and `0059.018' in others, and one deposit need not be
    # consistent with another.
    shapes = {}
    for (one,) in rows(duck, "SELECT comb_tlg_id FROM document"):
        shape = re.sub(r"\d", "N", one or "")
        shapes[shape] = shapes.get(shape, 0) + 1
    print("   shapes, with N for a digit:")
    for shape, count in sorted(shapes.items(), key=lambda p: -p[1])[:8]:
        print("      %-28s %5d" % (shape, count))

    heading("is there a citation anywhere in it")
    # THE QUESTION THE WHOLE THING TURNS ON.  A hit is worth having because it
    # is a passage one can open; `1.19.5' is what makes that possible.  The
    # deposit documents `location' as the place of COMPOSITION, so this looks
    # at what the column actually holds before believing either reading.
    for (one,) in rows(duck, "SELECT DISTINCT location FROM document\
 WHERE location IS NOT NULL LIMIT 12"):
        print("   document.location: %s" % one)
    looks_like_citation = 0
    for (one,) in rows(duck, "SELECT location FROM document\
 WHERE location IS NOT NULL"):
        if re.match(r"^'?\d+([.]\d+)*[a-z]?'?$", one.strip()):
            looks_like_citation += 1
    print("   %d of them look like a citation rather than a place"
          % looks_like_citation)
    columns = [row[0] for row in rows(duck, "DESCRIBE word")]
    print("   the word table's own columns: %s" % ", ".join(columns))
    print("   nothing citation-shaped among them"
          if not any(name in columns for name in
                     ("location", "citation", "ref", "passage"))
          else "   SOMETHING CITATION-SHAPED IS THERE -- look at it")

    heading("beta code or Unicode")
    for column in ("self_form", "self_lemma", "self_lemma_id"):
        samples = [row[0] for row in
                   rows(duck, "SELECT %s FROM word\
 WHERE %s IS NOT NULL LIMIT 400" % (column, column))]
        print("   %-16s %s" % (column, script_of(samples)))
        print("      e.g. %s" % ", ".join(str(one) for one in samples[:6]))

    heading("the tagset, which is the reason for wanting this file")
    for column in MORPH_COLUMNS:
        if column not in columns:
            print("   %-14s absent" % column)
            continue
        found = rows(duck, "SELECT %s, COUNT(*) FROM word\
 WHERE %s IS NOT NULL AND %s <> '' GROUP BY %s ORDER BY 2 DESC LIMIT 14"
                     % (column, column, column, column))
        print("   %-14s %s" % (column,
                               ", ".join("%s (%d)" % (value, count)
                                         for value, count in found)
                               or "always empty"))

    heading("one sentence, put back together")
    text = rows(duck, "SELECT comb_tlg_id FROM document\
 ORDER BY word_count DESC LIMIT 1")[0][0]
    sentence = rows(duck, "SELECT sent_id FROM word WHERE comb_tlg_id = ?\
 ORDER BY seq_id LIMIT 1", [text])[0][0]
    words = rows(duck, "SELECT self_word_id, self_form, self_lemma, self_pos\
 FROM word WHERE comb_tlg_id = ? AND sent_id = ? ORDER BY seq_id",
                 [text, sentence])
    print("   %s, sentence %s, %d words" % (text, sentence, len(words)))
    print("   %s" % " ".join(str(word[1]) for word in words))

    if not sqlite_file:
        heading("the cross-check was not run")
        print("   Pass --sqlite DIORISIS.DB to find out whether the sentence")
        print("   ids are the same numbers as ours.  That is the answer that")
        print("   decides whether our citations can carry these columns.")
        return

    heading("do the sentence ids mean the same thing")
    ours = sqlite3.connect(sqlite_file)
    # OURS IS KEYED (author_id, work_id) and theirs by one string, so the
    # string is reduced to the two numbers by taking the digits in order.
    # Printed rather than trusted: a shape this does not fit is reported as a
    # text that could not be matched, which is the honest outcome.
    agreed = disagreed = unmatched = 0
    examples = []
    for text, sentences, words in rows(
            duck, "SELECT comb_tlg_id, sent_count, word_count FROM document"):
        numbers = re.findall(r"\d+", text or "")
        if len(numbers) < 2:
            unmatched += 1
            continue
        author, work = numbers[0].zfill(4), numbers[1].zfill(3)
        mine = ours.execute(
            "SELECT COUNT(*), MAX(sentence), MIN(sentence) FROM sentences"
            " WHERE author_id = ? AND work_id = ?", (author, work)).fetchone()
        if not mine or not mine[0]:
            unmatched += 1
            continue
        if mine[0] == sentences:
            agreed += 1
        else:
            disagreed += 1
            if len(examples) < 8:
                examples.append((text, sentences, mine[0], mine[1]))
    print("   %d texts agree on the number of sentences" % agreed)
    print("   %d disagree" % disagreed)
    print("   %d could not be matched to a text of ours at all" % unmatched)
    for text, theirs, mine, highest in examples:
        print("      %-24s theirs %6s, ours %6s, our highest id %s"
              % (text, theirs, mine, highest))

    heading("and do the words line up inside a sentence")
    # THE HARDER QUESTION.  Equal sentence counts would let a citation be
    # carried text by text; carrying the morphology needs the TOKENS to line
    # up, one of theirs to one of ours.  Ours are stored without a position
    # in the sentence, so what can be compared here is how many there are.
    for text, in rows(duck, "SELECT comb_tlg_id FROM document\
 ORDER BY word_count DESC LIMIT 5"):
        numbers = re.findall(r"\d+", text or "")
        if len(numbers) < 2:
            continue
        author, work = numbers[0].zfill(4), numbers[1].zfill(3)
        for (sentence,) in rows(duck, "SELECT DISTINCT sent_id FROM word\
 WHERE comb_tlg_id = ? ORDER BY sent_id LIMIT 3", [text]):
            theirs = rows(duck, "SELECT COUNT(*) FROM word\
 WHERE comb_tlg_id = ? AND sent_id = ?", [text, sentence])[0][0]
            said = None
            try:
                said = int(str(sentence))
            except (TypeError, ValueError):
                pass
            mine = ours.execute(
                "SELECT COUNT(*) FROM occurrences WHERE author_id = ?"
                " AND work_id = ? AND sentence = ?",
                (author, work, said)).fetchone()[0]
            location = ours.execute(
                "SELECT location FROM sentences WHERE author_id = ?"
                " AND work_id = ? AND sentence = ?",
                (author, work, said)).fetchone()
            print("   %-22s sentence %-6s theirs %3d, ours %3d, our citation"
                  " %s" % (text, sentence, theirs, mine,
                           (location or ["none"])[0]))
    ours.close()


def main():
    parser = argparse.ArgumentParser(
        description="Say what is in the DuckDB Diorisis and whether it joins"
                    " to ours.")
    parser.add_argument("duckdb", help="Diorisis.duckdb")
    parser.add_argument("--sqlite", default=None,
                        help="our own diorisis.db, for the cross-check")
    args = parser.parse_args()

    if not os.path.exists(args.duckdb):
        sys.exit("%s is not here." % args.duckdb)
    if args.sqlite and not os.path.exists(args.sqlite):
        sys.exit("%s is not here." % args.sqlite)
    try:
        import duckdb
    except ImportError:
        sys.exit("No duckdb module: pip install duckdb")
    # READ-ONLY, because a file of this size downloaded once should not be
    # rewritten by something that only means to look at it.
    try:
        connection = duckdb.connect(args.duckdb, read_only=True)
    except Exception as error:
        sys.exit("DuckDB would not open it: %s\n"
                 "It was built with 0.10.x; try pip install 'duckdb==0.10.3'"
                 % error)
    print("   %s, %.0f MB" % (args.duckdb,
                              os.path.getsize(args.duckdb) / 1e6))
    probe(connection, args.sqlite)
    connection.close()
    print()


if __name__ == "__main__":
    main()
