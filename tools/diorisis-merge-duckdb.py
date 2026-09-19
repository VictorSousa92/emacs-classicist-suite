#!/usr/bin/env python3
"""diorisis-merge-duckdb.py -- the DuckDB's morphology, onto our citations.

WHAT IS BEING JOINED, AND WHY IN THIS DIRECTION.  Bilby's DuckDB compilation
of Diorisis holds the morphology in COLUMNS -- tense, mood, voice, case,
gender, number, person, degree -- and two things nothing else here has: the
DIALECT (`attic|epic|ionic') and the PROSODY (proclitic, enclitic).  What it
does not hold is a citation: its `location' is the place of composition, and
its word table has sentence and word ids and nothing that says `1.19.5'.

Our index has the citation and not the columns.  So ours is the spine and
theirs is what gets carried across, rather than the other way about.  A hit
must remain a passage one can open; that is the whole argument for doing any
of this in Emacs.

HOW THE TOKENS ARE PAIRED, AND WHY IT CAN BE TRUSTED.  Both releases were
made from the same TEI-XML, and the probe bears that out arithmetically:
their 11,516,038 word rows less their 1,309,617 punctuation rows is
10,206,421, which is the corpus's published count to the digit.  Ours is
10,058,758 -- short by the tokens the tagger left without a lemma, which our
indexer passes over.

So the pairing is positional, sentence by sentence: their tokens in document
order, less punctuation and less the unlemmatised, against ours in rowid
order, which is insertion order and so document order too.

POSITIONAL PAIRING IS ONLY AS GOOD AS ITS CHECK, so nothing is written on
trust.  For each sentence the counts must agree, and then each pair's forms
must agree as SKELETONS -- the Greek letters with the diacritics and the
breathings thrown away, theirs transliterated to beta.  A sentence that fails
is skipped and counted; a text that mostly fails is skipped whole and named.
Being short of the dialect for one text is nothing.  Attaching the wrong
analysis to the right citation would be worse than either database alone, and
would be invisible.

    python3 tools/diorisis-merge-duckdb.py DIORISIS.DUCKDB DIORISIS.DB
    python3 tools/diorisis-merge-duckdb.py DIORISIS.DUCKDB DIORISIS.DB --write

Without `--write' it changes nothing and reports what it would do.  With it,
ten new columns are added to `occurrences' and filled: budget some minutes
and a few hundred megabytes.  `--self-test' checks the pairing logic alone
and needs neither database.
"""

import argparse
import os
import shutil
import sqlite3
import sys
import unicodedata

# The columns carried across, as (ours, theirs).  Named as the schema here
# names things -- lower case, no `self_' -- because they are our columns once
# they are here.
COLUMNS = [("person", "self_person"),
           ("number", "self_number"),
           ("tense", "self_tense"),
           ("mood", "self_mood"),
           ("voice", "self_voice"),
           ("gender", "self_gender"),
           ("grammatical_case", "self_case"),
           ("degree", "self_degree"),
           ("idiom", "idiom"),
           ("prosody", "prosody")]

# THEIR EMPTY IS A STRING.  `_' and not NULL, in every one of these columns
# and in `self_lemma' -- so a query for `every participle' written against a
# NULL would find everything, and one written against `_' is what is meant.
# Stored as NULL on our side, the rest of our schema using NULL for absence.
EMPTY = "_"

GREEK_TO_BETA = {
    "α": "a", "β": "b", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "h",
    "θ": "q", "ι": "i", "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "c",
    "ο": "o", "π": "p", "ρ": "r", "σ": "s", "ς": "s", "τ": "t", "υ": "u",
    "φ": "f", "χ": "x", "ψ": "y", "ω": "w",
}


