#!/usr/bin/env python3
"""diorisis-index.py -- the Diorisis corpus, made searchable by lemma.

WHAT DIORISIS IS.  820 texts, ten million words, every one of them lemmatised
and tagged for part of speech, from Homer to the fifth century.  Which lets a
reader ask what neither Diogenes nor the TLG's own engine can answer: every
occurrence of a LEMMA whatever form it takes, narrowed by morphology, by genre
or by century.

WHY IT JOINS WHAT IS ALREADY HERE.  Two things fall out for nothing.

The filenames carry the TLG numbers -- `Plato (0059) - Charmides (018).xml' --
and the `location' of each sentence is the citation the TLG uses, `153' being a
Stephanus page of the Charmides.  So a hit is a citation the rest of the system
already understands: it opens in the browser, the printed edition is found for
it, a note can be made on it.

And Diorisis was lemmatised from DIOGENES' OWN word list -- the paper says so:
`Resources/perl/Perseus_Data/greek-analyses.txt'.  So a Diorisis lemma is the
same string Diogenes' parser returns for a form, and a hit leads to the LSJ
entry with nothing translated.

WHY SQLITE AND NOT AN ELD.  Ten million rows.  The indexes elsewhere in this
project are read into Emacs whole, which is right for a few thousand rows and
impossible for this.  Emacs 29 speaks SQLite natively, so the query stays in
the database and only the hits come back.
"""

import argparse
import glob
import json
import os
import re
import sqlite3
import sys
import io
import xml.etree.ElementTree as ET


NUMBERS = re.compile(r"^(.*?)\s*\((\d+)\)\s*-\s*(.*?)\s*\((\d+)\)$")


def numbers_from(filename):
    """(AUTHOR-NAME, AUTHOR, WORK-TITLE, WORK) from a Diorisis filename.

    `Plato (0059) - Charmides (018).xml' -- the numbers being the TLG's own,
    which is what lets a hit here be opened there."""
    # EITHER RELEASE'S SUFFIX.  Stripping only `.xml' left `.json' on the end
    # of the name, so the work number was never found and every text of the
    # newer release was passed over as `not named as Diorisis names them'.
    base = os.path.splitext(os.path.basename(filename))[0]
    found = NUMBERS.match(base)
    if not found:
        return None, None, None, None
    return (found.group(1), found.group(2).zfill(4),
            found.group(3), found.group(4).zfill(3))


def bare(beta):
    """BETA without its diacritics: the letters, lower case.

    WHAT IT IS FOR.  `ignore diacritics' in the query builder, which the app
    offers on every form- and lemma-based search.  Beta code spells a
    diacritic with a punctuation mark -- `mu/w' is mu, acute, omega -- so
    dropping everything but the letters drops exactly the diacritics, and the
    asterisk that marks a capital goes with them, which is right: a search
    ignoring accents should not distinguish Zeus from zeus."""
    if not beta:
        return None
    return "".join(c for c in beta.lower() if "a" <= c <= "z") or None


