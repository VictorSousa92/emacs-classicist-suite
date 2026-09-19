#!/usr/bin/env python3
"""make-diorisis-fixture.py -- a tiny Diorisis database, for testing.

WHY THIS EXISTS.  The real index is 1238 MB and takes an hour to build from a
two-and-a-half-gigabyte corpus.  Nothing in `diorisis.el' needs that: it
needs a database with the right SCHEMA and the right AWKWARDNESSES.  So this
writes one of about forty sentences, small enough to commit and to read, and
holding on purpose every shape that has bitten:

  * a location of two levels, three levels and four -- `1.1', `1.19.5',
    `1.1.1.1' -- because the search must not assume it parses like a TLG
    citation;
  * a location with QUOTES INSIDE THE VALUE -- `'513.3'' for Aristides, cited
    by Dindorf page -- which is what the corpus actually holds;
  * a Stephanus page, `153c', where the level is not a number;
  * a date that is a YEAR (`-750', `230') and one that is the JSON release's
    VERSION STRING (`1.51') leaking into the date column, which is what
    happens for a text the catalogue does not cover.  A century filter must
    exclude the second rather than reading it as the year 1;
  * a text with no genre and no date at all;
  * an occurrence whose sentence is MISSING from `sentences', which is why the
    search joins that table with LEFT JOIN;
  * a form with several analyses joined by ` | ', so a morphology search has
    something to match the middle of;
  * a confidence that is a number and one that is NULL -- NULL meaning the
    form admitted only one lemma, and so being the certain case rather than
    the unknown one.

THE GREEK IS BETA CODE, as the real corpus's is, and the lemmata are the
strings Diogenes' own parser returns.  The Homer and the Aelian are quoted
text; the rest are plausible sentences written for the fixture.  Nothing here
should be mistaken for a source.

    python3 tools/make-diorisis-fixture.py /tmp/diorisis-fixture.db
"""

import importlib.util
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
INDEXER = os.path.join(os.path.dirname(HERE), "diorisis-index.py")


def bare(beta):
    """The indexer's own `bare', imported rather than reimplemented."""
    return _indexer().bare(beta)


_MODULE = []