def skeleton_greek(form):
    """A Unicode Greek form as bare beta letters.

    THE DIACRITICS GO.  This is for CHECKING a pairing, not for storing
    anything: their forms were converted to Unicode with beta-code-py and ours
    are the corpus's own beta code, and the two disagree about where a
    breathing sits on a capital and about final sigma.  The letters agree, and
    the letters are enough to say whether two tokens are the same word."""
    if not form:
        return ""
    out = []
    for character in unicodedata.normalize("NFD", form).lower():
        letter = GREEK_TO_BETA.get(character)
        if letter:
            out.append(letter)
    return "".join(out)


def skeleton_beta(form):
    """A beta code form as bare beta letters."""
    if not form:
        return ""
    return "".join(c for c in form.lower() if "a" <= c <= "z")


def pair(mine, theirs):
    """Pair MINE with THEIRS, or say why not.

    MINE is [(ROWID, FORM-IN-BETA)] and THEIRS is [(FORM-IN-GREEK, VALUES)],
    both in document order within one sentence.  Returns
    (PAIRS, AGREED, COMPARED): PAIRS is [(ROWID, VALUES)] and is empty where
    the sentence is not to be trusted."""
    if len(mine) != len(theirs) or not mine:
        return [], 0, 0
    agreed = 0
    pairs = []
    for (rowid, form), (other, values) in zip(mine, theirs):
        ours, that = skeleton_beta(form), skeleton_greek(other)
        # A form one side records and the other leaves empty is not a
        # disagreement about which word it is, so it is not counted either
        # way; a form both record must match.
        if ours and that:
            if ours == that:
                agreed += 1
            pairs.append((rowid, values))
        else:
            pairs.append((rowid, values))
    compared = sum(1 for (_, form), (other, _) in zip(mine, theirs)
                   if skeleton_beta(form) and skeleton_greek(other))
    return pairs, agreed, compared


def self_test():
    """Check the pairing on cases made up for the purpose."""
    failures = []

    def expect(name, got, want):
        if got != want:
            failures.append("%s: %r, wanted %r" % (name, got, want))
            print("   %-46s FAILED %r" % (name, got))
        else:
            print("   %-46s ok" % name)

    # The Aelian, as both databases have it.  Their capital carries the
    # breathing differently and their final sigma is `ς'; the skeletons agree.
    mine = [(1, "sto/ma"), (2, "e)mpe/fuke"), (3, "o)do/ntes"),
            (4, "memuko/tos")]
    theirs = [("στόμα", "N"), ("ἐμπέφυκε", "V"), ("ὀδόντες", "N"),
              ("μεμυκότος", "V")]
    pairs, agreed, compared = pair(mine, theirs)
    expect("four tokens pair", len(pairs), 4)
    expect("all four agree", (agreed, compared), (4, 4))

    # A capital with a breathing, which is where beta and Unicode differ most.
    pairs, agreed, compared = pair([(1, "*)axilleu/s")], [("Ἀχιλλεύς", "N")])
    expect("a capital with a breathing agrees", (agreed, compared), (1, 1))
    # Final sigma.
    pairs, agreed, compared = pair([(1, "lo/gos")], [("λόγος", "N")])
    expect("final sigma agrees", (agreed, compared), (1, 1))

    # A COUNT THAT DOES NOT MATCH IS REFUSED WHOLE.  This is the case the
    # check exists for: one side has a token the other has not, so every pair
    # after it is offset and every analysis after it would be attached to the
    # wrong word.
    pairs, agreed, compared = pair(mine, theirs[:3])
    expect("a short sentence pairs nothing", pairs, [])
    pairs, _, _ = pair([], [])
    expect("an empty sentence pairs nothing", pairs, [])

    # And a sentence whose counts match but whose words do not: the caller
    # sees a low rate of agreement and skips it.
    pairs, agreed, compared = pair([(1, "lo/gos"), (2, "pai=s")],
                                   [("ἄνθρωπος", "N"), ("λέων", "N")])
    expect("different words disagree", (agreed, compared), (0, 2))

    expect("punctuation is not a token here",
           skeleton_greek(","), "")
    print()
    if failures:
        print("   %d FAILED" % len(failures))
        return 1
    print("   the pairing is sound")
    return 0