SCHEMA = """
CREATE TABLE IF NOT EXISTS texts (
  author_id   TEXT,
  author      TEXT,
  work_id     TEXT,
  work        TEXT,
  genre       TEXT,
  subgenre    TEXT,
  date        TEXT,
  words       INTEGER,
  -- THE NUMBER THE TLG USES, where ours has been made unique with a letter
  -- for a work Diorisis splits into parts.  `diorisis--work-number'
  -- prefers this when it asks the browser for a passage.  For Euripides it is
  -- written by `diorisis-tlg-numbers.py' instead, Diorisis numbering his
  -- plays 040 to 052 where the TLG numbers them 007 to 019.
  tlg_work_id TEXT,
  PRIMARY KEY (author_id, work_id)
);

-- THE WORDS OF EACH SENTENCE, once.
--
-- Wanted because a hit means nothing on its own.  A list of citations is a
-- list of places to go and look; a list of citations WITH THE WORDS is a
-- reading.  So each sentence is kept whole, and a hit shows the sentence it
-- fell in.
--
-- Once per sentence and not once per token: ten million tokens would store
-- the same sentence twenty times over.
CREATE TABLE IF NOT EXISTS sentences (
  author_id   TEXT NOT NULL,
  work_id     TEXT NOT NULL,
  sentence    INTEGER NOT NULL,
  location    TEXT,
  words       TEXT,
  PRIMARY KEY (author_id, work_id, sentence)
);

CREATE TABLE IF NOT EXISTS occurrences (
  lemma       TEXT NOT NULL,
  pos         TEXT,
  morph       TEXT,
  form        TEXT,
  -- THE SAME TWO WITHOUT THEIR DIACRITICS, which is what `ignore diacritics'
  -- compares against.  SQLite folds no accents and has no function that
  -- would: the alternative was reading every candidate into Emacs and
  -- comparing there, which for a search of ten million rows is not an
  -- alternative.  Beta code makes it cheap -- the diacritics ARE the
  -- punctuation of it -- so this is the letters and nothing else.
  form_bare   TEXT,
  lemma_bare  TEXT,
  author_id   TEXT NOT NULL,
  work_id     TEXT NOT NULL,
  location    TEXT,
  sentence    INTEGER,
  -- WHERE IN THE SENTENCE, which is what a query about SEQUENCES needs:
  -- `the form o( followed within 3 words by the form a)nh/r' is arithmetic
  -- on these two columns and cannot be asked at all without them.
  --
  -- TWO COUNTS, because the corpus counts both ways and a query says which.
  -- `word_index' numbers the words alone; `node_index' numbers words and
  -- punctuation together, which is what `followed by' uses where
  -- `followed by (ignore punctuation)' uses the other.  In
  -- In `w) a)/ndres , e)gw', the last word is the third node and the
  -- second word.
  word_index  INTEGER,
  node_index  INTEGER,
  -- HOW SURE THE LEMMA IS.  A fifth of the corpus admits more than one
  -- lemma and the tagger resolved most of it; this is its confidence, or
  -- nothing where the form was unambiguous to begin with.  A reader
  -- counting occurrences of a word will want to know.
  confidence  REAL
);

-- THE PUNCTUATION, which is a searchable element in its own right and the
-- thing sentences are delimited by.  Kept apart from the occurrences: it has
-- no lemma, no morphology and nothing to say about a word, and a `mark'
-- column on ten million rows that is null on all but one in eight would be a
-- waste of the space and a trap for every query that forgot to exclude it.
CREATE TABLE IF NOT EXISTS punctuation (
  author_id   TEXT NOT NULL,
  work_id     TEXT NOT NULL,
  sentence    INTEGER,
  node_index  INTEGER,
  mark        TEXT
);

CREATE INDEX IF NOT EXISTS punctuation_place ON punctuation
  (author_id, work_id, sentence);

-- BY SENTENCE, for the sequence queries: a query about two words in one
-- sentence joins the table to itself on this.
CREATE INDEX IF NOT EXISTS occurrences_sentence ON occurrences
  (author_id, work_id, sentence);

-- BY THE BARE LEMMA, so that a search ignoring diacritics is a lookup and not
-- a scan.  The accented lemma has its own index; a reader who asks for
-- `mu/w' and a reader who asks for `muw' should wait the same time.
CREATE INDEX IF NOT EXISTS occurrences_lemma_bare ON occurrences
  (lemma_bare);

-- BY LEMMA, which is the only question this is for.  Ten million rows
-- answered by a scan would be a second apiece; by an index, instant.
CREATE INDEX IF NOT EXISTS occurrences_lemma ON occurrences (lemma);
CREATE INDEX IF NOT EXISTS occurrences_work  ON occurrences
  (author_id, work_id);
"""


def header_of(root):
    """The genre, subgenre and date a text declares, as far as it declares
    them.

    Diorisis adds these by hand to every text -- which is what lets a search
    be narrowed to tragedy, or to the fourth century -- and they sit in
    different places according to how the source was encoded, so each is
    looked for and none is insisted on."""
    def first(*paths):
        for path in paths:
            found = root.find(path)
            if found is not None:
                said = "".join(found.itertext()).strip()
                if said:
                    return said
        return None
    return (first(".//genre", ".//xenoData/genre"),
            first(".//subgenre", ".//xenoData/subgenre"),
            first(".//creation/date", ".//date"))


