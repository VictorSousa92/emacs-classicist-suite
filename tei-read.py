#!/usr/bin/env python3
"""tei-read.py -- one TEI text, as citations and the words under them.

WHY A CONVERTER.  The same division the rest of this uses: Python reads the
awkward source, elisp displays it.  A Perseus text is a megabyte of TEI and
gathering the words under each citation is a stream parser's work.

HOW A TEXT IS CITED.  By its DIVISIONS, which every text in these corpora has
by construction:

    <div type="textpart" subtype="book"    n="1">
      <div type="textpart" subtype="section" n="1">   ->  1.1
      <div type="textpart" subtype="section" n="2">   ->  1.2

That is the CTS scheme the corpora are published under, and the `xml:base' of
an inner division spells it out -- `...perseus-grc2:1' being the base for the
sections of book 1.  So a citation is the nested `n' attributes joined by
stops, and the `subtype' attributes name the levels: book, section.

AND WHAT A MILESTONE IS.  Not always the citation, which is where the first
version of this went wrong.  It insisted on `<milestone unit="section">' and
found Plato --

    <milestone unit="section" resp="Stephanus" n="327a"/>

-- because Stephanus pages ARE how Plato is cited.  Galen has no such thing:

    <milestone unit="page" resp="kuhn" n="k.v.2.p.1"/>

which is Kuehn's printed pagination, a SECOND way of referring to a passage
and not the first.  So a milestone is recorded BESIDE the citation rather than
as it, and a reader may have either: `327a' for Plato, because that is what
one writes, and Kuehn's volume and page for Galen, because that is what the
secondary literature gives.

WHERE A MILESTONE IS THE CITATION.  For Plato it is, and `--cite-by-milestone'
says so: then the milestone's `n' is the citation and the divisions are
recorded beside it instead.  Which way round a text wants is a fact about the
text; the default is the divisions, which is right for the greater number.
"""

import argparse
import io
import os
import sys
import xml.etree.ElementTree as ET


def strip_namespace(tree):
    """The tree without namespaces, which make every path unreadable."""
    for element in tree.iter():
        if isinstance(element.tag, str) and "}" in element.tag:
            element.tag = element.tag.split("}", 1)[1]
        for key in list(element.attrib):
            if "}" in key:
                element.attrib[key.split("}", 1)[1]] = element.attrib.pop(key)
    return tree


SKIP = {"teiHeader", "note", "app", "bibl", "head", "speaker", "label",
        "orig", "sic", "figure", "fw", "gap", "ref"}
"""Elements whose text is not the text.

The header is apparatus, a `note' is an editor speaking, an `app' the
variants, a `head' a heading belonging to no citation.  Leaving them in put an
editor's English in the middle of a Greek sentence."""

BREAKS = {"p", "lg", "sp", "ab", "quote"}
"""Elements after which a space is owed, or the last word of one runs into the
first of the next."""