def our_texts(db):
    """What we hold, as (PAIRS, BY_TLG).

    PAIRS is our own (author_id, work_id); BY_TLG maps the TLG's own
    (author_id, work_id) to ours where the two differ.

    WHY THE SECOND MAP.  Diorisis numbers its own works and the TLG numbers
    them differently -- Euripides' Hecuba is 040 to Diorisis and 007 to the
    TLG, and thirteen plays are out by the same kind of shift.  Their DuckDB
    is keyed by the TLG's numbers, so pairing on ours alone passed over
    thirteen texts of Euripides, the whole of the tragedians' overlap.

    `tlg_work_id' is what `diorisis-tlg-numbers.py' wrote into `texts' for
    exactly this, and it is read here where the column exists -- a database
    indexed before that script was written has no such column, and pairing on
    our own numbers is what it could do anyway."""
    pairs = set(db.execute("SELECT author_id, work_id FROM texts").fetchall())
    by_tlg = {}
    have = set(row[1] for row in
               db.execute("PRAGMA table_info(texts)").fetchall())
    if "tlg_work_id" in have:
        for author, work, tlg in db.execute(
                "SELECT author_id, work_id, tlg_work_id FROM texts"
                " WHERE tlg_work_id IS NOT NULL AND tlg_work_id != ''"):
            # KEYED BY THEIR SPELLING EXACTLY.  Stripping the letter as well
            # -- mapping their `052a' and a bare `052' both to our `052b' --
            # put two of their numbers on one key and whichever was read
            # second won.  `tlg_work_id' holds their spelling as it stands,
            # so nothing has to be guessed at.
            by_tlg[(author, tlg)] = (author, work)
    return pairs, by_tlg


def our_works(db, author):
    """The work ids we hold for AUTHOR, for saying what we have instead."""
    return [row[0] for row in db.execute(
        "SELECT work_id FROM texts WHERE author_id = ? ORDER BY work_id",
        (author,))]


def identify(comb_tlg_id, known, by_tlg=None):
    """COMB_TLG_ID as our (AUTHOR_ID, WORK_ID), or None with a reason.

    Theirs is `0545-001'.  THIRTEEN OF THEM CARRY A LETTER -- `0086-029b' --
    where Diorisis split a work into parts, and our indexer took the digits
    only: two files became one (author, work) and the second replaced the
    first, which is why our index has 812 texts where theirs has 820.  Those
    cannot be told apart from here and are not guessed at."""
    parts = (comb_tlg_id or "").split("-")
    if len(parts) != 2:
        return None, "not shaped like an id"
    author, work = parts[0].zfill(4), parts[1]
    ours = (author, work.zfill(3))
    # THEIR NUMBER FIRST, AND THIS ORDER MATTERS.  The two numberings share a
    # namespace and collide: the TLG's `0007-052b' is Caius Gracchus, which
    # Diorisis numbers 052 -- while OUR `052b' is Tiberius, whom the TLG calls
    # 052a.  Matching on our own ids first therefore took their 052b as ours
    # and merged the wrong Life into the wrong text.  The document ids being
    # read are always theirs, so what `tlg_work_id' says about them is the
    # better evidence, and our own numbering is the fallback for the 795 texts
    # where the two agree.
    for key in (ours, (author, work)):
        instead = (by_tlg or {}).get(key)
        if instead:
            return instead, None
    if ours in known:
        return ours, None
    if not work[-1].isdigit():
        return None, "a lettered part our index cannot distinguish"
    return None, "no such text in our index"


def add_columns(db, write):
    """Add the columns, and say which were added."""
    have = set(row[1] for row in
               db.execute("PRAGMA table_info(occurrences)").fetchall())
    wanted = [name for name, _ in COLUMNS if name not in have]
    if wanted and write:
        for name in wanted:
            db.execute("ALTER TABLE occurrences ADD COLUMN %s TEXT" % name)
        db.commit()
    return wanted