def read_text(path):
    """One text as (TEXT-ROW, OCCURRENCE-ROWS).

    Streamed with `iterparse' and cleared as it goes: the corpus is two and a
    half gigabytes and some of its texts are large enough that holding a tree
    for each would be felt."""
    author, author_id, work, work_id = (None, None, None, None)
    name, aid, title, wid = numbers_from(path)
    if not (aid and wid):
        return None, [], []

    rows = []
    marks = []
    genre = subgenre = date = None
    location = None
    sentence = None
    word_index = node_index = 0
    words = 0

    # The header first, which is small and wanted whole.
    try:
        for event, element in ET.iterparse(path, events=("end",)):
            tag = element.tag.split("}")[-1]
            if tag == "teiHeader":
                genre, subgenre, date = header_of(element)
                element.clear()
                break
    except ET.ParseError:
        pass

    try:
        for event, element in ET.iterparse(path, events=("start", "end")):
            tag = element.tag.split("}")[-1]
            if event == "start" and tag == "sentence":
                location = element.get("location")
                sentence = element.get("id")
                # THE COUNTS BEGIN AGAIN at every sentence, a position being
                # a position WITHIN one: the scope of every query the corpus
                # allows is one sentence.
                word_index = 0
                node_index = 0
            elif event == "end" and tag == "punct":
                node_index += 1
                marks.append((aid, wid,
                              int(sentence) if sentence
                              and sentence.isdigit() else None,
                              node_index, element.get("mark")))
                element.clear()
            elif event == "end" and tag == "word":
                form = element.get("form")
                word_index += 1
                node_index += 1
                for lemma in element:
                    if lemma.tag.split("}")[-1] != "lemma":
                        continue
                    entry = lemma.get("entry")
                    if not entry:
                        continue
                    # EVERY ANALYSIS, joined.  A form may admit several and
                    # the corpus keeps them all; a reader asking for an
                    # aorist participle wants the form whose analyses
                    # include one, not only those where it is the single
                    # possibility.
                    morphs = [a.get("morph") for a in lemma
                              if a.tag.split("}")[-1] == "analysis"
                              and a.get("morph")]
                    said = lemma.get("disambiguated")
                    try:
                        confidence = float(said)
                    except (TypeError, ValueError):
                        confidence = None
                    rows.append((entry, lemma.get("POS") or lemma.get("pos"),
                                 " | ".join(morphs) or None, form,
                                 bare(form), bare(entry),
                                 aid, wid, location,
                                 int(sentence) if sentence
                                 and sentence.isdigit() else None,
                                 word_index, node_index,
                                 confidence))
                    words += 1
                element.clear()
            elif event == "end" and tag == "sentence":
                element.clear()
    except ET.ParseError as error:
        print("      %s: %s" % (os.path.basename(path), error))

    return ((aid, name, wid, title, genre, subgenre, date, words),
            rows, marks)


