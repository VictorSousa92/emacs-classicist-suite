#!/usr/bin/env python3
"""diorisis-tlg-numbers.py -- what the TLG calls each text, and what we called it.

THE ASSUMPTION THAT TURNED OUT TO BE FALSE.  This project has proceeded on
the belief that the Diorisis filenames carry the TLG's own numbers, so that a
hit could be opened in Diogenes with nothing translated:
`Plato (0059) - Charmides (018)' is author 0059 work 018 in the TLG, and it
is.  Euripides is not.  Diorisis numbers the Hecuba 040; Perseus and the TLG
number it 0006.007; and the thirteen plays it has run 040 to 052 against the
TLG's 007 to 019.  So `RET' on a Euripides hit has been asking Diogenes for a
work that is either something else or nothing at all -- quietly, which is the
kind of wrong this project keeps writing comments about.

WHY THE DUCKDB FIXES IT.  Bilby's compilation conformed the document ids to
the convention GlauX uses, which is the TLG's.  So that file is, among other
things, a CONCORDANCE between Diorisis' numbering and the TLG's -- worth more
to us than the morphology it was fetched for.

HOW THE PAIRING IS MADE, AND WHY NOT BY NUMBER.  By author and title, the
numbers being the thing in dispute; the titles are the same strings in both,
both deriving from the same corpus.  Each pairing is then CHECKED against the
word and sentence counts, which are independent of the numbering: two texts
of one author that agree in title and in length are the same text.  A pairing
that fails either test is reported and not written.

    python3 tools/diorisis-tlg-numbers.py DIORISIS.DUCKDB DIORISIS.DB
    python3 tools/diorisis-tlg-numbers.py DIORISIS.DUCKDB DIORISIS.DB --write

Without `--write' nothing is written.  With it, `texts' gains a column
`tlg_work_id' holding the TLG's number where it differs from ours and ours
where it does not.  OUR OWN NUMBERS ARE NOT TOUCHED: they are the primary key
of `texts' and the join to ten million occurrences, and the elisp can prefer
the new column when it opens a passage without anything else being disturbed.
"""

import argparse
import os
import re
import sqlite3
import sys
import unicodedata


def normalise(title):
    """A title as something to compare: letters and digits, lower case."""
    if not title:
        return ""
    plain = unicodedata.normalize("NFKD", title)
    return re.sub(r"[^a-z0-9]", "", plain.lower())


def close_enough(mine, theirs, slack=0.10):
    """Whether two counts are near enough to be the same text.

    NOT EQUAL, and cannot be.  Our word count is the tokens the tagger gave a
    lemma to; theirs is every word including the ones it did not.  Across the
    corpus ours is about 1.4% short, and for a text with much corrupt or
    foreign matter it is more.  So this asks for the same order of magnitude
    and the same shape, not for agreement."""
    if not mine or not theirs:
        return False
    return abs(mine - theirs) <= slack * max(mine, theirs)


def self_test():
    failures = []

    def expect(name, got, want):
        if got != want:
            failures.append(name)
            print("   %-46s FAILED %r" % (name, got))
        else:
            print("   %-46s ok" % name)

    expect("a title normalises", normalise("Iphigenia in Tauris"),
           "iphigeniaintauris")
    expect("case and punctuation go", normalise("De natura animalium."),
           "denaturaanimalium")
    expect("counts within a tenth agree", close_enough(7162, 7300), True)
    expect("counts a third apart do not", close_enough(7162, 11000), False)
    expect("a missing count never agrees", close_enough(0, 7162), False)
    print()
    if failures:
        print("   %d FAILED" % len(failures))
        return 1
    print("   sound")
    return 0