class Reader:
    """One text, read once.

    A CLASS because the walk carries state -- which divisions are open, which
    milestone was last seen, the words gathered so far -- and threading five
    accumulators through a recursive function is what made the first version
    hard to follow."""

    def __init__(self, cite_by_milestone=False):
        self.cite_by = cite_by_milestone
        self.stack = []          # (LEVEL, N) of the divisions now open
        self.milestone = None    # the last one seen, as (UNIT, RESP, N)
        self.words = []
        self.passages = []       # (CITATION, LEVELS, MILESTONE, WORDS)
        self.levels = []         # the level names, outermost first
        self.books = []          # [N, CITATION] for each `book' division
        self.urn = None
        self.language = None

    def citation(self):
        """Where the walk is, as a citation.

        BY THE UNIT, and not by a list of authors.  A milestone of unit
        `section' IS a citation scheme -- `<milestone unit="section"
        resp="Stephanus" n="327a">' is how Plato is cited and how the TLG
        files him.  A milestone of unit `page' is a printed edition's
        pagination: Kuehn's `k.v.2.p.1' is a second way of referring to a
        passage of Galen, not the first.
        
        So the unit decides, which needs no configuration and is right for
        both -- and `--cite-by-milestone' remains for a text that marks its
        citation some third way."""
        if self.milestone and (self.cite_by
                               or self.milestone[0] == "section"):
            return self.milestone[2]
        return ".".join(n for _level, n in self.stack if n) or None

    def note_level(self, name):
        """NAME as a level, in the order the text nests them."""
        if name and name not in self.levels:
            self.levels.append(name)

    def flush(self):
        """Keep what has been gathered, under the citation in force."""
        words = " ".join("".join(self.words).split())
        del self.words[:]
        citation = self.citation()
        if citation and words:
            self.passages.append((
                citation,
                [n for _level, n in self.stack if n],
                self.milestone[2] if self.milestone else None,
                words))

    def walk(self, element):
        tag = element.tag
        if tag in SKIP:
            # The tail still belongs to the text: only the element is passed
            # over.
            if element.tail:
                self.words.append(element.tail)
            return

        if tag == "milestone":
            unit = element.get("unit")
            number = element.get("n")
            if number and unit not in ("para", "line"):
                # A new reference begins, so what came before is kept.
                self.flush()
                self.milestone = (unit, element.get("resp"), number)
            if element.tail:
                self.words.append(element.tail)
            return

        if tag == "div":
            kind = element.get("type")
            if kind in ("edition", "translation"):
                # THE TEXT SAYS what it is and in what language.  The first
                # version guessed both from the file's name and was wrong for
                # anything outside the usual tree.
                self.urn = element.get("n") or self.urn
                self.language = element.get("lang") or self.language
            number = element.get("n")
            subtype = element.get("subtype")
            opened = False
            if kind == "textpart" and number:
                self.flush()
                self.stack.append((subtype or "part", number))
                self.note_level(subtype or "part")
                opened = True
                if subtype == "book":
                    # Filled in after the walk: a book's citation is the one
                    # in force once its first passage is reached.
                    self.books.append([number, None])
            if element.text:
                self.words.append(element.text)
            for child in element:
                self.walk(child)
            self.flush()
            if opened:
                self.stack.pop()
            if element.tail:
                self.words.append(element.tail)
            return

        if tag == "l" and element.get("n"):
            # A VERSE IS A CITATION.  Homer is cited by book and line, and the
            # line is an `<l n="1">' element rather than a division or a
            # milestone -- so a reader that treated it as mere text threw the
            # number away and cited every poem by book alone, which is most of
            # Greek verse made uncitable.
            #
            # Treated as a division, and the stack does the rest: inside
            # `<div subtype="book" n="1">' the line gives `1.1'.
            self.flush()
            self.stack.append(("line", element.get("n")))
            self.note_level("line")
            if element.text:
                self.words.append(element.text)
            for child in element:
                self.walk(child)
            self.flush()
            self.stack.pop()
            self.words.append(" ")
            if element.tail:
                self.words.append(element.tail)
            return

        if tag in ("lb", "pb", "cb"):
            self.words.append(" ")
            if element.tail:
                self.words.append(element.tail)
            return

        if element.text:
            self.words.append(element.text)
        for child in element:
            self.walk(child)
        if tag in BREAKS:
            self.words.append(" ")
        if element.tail:
            self.words.append(element.tail)

    def read(self, path):
        root = strip_namespace(ET.parse(path)).getroot()
        self.walk(root)
        self.flush()
        for entry in self.books:
            for citation, levels, _milestone, _words in self.passages:
                if levels and levels[0] == entry[0]:
                    entry[1] = citation
                    break
        return self


def elisp(value):
    if value is None:
        return "nil"
    if isinstance(value, str):
        return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')
    return str(value)


def write(out, reader):
    with io.open(out, "w", encoding="utf-8") as handle:
        handle.write(";; One TEI text, as citations and their words.\n")
        handle.write(";; Written by tei-read.py; do not edit by hand.\n")
        handle.write(";; The citation is the CTS division hierarchy, and a\n")
        handle.write(";; milestone is recorded beside it where there is one:\n")
        handle.write(";; Stephanus for Plato, Kuehn for Galen.\n")
        handle.write("(:urn %s\n :language %s\n" % (elisp(reader.urn),
                                                    elisp(reader.language)))
        handle.write(" :levels (%s)\n"
                     % " ".join(elisp(level) for level in reader.levels))
        handle.write(" :books (")
        for number, citation in reader.books:
            handle.write("(%s %s)" % (elisp(number), elisp(citation)))
        handle.write(")\n :passages\n (")
        for i, passage in enumerate(reader.passages):
            citation, _levels, milestone, words = passage
            handle.write("%s(%s %s . %s)"
                         % ("" if i == 0 else "\n  ",
                            elisp(citation), elisp(milestone), elisp(words)))
        handle.write("))\n")
    return out


def main():
    parser = argparse.ArgumentParser(
        description="One TEI text, as citations and their words.")
    parser.add_argument("text")
    parser.add_argument("out", nargs="?")
    parser.add_argument("--cite-by-milestone", action="store_true",
                        help="any milestone is the citation, not only one "
                             "of unit `section'")
    args = parser.parse_args()

    out = args.out or os.path.splitext(args.text)[0] + ".eld"
    reader = Reader(args.cite_by_milestone).read(args.text)
    if not reader.passages:
        sys.exit("Nothing to cite by in %s: it marks neither textpart "
                 "divisions nor milestones" % args.text)
    seconds = sum(1 for p in reader.passages if p[2])
    print("   %-44s %5d passages, %2d books, by %s%s"
          % (os.path.basename(args.text), len(reader.passages),
             len(reader.books), "/".join(reader.levels) or "milestone",
             (", %d with a second reference" % seconds) if seconds else ""))
    print(write(out, reader))


if __name__ == "__main__":
    main()