def read_json(path):
    """One text of the JSON release as (TEXT-ROW, OCCURRENCE-ROWS).

    TWO RELEASES, TWO FORMATS.  The 2018 corpus is XML with its lemmata in
    UTF-8 and a bare location -- `153\' for a Stephanus page; the 2021 one
    (1.51) is JSON, its lemmata in BETA CODE and its locations full --
    `1.1.1.1\'.

    The beta code is no loss and arguably the gain: Diorisis was lemmatised
    from Diogenes\' own word list, which keys on beta code, so a lemma here is
    the string Diogenes\' parser returns and needs converting only to be shown
    to a reader.

    Both are read, so whichever release a reader has is the one that works."""
    name, aid, title, wid = numbers_from(path)
    if not (aid and wid):
        return None, []
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        datum = json.load(handle)
    rows = []
    texts = []
    marks = []
    words = 0
    for sentence in datum.get("sentences", []):
        location = sentence.get("location")
        said = sentence.get("id")
        number = int(said) if said and str(said).isdigit() else None
        # THE SENTENCE AS IT READS, from its own tokens.  The corpus keeps no
        # running text -- it is tokens all the way down -- so the sentence is
        # put back together from the forms and the punctuation, in order.
        said_words = []
        for token in sentence.get("tokens", []):
            if token.get("type") == "punct":
                if said_words:
                    said_words[-1] += (token.get("mark") or "")
                continue
            form = token.get("form")
            if form:
                said_words.append(form)
        if number is not None and said_words:
            texts.append((aid, wid, number, location, " ".join(said_words)))
        # COUNTED AS THEY COME.  Both counts advance over every token of the
        # right sort, whether or not it has a lemma: a word the tagger left
        # unlemmatised is still a word between two others, and a query about
        # what follows what must count it or the distances are wrong.
        word_index = 0
        node_index = 0
        for token in sentence.get("tokens", []):
            kind = token.get("type")
            if kind == "punct":
                node_index += 1
                marks.append((aid, wid, number, node_index,
                              token.get("mark")))
                continue
            if kind != "word":
                continue
            word_index += 1
            node_index += 1
            lemma = token.get("lemma") or {}
            entry = lemma.get("entry")
            if not entry:
                continue
            try:
                confidence = float(lemma.get("disambiguated"))
            except (TypeError, ValueError):
                confidence = None
            rows.append((entry, lemma.get("POS") or lemma.get("pos"),
                         " | ".join(lemma.get("analyses") or []) or None,
                         token.get("form"),
                         bare(token.get("form")), bare(entry),
                         aid, wid, location, number,
                         word_index, node_index, confidence))
            words += 1
    # The JSON release keeps no genre or date; the XML one did.
    return ((aid, name, wid, title, None, None,
             datum.get("version"), words), rows, texts, marks)


def read_catalogue(path):
    """The genre and date of each text, from `catalog.tsv\'.

    THE JSON RELEASE DROPS THEM.  Diorisis added a date and a genre to every
    text by hand -- which is what lets a search be narrowed to tragedy, or to
    the fourth century -- and the 2018 XML kept them in its TEI header while
    the 2021 JSON does not.

    Tauber's `diorisis\' repository extracts them into a tab-separated
    catalogue, keyed by the same TLG numbers, so they can be put back.  Pass
    it with `--catalogue\'; without it a text simply has no genre, and the
    searches that use one find nothing rather than being wrong."""
    found = {}
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        want = dict((name, i) for i, name in enumerate(header))
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < len(header):
                continue

            def field(name):
                index = want.get(name)
                return parts[index] if index is not None else None

            author = (field("tlgAuthor") or "").zfill(4)
            work = (field("tlgId") or "").zfill(3)
            if author and work:
                found[(author, work)] = (field("genre"), field("subgenre"),
                                         field("date"))
    return found


