#!/usr/bin/env python3
"""tei-index.py -- what a TEI corpus holds, read from its own declarations.

WHY AN INDEX.  A corpus of this kind is some thousands of directories, each
with a small XML file saying what is in it.  Reading them all takes a few
seconds -- tolerable once, absurd at every startup -- so they are read once
into a file the Emacs side can load in one go, exactly as the printed editions
are indexed.

WHAT IS READ.  Not the texts, and not their TEI headers: the `__cts__.xml'
beside them.  Each is a CTS declaration -- the canonical scheme these corpora
are published under -- and says what a thing is called and what editions of it
there are:

    <ti:work urn="urn:cts:greekLit:tlg0059.tlg030" xml:lang="grc">
      <ti:title xml:lang="eng">Republic</ti:title>
      <ti:edition urn="...perseus-grc2" xml:lang="grc">
        <ti:label xml:lang="grc">Politeia</ti:label>
        <ti:description>Platonis Opera Tomus IV ... Burnet ...</ti:description>
      </ti:edition>
      <ti:translation urn="...perseus-eng2" xml:lang="eng"> ... </ti:translation>
    </ti:work>

That is better than the header in every way: one small file to a work rather
than a text of two megabytes, and declarative rather than inferred.

THE NUMBERS ARE DIOGENES' OWN.  `tlg0059.tlg030' is author 0059, work 030 --
Plato's Republic, the same numbers the TLG files it under.  So a work here and
the same work in the TLG are one work as far as a citation is concerned, and a
note or a link made against one answers for the other.  Nothing has to be
translated; it was already the same.
"""

import glob
import io
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

CTS = "{http://chs.harvard.edu/xmlns/cts}"


# --------------------------------------------------------------- the corpora

CORPORA = [
    {
        "id": "perseus-greek",
        "name": "Perseus, Greek",
        "directory": "canonical-greekLit",
        "language": "greek",
    },
    {
        "id": "perseus-latin",
        "name": "Perseus, Latin",
        "directory": "canonical-latinLit",
        "language": "latin",
    },
    {
        "id": "first1k",
        "name": "First Thousand Years of Greek",
        "directory": "First1KGreek",
        "language": "greek",
    },
]
"""The corpora this knows how to read, and what to call them.

Each is a clone of its own, and the layout is the same in all three:
`data/AUTHOR/WORK/__cts__.xml' beside the texts.  A corpus not here is added
by naming its directory; nothing else about it need be said, the declarations
saying the rest."""


# ------------------------------------------------------------------- reading

def text_of(element):
    """ELEMENT's text, tidied, or None."""
    if element is None:
        return None
    said = "".join(element.itertext())
    said = " ".join(said.split())
    return said or None


def best_title(node, tag):
    """The most useful of NODE's TAG elements.

    ENGLISH FIRST where there is a choice.  A work carries its title more than
    once -- `Republic' in English and `Politeia' in Greek -- and a list of
    works is read by someone who knows the English name and is looking for it.
    The other is kept separately; neither is thrown away."""
    found = node.findall(CTS + tag)
    if not found:
        return None, None
    english = None
    other = None
    for element in found:
        lang = (element.get("{http://www.w3.org/XML/1998/namespace}lang")
                or element.get("lang") or "")
        said = text_of(element)
        if not said:
            continue
        if lang.startswith("en") and english is None:
            english = said
        elif other is None:
            other = said
    return english or other, (other if english else None)


def numbers_from(urn):
    """(AUTHOR, WORK) from a CTS urn, or (None, None).

    `urn:cts:greekLit:tlg0059.tlg030' is author 0059 and work 030 -- the
    digits only, because that is how Diogenes files them and how a citation
    made against one must find the other."""
    if not urn:
        return None, None
    tail = urn.split(":")[-1]
    parts = tail.split(".")
    digits = [re.sub(r"[^0-9]", "", part) for part in parts[:2]]
    author = digits[0] if digits and digits[0] else None
    work = digits[1] if len(digits) > 1 and digits[1] else None
    return author, work