def merge(duck, ours, write, limit, threshold):
    known, by_tlg = our_texts(ours)
    if by_tlg:
        # COUNTED AS THE ONES THAT DIFFER, which is what the sentence says.
        # The map holds every text that has a `tlg_work_id' -- most of them
        # mapping to themselves, which is how a document keyed by either
        # number is found -- so its size said 820 where the answer is 25.
        differ = sum(1 for (author, tlg), (_, work) in by_tlg.items()
                     if tlg.zfill(3) != work)
        print("   %d of %d works are numbered differently by the TLG;"
              " all are paired by `tlg_work_id'" % (differ, len(by_tlg)))
    added = add_columns(ours, write)
    print("   columns %s" % ("already present" if not added
                             else ("added: " if write else "to add: ")
                             + ", ".join(added)))
    if not write:
        print("   DRY RUN: nothing will be written.  Pass --write to write.")

    documents = duck.execute(
        "SELECT comb_tlg_id FROM document ORDER BY comb_tlg_id").fetchall()
    if limit:
        documents = documents[:limit]

    skipped_texts = []
    done = sentences_merged = sentences_skipped = tokens = 0
    agreed_total = compared_total = 0

    for index, (comb,) in enumerate(documents, 1):
        identity, why = identify(comb, known, by_tlg)
        if not identity:
            # WHAT WE HAVE INSTEAD, said here rather than left to be asked
            # for.  A text of theirs we cannot place is either a numbering
            # that differs from ours or a text our index lost, and the two
            # look nothing alike once the author's own work ids are printed
            # beside the one that was looked for.
            author = (comb or "").split("-")[0].zfill(4)
            mine = our_works(ours, author)
            title = duck.execute(
                "SELECT author, title FROM document WHERE comb_tlg_id = ?",
                [comb]).fetchone()
            skipped_texts.append(
                (comb, "%s -- %s, %s -- we hold %s for %s"
                 % (why,
                    (title or ["?", "?"])[0], (title or ["?", "?"])[1],
                    ", ".join(mine[:12]) + ("..." if len(mine) > 12 else "")
                    or "nothing",
                    author)))
            continue
        author, work = identity

        # THEIRS, LESS PUNCTUATION AND LESS THE UNLEMMATISED.  Those are the
        # two kinds of token our index does not hold: the first by design, the
        # second because a token the tagger left without a lemma has nothing
        # to index.  Both are marked `_' in `self_lemma'.
        rows = duck.execute(
            "SELECT CAST(sent_id AS INTEGER), self_form, %s FROM word"
            " WHERE comb_tlg_id = ? AND self_pos <> 'punctuation'"
            " AND self_lemma <> '_'"
            " ORDER BY CAST(sent_id AS INTEGER), CAST(seq_id AS INTEGER)"
            % ", ".join(theirs for _, theirs in COLUMNS),
            [comb]).fetchall()
        theirs_by_sentence = {}
        for row in rows:
            values = tuple(None if value in (None, EMPTY, "") else value
                           for value in row[2:])
            theirs_by_sentence.setdefault(row[0], []).append((row[1], values))

        mine_by_sentence = {}
        for rowid, sentence, form in ours.execute(
                "SELECT rowid, sentence, form FROM occurrences"
                " WHERE author_id = ? AND work_id = ? ORDER BY rowid",
                (author, work)):
            mine_by_sentence.setdefault(sentence, []).append((rowid, form))

        updates = []
        text_agreed = text_compared = 0
        for sentence, mine in mine_by_sentence.items():
            pairs, agreed, compared = pair(
                mine, theirs_by_sentence.get(sentence, []))
            if not pairs:
                sentences_skipped += 1
                continue
            # THE RATE, NOT THE COUNT.  One token in a long sentence spelled
            # otherwise in the two releases is not a misalignment; a third of
            # them is.
            if compared and agreed < threshold * compared:
                sentences_skipped += 1
                continue
            sentences_merged += 1
            text_agreed += agreed
            text_compared += compared
            updates.extend(pairs)

        if text_compared and text_agreed < threshold * text_compared:
            skipped_texts.append(
                (comb, "only %d of %d forms agreed"
                 % (text_agreed, text_compared)))
            continue

        agreed_total += text_agreed
        compared_total += text_compared
        tokens += len(updates)
        done += 1
        if write and updates:
            ours.executemany(
                "UPDATE occurrences SET %s WHERE rowid = ?"
                % ", ".join("%s = ?" % name for name, _ in COLUMNS),
                [values + (rowid,) for rowid, values in updates])
            ours.commit()
        if index % 50 == 0 or index == len(documents):
            print("   %4d of %d texts, %9d tokens" % (index, len(documents),
                                                      tokens), flush=True)

    print()
    print("   %d texts merged, %d skipped" % (done, len(skipped_texts)))
    print("   %d sentences merged, %d skipped" % (sentences_merged,
                                                  sentences_skipped))
    print("   %d tokens carried across" % tokens)
    if compared_total:
        print("   %.4f%% of compared forms agreed"
              % (100.0 * agreed_total / compared_total))
    if skipped_texts:
        print()
        print("   the texts passed over:")
        for comb, why in skipped_texts[:40]:
            print("      %s  %s" % (comb, why))
        if len(skipped_texts) > 40:
            print("      ... and %d more" % (len(skipped_texts) - 40))