def main():
    parser = argparse.ArgumentParser(
        description="Index the Diorisis corpus for searching by lemma.")
    parser.add_argument("corpus", help="the directory of .xml files")
    parser.add_argument("-o", "--out", default=None,
                        help="the database, default diorisis.db in CORPUS")
    parser.add_argument("--catalogue", default=None,
                        help="catalog.tsv, for the genre and date the JSON "
                             "release drops")
    parser.add_argument("--limit", type=int, default=0,
                        help="stop after this many texts, for a trial run")
    args = parser.parse_args()

    if not os.path.isdir(args.corpus):
        sys.exit("%s is not a directory." % args.corpus)
    out = args.out or os.path.join(args.corpus, "diorisis.db")

    # WHICHEVER RELEASE IS THERE.  Not both at once: two releases of one
    # corpus in one index would count every word twice.
    catalogue = {}
    if args.catalogue:
        if not os.path.exists(args.catalogue):
            sys.exit("%s is not here." % args.catalogue)
        catalogue = read_catalogue(args.catalogue)
        print("   %d texts catalogued for genre and date" % len(catalogue))

    files = sorted(f for f in os.listdir(args.corpus) if f.endswith(".json"))
    kind = "json"
    if not files:
        files = sorted(f for f in os.listdir(args.corpus)
                       if f.endswith(".xml"))
        kind = "xml"
    if not files:
        sys.exit("No .json or .xml files in %s." % args.corpus)
    print("   the %s release, %d texts" % (kind.upper(), len(files)))
    if args.limit:
        files = files[:args.limit]

    # WRITTEN AFRESH.  A half-built index that looked complete would answer
    # questions wrongly and quietly, which is worse than answering none.
    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.executescript(SCHEMA)
    # The indexes are built at the END: inserting ten million rows into an
    # indexed table is several times slower than indexing them afterwards.
    db.execute("DROP INDEX IF EXISTS occurrences_lemma")
    db.execute("DROP INDEX IF EXISTS occurrences_work")

    total = 0
    seen = set()
    for i, name in enumerate(files, 1):
        path = os.path.join(args.corpus, name)
        try:
            if kind == "json":
                text, rows, texts, marks = read_json(path)
            else:
                text, rows, marks = read_text(path)
                texts = []
        except (ValueError, KeyError) as error:
            print("   %-58s %s" % (name[:58], error))
            continue
        if not text:
            print("   %-58s not named as Diorisis names them" % name[:58])
            continue
        # THE CATALOGUE'S GENRE AND DATE, where there is one.  The text's own
        # fields are used otherwise, which for the JSON release is nothing.
        said = catalogue.get((text[0], text[2]))
        if said:
            text = (text[0], text[1], text[2], text[3],
                    said[0] or text[4], said[1] or text[5],
                    said[2] or text[6], text[7])
        # TWO FILES, ONE NUMBER.  Diorisis splits a work into parts --
        # Plutarch's Agis and Cleomenes are one TLG work and two files, and
        # there are thirteen such -- and both carry the same number in their
        # names.  `INSERT OR REPLACE' put the second text row over the first
        # while the occurrences of both accumulated under one key: eight texts
        # lost, their word counts wrong, and their sentences overwriting each
        # other where the ids collided.  Found by comparing our 812 texts with
        # the 820 of Bilby's DuckDB compilation, not by reading anything here.
        #
        # So the second gets a letter -- `051b' -- as that compilation does,
        # and `tlg_work_id' keeps the number the browser can open.
        base = text[2]
        work = base
        suffix = 0
        while (text[0], work) in seen:
            suffix += 1
            work = "%s%s" % (base, chr(ord("a") + suffix))
        if work != base:
            print("   %-58s also %s, kept as %s" % (name[:58], base, work))
        seen.add((text[0], work))
        text = (text[0], text[1], work) + tuple(text[3:])
        # The work is the SEVENTH column now -- lemma, pos, morph, form,
        # form_bare, lemma_bare, author_id, work_id -- and a slice written for
        # the old shape would have quietly rewritten the author instead.
        rows = [row[:7] + (work,) + row[8:] for row in rows]
        texts = [(t[0], work) + tuple(t[2:]) for t in texts]
        marks = [(m[0], work) + tuple(m[2:]) for m in marks]
        db.execute("INSERT OR REPLACE INTO texts VALUES (?,?,?,?,?,?,?,?,?)",
                   text + (base,))
        db.executemany(
            "INSERT INTO occurrences VALUES\
 (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        if texts:
            db.executemany(
                "INSERT OR REPLACE INTO sentences VALUES (?,?,?,?,?)", texts)
        if marks:
            db.executemany(
                "INSERT INTO punctuation VALUES (?,?,?,?,?)", marks)
        total += len(rows)
        if i % 50 == 0 or i == len(files):
            db.commit()
            print("   %4d of %d texts, %9d words" % (i, len(files), total),
                  flush=True)
    db.commit()
    print("   indexing ...", flush=True)
    db.executescript(SCHEMA)
    db.commit()

    lemmas = db.execute("SELECT COUNT(DISTINCT lemma) FROM occurrences") \
               .fetchone()[0]
    texts = db.execute("SELECT COUNT(*) FROM texts").fetchone()[0]
    print()
    print("   %d texts, %d words, %d distinct lemmata" %
          (texts, total, lemmas))
    print("   %.0f MB" % (os.path.getsize(out) / 1e6))
    print(out)
    db.close()


if __name__ == "__main__":
    main()