def read_work(path):
    """One work's `__cts__.xml' as a dict, or None.

    The editions and translations are kept apart: a reader wanting the Greek
    and a reader wanting the English are asking different questions, and a
    list that mixed them would answer neither."""
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return None
    if not root.tag.endswith("work"):
        return None
    author, work = numbers_from(root.get("urn"))
    if not (author and work):
        return None
    title, also = best_title(root, "title")
    here = os.path.dirname(path)

    def versions(tag):
        out = []
        for element in root.findall(CTS + tag):
            urn = element.get("urn") or ""
            name = urn.split(":")[-1]
            # ABSOLUTE, so the index does not depend on where it was built
            # from.  Run with `.' for the directory it held `./canonical-...',
            # which resolves against whatever buffer a command runs in.
            file = os.path.abspath(os.path.join(here, name + ".xml"))
            if not os.path.exists(file):
                # DECLARED AND ABSENT.  The declarations outrun the texts --
                # a version named but not yet published -- and an index that
                # offered it would offer a file that is not there.
                continue
            label, _ = best_title(element, "label")
            out.append({
                "urn": urn,
                "language": (element.get(
                    "{http://www.w3.org/XML/1998/namespace}lang") or ""),
                "label": label,
                "description": text_of(element.find(CTS + "description")),
                "file": file,
            })
        return out

    editions = versions("edition")
    translations = versions("translation")
    if not (editions or translations):
        return None
    return {
        "author": author,
        "work": work,
        "title": title,
        "also": also,
        "editions": editions,
        "translations": translations,
    }


def read_author(path):
    """One author's `__cts__.xml' as (NUMBER, NAME), or (None, None)."""
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return None, None
    author, _ = numbers_from(root.get("urn"))
    name, _ = best_title(root, "groupname")
    return author, name


def read_corpus(root):
    """Every author and work under ROOT."""
    data = os.path.join(root, "data")
    if not os.path.isdir(data):
        data = root
    authors = {}
    for path in sorted(glob.glob(os.path.join(data, "*", "__cts__.xml"))):
        number, name = read_author(path)
        if number:
            authors[number] = {"name": name, "works": []}
    for path in sorted(glob.glob(os.path.join(data, "*", "*",
                                              "__cts__.xml"))):
        work = read_work(path)
        if not work:
            continue
        entry = authors.setdefault(work["author"],
                                  {"name": None, "works": []})
        entry["works"].append(work)
    # An author declared with no work that is actually there is no use.
    return dict((number, entry) for number, entry in authors.items()
                if entry["works"])


# ------------------------------------------------------------------- writing

def elisp(value):
    if value is None:
        return "nil"
    if isinstance(value, str):
        return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')
    return str(value)


def write_index(out, corpora):
    """CORPORA as a plist the Emacs side can read in one go."""
    with io.open(out, "w", encoding="utf-8") as handle:
        handle.write(";; What each TEI corpus holds, from its CTS files.\n")
        handle.write(";; Written by tei-index.py; do not edit by hand.\n")
        handle.write(";; The author and work numbers are Diogenes' own, so a\n")
        handle.write(";; citation made here answers in the TLG and back.\n")
        handle.write("(")
        for corpus in corpora:
            handle.write("(:id %s :name %s :language %s :directory %s\n"
                         " :authors\n (" % (elisp(corpus["id"]),
                                            elisp(corpus["name"]),
                                            elisp(corpus["language"]),
                                            elisp(corpus["directory"])))
            for number in sorted(corpus["authors"]):
                entry = corpus["authors"][number]
                handle.write("(%s %s\n  (" % (elisp(number),
                                              elisp(entry["name"])))
                for work in entry["works"]:
                    handle.write("(%s %s" % (elisp(work["work"]),
                                             elisp(work["title"])))
                    for kind in ("editions", "translations"):
                        handle.write(" (")
                        for version in work[kind]:
                            handle.write("(%s %s %s)"
                                         % (elisp(version["language"]),
                                            elisp(version["label"]),
                                            elisp(version["file"])))
                        handle.write(")")
                    handle.write(")")
                handle.write("))\n")
            handle.write("))\n")
        handle.write(")\n")
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    wanted = sys.argv[2:] or None
    found = []
    for corpus in CORPORA:
        if wanted and corpus["id"] not in wanted:
            continue
        where = os.path.join(root, corpus["directory"])
        if not os.path.isdir(where):
            print("   %-32s not here, passed over" % corpus["directory"])
            continue
        authors = read_corpus(where)
        works = sum(len(entry["works"]) for entry in authors.values())
        texts = sum(len(work["editions"]) + len(work["translations"])
                    for entry in authors.values() for work in entry["works"])
        print("   %-32s %4d authors, %5d works, %5d texts"
              % (corpus["name"], len(authors), works, texts))
        found.append(dict(corpus, authors=authors))
    if not found:
        sys.exit("No corpus found under %s. Clone one first." % root)
    out = write_index(os.path.join(root, "tei-index.eld"), found)
    print(out)


if __name__ == "__main__":
    main()