def report(duck, ours, write):
    theirs = {}
    for comb, author, title, sentences, words in duck.execute(
            "SELECT comb_tlg_id, author, title, sent_count, word_count"
            " FROM document").fetchall():
        parts = (comb or "").split("-")
        if len(parts) != 2:
            continue
        theirs.setdefault(parts[0].zfill(4), []).append(
            (parts[1], title, sentences, words, comb))

    mine = {}
    for author_id, work_id, author, work, words in ours.execute(
            "SELECT author_id, work_id, author, work, words FROM texts"):
        sentences = ours.execute(
            "SELECT COUNT(*) FROM sentences WHERE author_id = ?"
            " AND work_id = ?", (author_id, work_id)).fetchone()[0]
        mine.setdefault(author_id, []).append(
            (work_id, work, sentences, words, author))

    agreed = differed = unpaired = 0
    corrections = []
    examples = []
    orphans = []

    for author_id, texts in sorted(mine.items()):
        candidates = theirs.get(author_id, [])
        taken = set()
        for work_id, title, sentences, words, author in texts:
            wanted = normalise(title)
            found = None
            for index, (their_work, their_title, their_sentences,
                        their_words, comb) in enumerate(candidates):
                if index in taken:
                    continue
                if normalise(their_title) != wanted:
                    continue
                # THE COUNTS ARE THE CHECK.  An author with two texts of the
                # same title -- a work and its spurious twin -- would
                # otherwise be paired by whichever came first.
                if not (close_enough(words, their_words)
                        or close_enough(sentences, their_sentences)):
                    continue
                found = (index, their_work, comb)
                break
            if not found:
                unpaired += 1
                if len(orphans) < 30:
                    orphans.append("%s-%s  %s, %s" % (author_id, work_id,
                                                      author or "?",
                                                      title or "?"))
                continue
            index, their_work, comb = found
            taken.add(index)
            corrections.append((author_id, work_id, their_work))
            if their_work.zfill(3) == work_id:
                agreed += 1
            else:
                differed += 1
                if len(examples) < 30:
                    examples.append("%s  %s, %s: ours %s, the TLG's %s"
                                    % (author_id, author or "?",
                                       title or "?", work_id, their_work))

    print()
    print("   %d texts are numbered as the TLG numbers them" % agreed)
    print("   %d are NOT" % differed)
    print("   %d could not be paired with a text of theirs" % unpaired)
    if examples:
        print()
        print("   where the numbering differs:")
        for line in examples:
            print("      %s" % line)
        if differed > len(examples):
            print("      ... and %d more" % (differed - len(examples)))
    if orphans:
        print()
        print("   ours that found no text of theirs:")
        for line in orphans:
            print("      %s" % line)
        if unpaired > len(orphans):
            print("      ... and %d more" % (unpaired - len(orphans)))

    if not write:
        print()
        print("   DRY RUN: nothing written.  Pass --write to record these")
        print("   in texts.tlg_work_id.  Our own work_id is never altered.")
        return

    have = set(row[1] for row in
               ours.execute("PRAGMA table_info(texts)").fetchall())
    if "tlg_work_id" not in have:
        ours.execute("ALTER TABLE texts ADD COLUMN tlg_work_id TEXT")
    ours.executemany(
        "UPDATE texts SET tlg_work_id = ? WHERE author_id = ?"
        " AND work_id = ?",
        [(their_work, author_id, work_id)
         for author_id, work_id, their_work in corrections])
    ours.commit()
    print()
    print("   %d texts now carry a TLG work number" % len(corrections))


def main():
    parser = argparse.ArgumentParser(
        description="Compare our Diorisis numbering with the TLG's.")
    parser.add_argument("duckdb", nargs="?")
    parser.add_argument("sqlite", nargs="?")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        sys.exit(self_test())
    if not (args.duckdb and args.sqlite):
        sys.exit("Give the DuckDB and our diorisis.db, or --self-test.")
    for path in (args.duckdb, args.sqlite):
        if not os.path.exists(path):
            sys.exit("%s is not here." % path)
    try:
        import duckdb
    except ImportError:
        sys.exit("No duckdb module: pip install duckdb")
    duck = duckdb.connect(args.duckdb, read_only=True)
    connection = sqlite3.connect(args.sqlite)
    report(duck, connection, args.write)
    connection.close()
    duck.close()
    print()


if __name__ == "__main__":
    main()