def _indexer():
    """The indexer, loaded once and kept."""
    if not _MODULE:
        spec = importlib.util.spec_from_file_location("diorisis_index",
                                                      INDEXER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _MODULE.append(module)
    return _MODULE[0]


def schema():
    """The indexer's own SCHEMA, imported rather than copied.

    A fixture whose schema had drifted from the indexer's would test the
    search against a database no reader has.  The file's name has a hyphen in
    it and cannot be imported by name, so it is loaded by path."""
    return _indexer().SCHEMA


# (author_id, author, work_id, work, genre, subgenre, date, words)
TEXTS = [
    ("0012", "Homer", "001", "Iliad", "Epic", None, "-750", 9),
    ("0059", "Plato", "018", "Charmides", "Philosophy", "Dialogue",
     "-380", 8),
    ("0545", "Aelian", "001", "De natura animalium", "Technical",
     "Zoology", "230", 11),
    ("0532", "Achilles Tatius", "001", "Leucippe et Clitophon",
     "Narrative", "Novel", "150", 7),
    ("0284", "Aristides", "002", "Orationes", "Oratory", None, "170", 6),
    # THE VERSION STRING IN THE DATE COLUMN.  `read_json' falls back on the
    # release's version where the catalogue covers nothing, so a text can
    # carry `1.51' as its date.  A century filter must not read that as a year.
    ("9999", "Anonymus", "001", "Fragmentum incertum", None, None,
     "1.51", 4),
    # AND A TEXT THAT DECLARES NOTHING.  Genre and date both absent.
    ("2200", "Anonymus alter", "003", "Fragmenta", None, None, None, 3),
    # THE TEXT WHOSE NUMBER IS NOT THE TLG'S.  Diorisis numbers the Hecuba
    # 040; the TLG numbers it 0006.007.  `tlg_work_id' below is what
    # `diorisis-tlg-numbers.py' writes, and what the browser must be asked
    # for -- 040 is not this play anywhere but here.
    ("0006", "Euripides", "040", "Hecuba", "Drama", "Tragedy", "-424", 5),
]

# (author_id, work_id, tlg_work_id) -- the correction, as the script writes it.
TLG_NUMBERS = [
    ("0006", "040", "007"),
    ("0545", "001", "001"),
]

# (author_id, work_id, sentence, location, words)
SENTENCES = [
    ("0012", "001", 1, "1.1",
     "mh=nin a)/eide qea\\ *phlhi+a/dew *)axilh=os"),
    ("0012", "001", 2, "1.2",
     "ou)lome/nhn h(\\ mu/ri' *)axaioi=s a)/lge' e)/qhken"),
    ("0059", "018", 1, "153c",
     "kai\\ o( *xairefw=n e)/fh pai=s ti/s e)stin o( lo/gos"),
    ("0059", "018", 2, "153d",
     "e)gw\\ de\\ tou=ton to\\n lo/gon ou)k a)nte/xomai le/gein"),
    ("0545", "001", 19, "1.19.5",
     "sto/ma de\\ au)tw=| e)mpe/fuke smikro/n oi( de\\ o)do/ntes "
     "memuko/tos tou= sto/matos ou)k a(\\n i)/dois"),
    ("0545", "001", 20, "1.20.1",
     "o( de\\ le/wn, memuko/ta e)/xwn ta\\ o)/mmata kaqeu/dei."),
    ("0532", "001", 1, "1.1.1.1",
     "*sidw\\n e)pi\\ qala/tth| po/lis"),
    ("0532", "001", 2, "1.1.2.3",
     "o( de\\ pai=s e)/legen o(/ti me/mukas tou\\s o)fqalmou/s"),
    # QUOTES INSIDE THE VALUE.  Aristides is cited by Dindorf page and the
    # corpus wrote the page with its quotation marks left on.
    ("0284", "002", 7, "'513.3'",
     "ou)k a(\\n ou)=n o( lo/gos memuko/si toi=s a)nqrw/pois le/goito"),
    ("9999", "001", 1, "3",
     "mu/ei ga\\r o( a)/nqrwpos"),
    ("2200", "003", 1, None,
     "a)/nqrwpon le/gw"),
    # VERSE: THE CITATION IS A LINE, one level and no stop, which is how the
    # corpus cites Euripides -- and the line is where the SENTENCE begins.
    ("0006", "040", 3, "560",
     "ti/ ta\\s ko/ras memukui/as e)/xeis ou)/t' e)/gxos"),
]

# (lemma, pos, morph, form, author_id, work_id, location, sentence,
#  confidence)
OCCURRENCES = [
    ("mh=nis", "noun", "fem acc sg", "mh=nin",
     "0012", "001", "1.1", 1, None),
    ("a)ei/dw", "verb", "pres imperat act 2nd sg | pres ind act 2nd sg",
     "a)/eide", "0012", "001", "1.1", 1, 0.62),
    ("qea/", "noun", "fem voc sg | fem nom sg", "qea\\",
     "0012", "001", "1.1", 1, 0.91),
    ("ti/qhmi", "verb", "aor ind act 3rd sg", "e)/qhken",
     "0012", "001", "1.2", 2, None),
    ("pai=s", "noun", "masc nom sg", "pai=s",
     "0059", "018", "153c", 1, None),
    ("lo/gos", "noun", "masc nom sg", "lo/gos",
     "0059", "018", "153c", 1, None),
    ("le/gw", "verb", "pres inf act", "le/gein",
     "0059", "018", "153d", 2, 0.77),
    ("lo/gos", "noun", "masc acc sg", "lo/gon",
     "0059", "018", "153d", 2, None),
    ("a)nte/xw", "verb", "pres ind mid 1st sg", "a)nte/xomai",
     "0059", "018", "153d", 2, None),
    ("sto/ma", "noun", "neut nom sg | neut acc sg", "sto/ma",
     "0545", "001", "1.19.5", 19, 0.88),
    ("e)mfu/w", "verb", "perf ind act 3rd sg", "e)mpe/fuke",
     "0545", "001", "1.19.5", 19, None),
    ("o)dou/s", "noun", "masc nom pl", "o)do/ntes",
     "0545", "001", "1.19.5", 19, None),
    # THE HIT THE HANDOVER VERIFIED.  A perfect participle of `mu/w', in the
    # genitive, its analyses several.
    ("mu/w", "verb",
     "perf part act masc gen sg | perf part act neut gen sg",
     "memuko/tos", "0545", "001", "1.19.5", 19, 0.95),
    ("mu/w", "verb", "perf part act neut acc pl | perf part act masc acc sg",
     "memuko/ta", "0545", "001", "1.20.1", 20, 0.71),
    ("le/wn", "noun", "masc nom sg", "le/wn",
     "0545", "001", "1.20.1", 20, None),
    ("po/lis", "noun", "fem nom sg", "po/lis",
     "0532", "001", "1.1.1.1", 1, None),
    ("pai=s", "noun", "masc nom sg", "pai=s",
     "0532", "001", "1.1.2.3", 2, None),
    ("mu/w", "verb", "perf ind act 2nd sg", "me/mukas",
     "0532", "001", "1.1.2.3", 2, 0.83),
    ("o)fqalmo/s", "noun", "masc acc pl", "o)fqalmou/s",
     "0532", "001", "1.1.2.3", 2, None),
    ("mu/w", "verb", "perf part act masc dat pl", "memuko/si",
     "0284", "002", "'513.3'", 7, 0.66),
    ("a)/nqrwpos", "noun", "masc dat pl", "a)nqrw/pois",
     "0284", "002", "'513.3'", 7, None),
    ("lo/gos", "noun", "masc nom sg", "lo/gos",
     "0284", "002", "'513.3'", 7, None),
    ("mu/w", "verb", "pres ind act 3rd sg", "mu/ei",
     "9999", "001", "3", 1, None),
    ("a)/nqrwpos", "noun", "masc nom sg", "a)/nqrwpos",
     "9999", "001", "3", 1, None),
    ("a)/nqrwpos", "noun", "masc acc sg", "a)/nqrwpon",
     "2200", "003", None, 1, None),
    ("le/gw", "verb", "pres ind act 1st sg", "le/gw",
     "2200", "003", None, 1, None),
    ("mu/w", "verb", "perf part act fem acc pl", "memukui/as",
     "0006", "040", "560", 3, None),
    # AN OCCURRENCE WHOSE SENTENCE IS NOT STORED.  Sentence 21 of the Aelian
    # is in no row of `sentences', which is what the LEFT JOIN is for: the hit
    # is real and must be listed, with no words to show for it.
    ("mu/w", "verb", "perf part act fem nom sg", "memukui=a",
     "0545", "001", "1.21.2", 21, 0.58),
]


def positions():
    """The occurrences with a word and node index worked out for each.

    COMPUTED FROM THE SENTENCES rather than typed in.  A position typed by
    hand would be wrong the first time a fixture sentence was edited, and
    wrong in a way that made the sequence queries pass or fail for no reason
    anybody could see.  So each sentence is walked, its words numbered, and
    its punctuation counted as nodes where the stored sentence shows one.

    The rule matches the indexer's: both counts advance over a word, only the
    node count over a punctuation mark."""
    words_of = {}
    for author, work, number, location, text in SENTENCES:
        words_of[(author, work, number)] = text.split()
    placed = []
    for row in OCCURRENCES:
        lemma, pos, morph, form, author, work, location, number, conf = row
        tokens = words_of.get((author, work, number), [])
        word_index = node_index = None
        nodes = 0
        for index, token in enumerate(tokens, 1):
            nodes += 1
            if token.rstrip(",.;:") != token:
                # A mark attached to this word is a node of its own, after it.
                pass
            if token.rstrip(",.;:") == form or token == form:
                word_index, node_index = index, nodes
                break
            if token.rstrip(",.;:") != token:
                nodes += 1
        placed.append((lemma, pos, morph, form,
                       bare(form), bare(lemma),
                       author, work, location,
                       number, word_index, node_index, conf))
    return placed


def marks():
    """The punctuation of each fixture sentence, as nodes."""
    found = []
    for author, work, number, location, text in SENTENCES:
        nodes = 0
        for token in text.split():
            nodes += 1
            bare = token.rstrip(",.;:")
            if bare != token:
                nodes += 1
                found.append((author, work, number, nodes, token[len(bare):]))
    return found


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "diorisis-fixture.db"
    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.executescript(schema())
    # `tlg_work_id' last, and null here: the schema carries it now, and
    # `diorisis-tlg-numbers.py' or the indexer fills it.
    db.executemany("INSERT INTO texts VALUES (?,?,?,?,?,?,?,?,NULL)", TEXTS)
    db.executemany("INSERT INTO sentences VALUES (?,?,?,?,?)", SENTENCES)
    db.executemany(
        "INSERT INTO occurrences VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        positions())
    db.executemany("INSERT INTO punctuation VALUES (?,?,?,?,?)", marks())
    db.executemany("UPDATE texts SET tlg_work_id = ? WHERE author_id = ?"
                   " AND work_id = ?",
                   [(tlg, author, work)
                    for author, work, tlg in TLG_NUMBERS])
    db.commit()
    lemmata = db.execute(
        "SELECT COUNT(DISTINCT lemma) FROM occurrences").fetchone()[0]
    print("   %d texts, %d sentences, %d occurrences, %d distinct lemmata"
          % (len(TEXTS), len(SENTENCES), len(OCCURRENCES), lemmata))
    print(out)
    db.close()


if __name__ == "__main__":
    main()