def main():
    parser = argparse.ArgumentParser(
        description="Carry the DuckDB Diorisis' morphology onto our index.")
    parser.add_argument("duckdb", nargs="?", help="Diorisis.duckdb")
    parser.add_argument("sqlite", nargs="?", help="our diorisis.db")
    parser.add_argument("--into", default=None, metavar="FILE",
                        help="copy the sqlite database here first and write "
                             "the columns onto the copy, leaving the original "
                             "untouched -- so that both are available and "
                             "Emacs can be switched between them")
    parser.add_argument("--write", action="store_true",
                        help="actually write; without it, a dry run")
    parser.add_argument("--limit", type=int, default=0,
                        help="stop after this many texts, for a trial")
    parser.add_argument("--threshold", type=float, default=0.9,
                        help="the fraction of forms that must agree, 0.9")
    parser.add_argument("--self-test", action="store_true",
                        help="check the pairing logic and exit")
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

    # ONTO A COPY, WHERE ONE IS ASKED FOR.  The columns are added to the
    # database given, which is the corpus itself -- and a reader may
    # reasonably want both: the plain Diorisis, which is what the corpus
    # publishes, and a merged one with the decomposed morphology, the dialect
    # and the prosody.  `--into' copies first and writes to the copy, so
    # neither is a guess about which they wanted.
    #
    # COPIED WITH THE FILE SYSTEM and not by SQL: a gigabyte of SQLite copies
    # in seconds and `VACUUM INTO' would want the same space and more time.
    # A DRY RUN READS THE ORIGINAL.  It was opening the target, which a dry
    # run has not copied -- and `sqlite3.connect' CREATES a file it cannot
    # find, so the run met an empty database with no `texts' in it and said
    # so in a traceback.  Nothing is written either way, so the original is
    # the right thing to read and the copy is made only when it will be
    # written to.
    target = args.sqlite
    if args.into and args.write:
        target = args.into
        if os.path.exists(target):
            print("   %s is there already and will be overwritten"
                  % os.path.basename(target))
        print("   copying %s -> %s (%.1f GB)"
              % (os.path.basename(args.sqlite), os.path.basename(target),
                 os.path.getsize(args.sqlite) / 1e9))
        shutil.copyfile(args.sqlite, target)
    elif args.into:
        print("   a dry run: reading %s, and copying nothing"
              % os.path.basename(args.sqlite))

    ours = sqlite3.connect(target)
    print("   %s -> %s" % (os.path.basename(args.duckdb),
                           os.path.basename(target)))
    merge(duck, ours, args.write, args.limit, args.threshold)
    ours.close()
    duck.close()
    print()


if __name__ == "__main__":
    main()
