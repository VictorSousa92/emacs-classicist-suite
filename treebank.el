;;; treebank.el --- annotating a Diorisis sentence -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa
;; Keywords: classics, philology, greek

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; ANNOTATING WHAT THE CORPUS FOUND.  A dependency tree over one
;; sentence, drawn here or in a viewer, written as ALDT or
;; CoNLL-U, and a workbook of the sentences collected on the way.
;;
;; IT REQUIRES `diorisis.el' and always will: it annotates
;; Diorisis sentences, calling `--select' six times, `--hit-at'
;; four and `--levels' three.  That is not incidental coupling,
;; it is what a treebank is.
;;
;; THE XML HERE IS ON THE WAY OUT.  No elisp in this repository
;; parses a corpus's XML -- the corpora are indexed by Python and
;; read as SQLite.  `xml' is for writing a tree as ALDT, `svg'
;; for drawing it, `color' for keeping its labels legible, and
;; `filenotify' for noticing when the viewer has saved.

;;; Code:

(require 'diorisis)

(require 'seq)

(require 'subr-x)

(require 'cl-lib)

(require 'transient)

(require 'xml)

(require 'svg)

(require 'color)

(require 'filenotify)

(require 'text-property-search)

;; THE SUITE FEATURE LIST, if this file is part of a suite at all.
;; Declared and not required, as in the two files beside it: absent the
;; suite the guard falls back to installing the keys, which is what this
;; did before the list existed.
(declare-function classicist-feature-p "classicist-groups" (feature))

(declare-function classicist--parse-word "classicist-morphology" (word lang))
;; AND THE BASE, WHERE THE SAME FUNCTION KEEPS ITS OLD NAME: the four-way
;; split of the base perseus renamed it, and a reader with the base and not
;; this suite still has the original.  This wants analyses as data rather
;; than any particular implementation, so it takes whichever is there.
(declare-function diogenes--parse-word "diogenes-perseus" (word lang))

(defgroup treebank nil
  "Annotating a Diorisis sentence as a dependency tree.

Its own group and not a child of diorisis, though this file requires that
one: a reader looking for the tree options should not have to know that the
corpus search is where they hang from."
  :group 'tools
  :prefix "treebank-")

(defcustom treebank-directory
  (expand-file-name "diorisis-treebank/" user-emacs-directory)
  "Where exported sentences are written."
  :type 'directory
  :group 'treebank)

(defun treebank--conllu-features (morph)
  "MORPH, the corpus's first analysis, as UD features.

THE FIRST ANALYSIS AND NOT ALL OF THEM.  CoNLL-U has one FEATS column and a
form may admit six analyses; the rest go into MISC, where an annotator can see
what was set aside rather than having it silently dropped."
  (let* ((first (car (split-string (or morph "") " *| *" t)))
         (found (delq nil
                      (mapcar (lambda (piece)
                                (cadr (assoc piece diorisis--features)))
                              (split-string first " " t)))))
    (if found (string-join found "|") "_")))

(defun treebank--conllu-sentence (author work sentence)
  "One sentence as CoNLL-U, as a string, or nil where there is nothing.

THE PUNCTUATION IS PUT BACK.  It is in a table of its own, and a tree without
its stops is not what anybody wants to annotate -- so the words and the marks
are read separately and interleaved by `node_index', which is what that column
was indexed for.

THE IDS ARE RENUMBERED, and the corpus's own kept in MISC.  CoNLL-U wants ids
from 1 with no gaps, and ours has gaps: a token the tagger could not lemmatise
is in no row of the index.  So the file is valid and `DiorisisWord=' says
where each token really stood, without which nothing could be sent back."
  (let* ((words (diorisis--select
                 "SELECT node_index, word_index, form, lemma, pos, morph,\
 confidence FROM occurrences\
 WHERE author_id = ? AND work_id = ? AND sentence = ?\
 ORDER BY node_index"
                 (list author work sentence)))
         (marks (and (diorisis--column-p "punctuation" "mark")
                     ;; As in `treebank--aldt-sentence': a null mark is
                     ;; not a token.
                     (seq-filter
                      (lambda (row)
                        (let ((mark (nth 1 row)))
                          (and mark (not (string-empty-p mark)))))
                      (diorisis--select
                       "SELECT node_index, mark FROM punctuation\
 WHERE author_id = ? AND work_id = ? AND sentence = ?\
 ORDER BY node_index"
                       (list author work sentence)))))
         (tokens (sort (append
                        (mapcar (lambda (row) (cons (or (nth 0 row) 0) row))
                                words)
                        (mapcar (lambda (row)
                                  (cons (or (nth 0 row) 0) (list nil nil)))
                                marks))
                       (lambda (a b) (< (car a) (car b)))))
         (named (car (diorisis--select
                      "SELECT author, work FROM texts\
 WHERE author_id = ? AND work_id = ?"
                      (list author work))))
         (place (car (diorisis--select
                      "SELECT location, words FROM sentences\
 WHERE author_id = ? AND work_id = ? AND sentence = ?"
                      (list author work sentence))))
         (mark-of (let ((table (make-hash-table)))
                    (dolist (row marks)
                      (puthash (nth 0 row) (nth 1 row) table))
                    table))
         (id 0)
         (lines nil))
    (when words
      (dolist (entry tokens)
        (setq id (1+ id))
        (let* ((node (car entry))
               (row (cdr entry))
               (mark (gethash node mark-of))
               (form (if mark (diorisis--greek mark)
                       (diorisis--greek (nth 2 row))))
               (lemma (if mark form (diorisis--greek (nth 3 row))))
               (pos (if mark "punctuation" (or (nth 4 row) "_")))
               (analyses (split-string (or (nth 5 row) "") " *| *" t)))
          (push (mapconcat
                 #'identity
                 (list (number-to-string id)
                       form
                       (if (string-empty-p lemma) "_" lemma)
                       (or (cdr (assoc pos diorisis--upos)) "X")
                       pos
                       (if mark "_"
                         (treebank--conllu-features (nth 5 row)))
                       "_"        ; HEAD, for the annotator
                       "_"        ; DEPREL, likewise
                       "_"        ; DEPS
                       (let ((misc nil))
                         (when node
                           (push (format "DiorisisNode=%s" node) misc))
                         (when (nth 1 row)
                           (push (format "DiorisisWord=%s" (nth 1 row)) misc))
                         (when (cdr analyses)
                           (push (format "Analyses=%s"
                                         (string-join (cdr analyses) ","))
                                 misc))
                         (when (nth 6 row)
                           (push (format "Confidence=%.2f" (nth 6 row)) misc))
                         (if misc (string-join (nreverse misc) "|") "_")))
                 "\t")
                lines)))
      (concat
       (format "# sent_id = %s-%s:%s\n" author work sentence)
       (format "# reference = %s, %s %s\n"
               (or (nth 0 named) author) (or (nth 1 named) work)
               (let ((levels (diorisis--levels (nth 0 place))))
                 (if levels (string-join levels ".") "?")))
       (format "# text = %s\n"
               (diorisis--greek (or (nth 1 place) "")))
       "# annotator = \n"
       (string-join (nreverse lines) "\n")
       "\n\n"))))

(defcustom treebank-format 'aldt
  "Which format an exported sentence is written in.

`aldt' is the Perseus treebank XML that Arethusa, the Arethusa widget and
`treebank-react' read, and is the one to choose to annotate Greek: its
`postag' is the nine-place tag those tools show and edit.

`conllu' is Universal Dependencies' format, for a UD tool or a parser.

`both' writes two files, there being no reason not to."
  :type '(choice (const :tag "Perseus treebank XML (Arethusa)" aldt)
                 (const :tag "CoNLL-U (Universal Dependencies)" conllu)
                 (const :tag "Both" both))
  :group 'treebank)

(defconst treebank--postag-places
  '((("noun" . "n") ("verb" . "v") ("adjective" . "a") ("adverb" . "d")
     ("adverbial" . "d") ("article" . "l") ("particle" . "g")
     ("expletive" . "g") ("conjunction" . "c") ("conj" . "c")
     ("preposition" . "r") ("prep" . "r") ("pronoun" . "p")
     ("interrog" . "p") ("numeral" . "m") ("interjection" . "i")
     ("exclam" . "e") ("exclamation" . "e") ("proper" . "n")
     ("geog_name" . "n") ("punctuation" . "u"))
    (("1st" . "1") ("2nd" . "2") ("3rd" . "3"))
    (("sg" . "s") ("pl" . "p") ("dual" . "d"))
    (("pres" . "p") ("imperf" . "i") ("perf" . "r") ("plup" . "l")
     ("futperf" . "t") ("fut" . "f") ("aor" . "a"))
    (("ind" . "i") ("subj" . "s") ("opt" . "o") ("inf" . "n")
     ("imperat" . "m") ("part" . "p"))
    (("act" . "a") ("mid" . "m") ("pass" . "p") ("mp" . "e"))
    (("masc" . "m") ("fem" . "f") ("neut" . "n"))
    (("nom" . "n") ("gen" . "g") ("dat" . "d") ("acc" . "a")
     ("voc" . "v"))
    (("comp" . "c") ("superl" . "s") ("irreg_comp" . "c")
     ("irreg_superl" . "s")))
  "The nine places of a GREEK postag, each as (DIORISIS-VALUE . LETTER).

IN ORDER: part of speech, person, number, tense, mood, voice, gender, case,
degree.  A place with nothing to put in it is a hyphen, which is why the tag
is always nine characters and why `n-s---mv-' is a noun, singular, masculine,
vocative and nothing else.

WHERE THE TWO TAGSETS DISAGREE, ours is the finer and the letter is the
coarser: Diorisis distinguishes a proper noun and a place name from a common
noun, and ALDT has one letter for all three.  Nothing is lost by it -- the
lemma says which -- but a tag read back will not restore the distinction.")

(defconst treebank--postag-places-latin
  '((("noun" . "n") ("verb" . "v") ("adjective" . "a") ("adverb" . "d")
     ("conjunction" . "c") ("conj" . "c") ("adposition" . "r")
     ("preposition" . "r") ("prep" . "r") ("pronoun" . "p")
     ("numeral" . "m") ("interjection" . "i") ("exclamation" . "e")
     ("exclam" . "e") ("punctuation" . "u"))
    (("1st" . "1") ("2nd" . "2") ("3rd" . "3"))
    (("sg" . "s") ("pl" . "p"))
    (("pres" . "p") ("imperf" . "i") ("perf" . "r") ("plup" . "l")
     ("futperf" . "t") ("fut" . "f"))
    (("ind" . "i") ("subj" . "s") ("inf" . "n") ("imperat" . "m")
     ("part" . "p") ("gerund" . "d") ("gerundive" . "g"))
    (("act" . "a") ("pass" . "p") ("dep" . "d") ("deponent" . "d"))
    (("masc" . "m") ("fem" . "f") ("neut" . "n"))
    (("nom" . "n") ("gen" . "g") ("dat" . "d") ("acc" . "a")
     ("voc" . "v") ("abl" . "b") ("loc" . "l"))
    (("pos" . "p") ("positive" . "p") ("comp" . "c") ("superl" . "s")))
  "The nine places of a LATIN postag, from the Latin Dependency Treebank.

NOT THE GREEK TABLE, AND THIS IS WHY IT IS ITS OWN.  The two schemes share
nine places and differ in five of them, and the differences are not
cosmetic: Latin has no dual, no middle voice and no optative; it HAS a
deponent voice, a gerund and a gerundive mood, and an ablative and a locative
case.  Using the Greek letters for Latin would write `d\=' for a dual where
the Latin scheme means a deponent, and produce a file another tool would read
as nonsense.

Taken from `TAGSET.txt\=' in the Latin Dependency Treebank 2.1, which is the
authority for it, as Celano\='s guidelines are for the Greek.

THE RELATIONS ARE THE SAME SET, the treebanks sharing the Prague scheme --
`diorisis-relations\=' serves both -- so only the morphology is here.")

(defun treebank--postag-places-for-language ()
  "The postag places of the language this tree is annotated by.
NAMED APART FROM `diorisis--places', which is a different thing: the
citations of a text buffer, set when the text is read.  A variable and a
function may share a name in elisp and these two did, being unrelated -- and
they belong in different files, which is where it showed."
  (if (eq diorisis-language 'latin)
      treebank--postag-places-latin
    treebank--postag-places))

(defconst treebank--latin-postag-places
  '((("noun" . "n") ("verb" . "v") ("participle" . "t") ("adjective" . "a")
     ("adverb" . "d") ("adverbial" . "d") ("conjunction" . "c")
     ("conj" . "c") ("adposition" . "r") ("preposition" . "r")
     ("prep" . "r") ("pronoun" . "p") ("numeral" . "m")
     ("interjection" . "i") ("exclamation" . "e") ("exclam" . "e")
     ("punctuation" . "u"))
    (("1st" . "1") ("2nd" . "2") ("3rd" . "3"))
    (("sg" . "s") ("pl" . "p"))
    (("pres" . "p") ("imperf" . "i") ("perf" . "r") ("plup" . "l")
     ("futperf" . "t") ("fut" . "f"))
    (("ind" . "i") ("subj" . "s") ("inf" . "n") ("imperat" . "m")
     ("part" . "p") ("gerund" . "d") ("gerundive" . "g")
     ("supine" . "u"))
    (("act" . "a") ("pass" . "p") ("dep" . "d") ("deponent" . "d"))
    (("masc" . "m") ("fem" . "f") ("neut" . "n"))
    (("nom" . "n") ("gen" . "g") ("dat" . "d") ("acc" . "a")
     ("abl" . "b") ("voc" . "v") ("loc" . "l"))
    (("pos" . "p") ("positive" . "p") ("comp" . "c") ("superl" . "s")))
  "The nine places of a LATIN postag: the Latin Dependency Treebank\='s.

NOT THE GREEK TABLE WITH A FEW WORDS CHANGED.  The two schemes differ in five
of the nine places, and a reader annotating Latin with the Greek table would
get wrong tags that look right:

  NUMBER has no dual.
  TENSE has no aorist.
  MOOD has a gerund, a gerundive and a supine, and no optative.
  VOICE has a DEPONENT and no middle -- and `d\=' is deponent in Latin where it
    is dual in Greek, the same letter in the same place meaning two different
    things, which is the trap.
  CASE has an ABLATIVE and a LOCATIVE, `b\=' and `l\='.
  DEGREE names the positive, which Greek leaves blank.

BOTH RELEASES ARE READ.  The LDT 1.5 documentation and the 2.1 tagset differ:
1.5 gives the participle a part of speech of its own (`t\=') and a supine mood
 (`u\='); 2.1 has neither, and adds a deponent voice (`d\=') and a positive degree
 (`p\='). No letter means two things across the two, so one table reads either --
which matters, the files in circulation being of both."
  )

(defun treebank-postag-places ()
  "The postag places for the language being annotated.

GREEK BY DEFAULT, because the corpus is Greek: everything that begins from a
Diorisis hit is Greek and cannot be otherwise.  Latin arrives the other way,
through `treebank-annotate-region\=' on a text in Diogenes\=' Latin corpora,
and a tree once made says which it is in its own `xml:lang\='."
  (if (eq diorisis-language 'latin)
      treebank--latin-postag-places
    treebank--postag-places))

(defun treebank--postag (pos morph)
  "POS and MORPH as an ALDT nine-place postag.

THE FIRST ANALYSIS, as with the CoNLL-U features: the tag has one place per
category and a form may admit six analyses.  The rest are kept in the
sentence's XML as a comment, so an annotator can see what was set aside."
  (let* ((first (car (split-string (or morph "") " *| *" t)))
         (values (cons (or pos "") (split-string (or first "") " " t))))
    (mapconcat
     (lambda (place)
       (or (cdr (seq-find (lambda (pair) (member (car pair) values)) place))
           "-"))
     (treebank--postag-places-for-language)
     "")))

(defun treebank--postag-words (postag)
  "The words POSTAG stands for, as a list.

READ OFF THE SAME TABLE THAT WRITES IT.  `treebank--postag-places\=' maps
each place\='s words to its letter, so this walks the places with the letters
and takes the first word that gave each -- the table being the one authority
for what a letter means, and a second table written out here being a thing to
fall out of step with it."
  (let ((places (treebank--postag-places-for-language))
        (words nil)
        (at 0))
    (dolist (place places)
      (let ((letter (and (< at (length postag)) (aref postag at))))
        (when (and letter (not (eq letter ?-)))
          (let ((found (seq-find (lambda (pair)
                                   (equal (cdr pair) (string letter)))
                                 place)))
            (when found (push (car found) words)))))
      (setq at (1+ at)))
    (nreverse words)))

(defun treebank--postag-said (postag)
  "POSTAG as `diorisis-postag-style\=' would have it shown."
  (let* ((postag (or postag ""))
         (said (string-join (treebank--postag-words postag) " ")))
    (pcase diorisis-postag-style
      ('code postag)
      ('both (if (string-empty-p said) postag
               (format "%s  %s" said postag)))
      (_ (if (string-empty-p said) postag said)))))

(defun treebank--cts-urn (author work)
  "AUTHOR and WORK as the CTS URN Perseids files carry.

    0545 001  ->  urn:cts:greekLit:tlg0545.tlg001

WHICH IS WORTH WRITING even though nothing here needs it: a file annotated in
Arethusa and deposited on Perseids is found by this, and a treebank whose
document_id is empty is a treebank of nowhere."
  (format "urn:cts:greekLit:tlg%s.tlg%s" author work))

(defun treebank--aldt-sentence (author work sentence number)
  "One sentence as an ALDT `<sentence>' element, NUMBER being its id.

`subdoc' CARRIES THE CITATION, which is where Arethusa and Perseids look for
it -- so `1.19.5' travels with the tree and the passage can be found again
from a file that has been round a web annotator and back."
  (let* ((words (diorisis--select
                 "SELECT node_index, word_index, form, lemma, pos, morph\
 FROM occurrences WHERE author_id = ? AND work_id = ? AND sentence = ?\
 ORDER BY node_index"
                 (list author work sentence)))
         (marks (and (diorisis--column-p "punctuation" "mark")
                     ;; A MARK THAT IS NOT THERE IS NOT A TOKEN.  The corpus
                     ;; has punct nodes with no `mark' attribute, so the
                     ;; indexer stored null -- and those arrived in the tree
                     ;; as a word with an empty form and a postag of `u',
                     ;; which is a token an annotator can neither read nor
                     ;; attach.  Dropped here rather than in the indexer: it
                     ;; is the exports that cannot use them, and the count is
                     ;; worth keeping in the database.
                     (seq-filter
                      (lambda (row)
                        (let ((mark (nth 1 row)))
                          (and mark (not (string-empty-p mark)))))
                      (diorisis--select
                       "SELECT node_index, mark FROM punctuation\
 WHERE author_id = ? AND work_id = ? AND sentence = ?\
 ORDER BY node_index"
                       (list author work sentence)))))
         (place (car (diorisis--select
                      "SELECT location FROM sentences\
 WHERE author_id = ? AND work_id = ? AND sentence = ?"
                      (list author work sentence))))
         (citation (let ((levels (diorisis--levels (nth 0 place))))
                     (if levels (string-join levels ".") "")))
         (tokens (sort (append
                        (mapcar (lambda (row) (cons (or (nth 0 row) 0) row))
                                words)
                        (mapcar (lambda (row)
                                  (cons (or (nth 0 row) 0)
                                        (list (nth 0 row) nil
                                              (nth 1 row) (nth 1 row)
                                              "punctuation" nil)))
                                marks))
                       (lambda (a b) (< (car a) (car b)))))
         (id 0)
         (lines nil))
    (when words
      (dolist (entry tokens)
        (setq id (1+ id))
        (let* ((row (cdr entry))
               (form (diorisis--greek (nth 2 row)))
               (lemma (diorisis--greek (nth 3 row)))
               (analyses (split-string (or (nth 5 row) "") " *| *" t)))
          (push (format
                 "    <word id=\"%d\" form=\"%s\" lemma=\"%s\" postag=\"%s\"\
 relation=\"\" head=\"\"%s/>"
                 id
                 (treebank--xml form)
                 (treebank--xml lemma)
                 (treebank--postag (nth 4 row) (nth 5 row))
                 ;; THE OTHER ANALYSES, IN AN ATTRIBUTE OF OUR OWN.  ALDT has
                 ;; nowhere for them and an annotator wants to see them: a
                 ;; namespace-less extra attribute is ignored by every tool
                 ;; that reads this and read by anyone who opens the file.
                 (if (cdr analyses)
                     (format " diorisis-analyses=\"%s\""
                             (treebank--xml
                              (string-join (cdr analyses) " | ")))
                   ""))
                lines)))
      (format "  <sentence id=\"%d\" document_id=\"%s\" subdoc=\"%s\" \
span=\"\">\n%s\n  </sentence>\n"
              number (treebank--cts-urn author work)
              (treebank--xml citation)
              (string-join (nreverse lines) "\n")))))

(defun treebank--xml (string)
  "STRING with the five XML characters escaped.
Greek needs none of it and an editor's bracket does: `<add>' in a fragmentary
text reaches the corpus as part of a form."
  (let ((out (or string "")))
    (dolist (pair '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;")
                    ("\"" . "&quot;") ("'" . "&apos;")))
      (setq out (replace-regexp-in-string (car pair) (cdr pair) out t t)))
    out))

(defun treebank--aldt-document (keys)
  "KEYS -- (AUTHOR WORK SENTENCE) each -- as one ALDT treebank document."
  (let ((number 0)
        (sentences nil))
    (dolist (key keys)
      (setq number (1+ number))
      (let ((text (apply #'treebank--aldt-sentence
                         (append key (list number)))))
        (if text (push text sentences) (setq number (1- number)))))
    (concat "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            ;; `grc\=' WITHOUT ASKING: this writes sentences of Diorisis, and
            ;; Diorisis is Greek.  The language is a question only for
            ;; `treebank-annotate-region\=', which may be given a Latin
            ;; text out of Diogenes.
            "<treebank xml:lang=\"grc\" format=\"aldt\" version=\"1.5\">\n"
            (string-join (nreverse sentences) "")
            "</treebank>\n")))

(defun treebank--write-treebank (keys name)
  "Write KEYS -- (AUTHOR WORK SENTENCE) each -- as NAME, and return the files.

ONE SENTENCE OR TWO HUNDRED go through here alike: a treebank of one sentence
and a treebank of a search differ in how the sentences were chosen and in
nothing else."
  (make-directory treebank-directory t)
  (let ((written nil))
    (when (memq treebank-format '(aldt both))
      (let ((file (expand-file-name (concat name ".xml")
                                    treebank-directory)))
        (with-temp-file file
          (insert (treebank--aldt-document keys)))
        (push file written)))
    (when (memq treebank-format '(conllu both))
      (let ((file (expand-file-name (concat name ".conllu")
                                    treebank-directory)))
        (with-temp-file file
          (dolist (key keys)
            (let ((text (apply #'treebank--conllu-sentence key)))
              (when text (insert text)))))
        (push file written)))
    (nreverse written)))

(defun treebank-export-sentence (&optional hit)
  "Write HIT's sentence out to be annotated.

The format is `treebank-format': ALDT XML for Arethusa and the
`treebank-react' viewer, CoNLL-U for a Universal Dependencies tool, or both."
  (interactive)
  (let* ((hit (or hit (diorisis--hit-at)))
         (files (treebank--write-treebank
                 (list (list (plist-get hit :author-id)
                             (plist-get hit :work-id)
                             (plist-get hit :sentence)))
                 (format "%s-%s-%s"
                         (plist-get hit :author-id)
                         (plist-get hit :work-id)
                         (plist-get hit :sentence)))))
    (unless files (user-error "Nothing to export here"))
    (message "Wrote %s" (string-join files ", "))
    (find-file-other-window (car files))))

(defun treebank-export-hits ()
  "Write every sentence of this buffer's hits to one CoNLL-U file.

A TREEBANK OF A QUESTION, which is what makes this worth having: the hits are
already a set chosen for a reason -- every perfect participle of `mu/w', or
every article followed by a genitive in Herodotus -- and annotating exactly
those is a study rather than a chore.  One sentence to a tree, in corpus order,
each carrying its citation."
  (interactive)
  (unless diorisis--spec (user-error "No search to export"))
  (let ((seen (make-hash-table :test #'equal))
        (sentences nil))
    (dolist (hit (diorisis-hits
                  (plist-put (copy-sequence diorisis--spec)
                             :limit (or (plist-get diorisis--spec :limit)
                                        diorisis-limit))))
      ;; ONE TREE TO A SENTENCE, however many hits fall in it: two occurrences
      ;; of the word in one sentence are one thing to annotate.
      (let ((key (list (plist-get hit :author-id)
                       (plist-get hit :work-id)
                       (plist-get hit :sentence))))
        (unless (gethash key seen)
          (puthash key t seen)
          (push key sentences))))
    (let* ((keys (nreverse sentences))
           (files (treebank--write-treebank
                   keys (format-time-string "hits-%Y%m%d-%H%M"))))
      (unless files (user-error "Nothing to export"))
      (message "Wrote %d sentences to %s" (length keys)
               (string-join files ", "))
      (find-file-other-window (car files)))))

(defvar treebank--graph-side nil
  "Where the drawing was last put, so that a redraw keeps its place.

NOT BUFFER-LOCAL.  The drawing lives in a buffer of its own and the tree in
another; either may ask for the redraw, and both mean the same window.")

(defvar-local treebank--tree nil
  "The tokens of the sentence being annotated, as a list of plists.")

(defvar-local treebank--tree-file nil
  "The ALDT file this buffer was read from and is written back to.")

(defvar-local treebank--tree-sentence nil
  "The sentence's own attributes: id, document_id, subdoc, span.")

(defcustom treebank-guidelines-url
  "https://github.com/PerseusDL/treebank_data/blob/master/AGDT2/guidelines/Greek_guidelines.md"
  "Where the annotation guidelines are.

`G\\=' in the help buffer opens them.  Celano\\='s guidelines for the Ancient Greek
Dependency Treebank 2.0: the authority for everything the help says, and
fuller than it by two hundred pages."
  :type 'string
  :group 'treebank)

(defconst treebank-relation-notes
  '(("PRED"
     . "The verb of the MAIN clause, and there is one to a sentence (3.1).
Every other verb, finite or not, takes the label of the function it has
towards the word it hangs from -- which is what makes a subordinate clause's
verb an OBJ or an ADV rather than a second PRED.  Its own head is 0.")
    ("SBJ"
     . "Every subject (3.2): a noun or its equivalent in the nominative; a
genitive in the genitive absolute; an accusative in an infinitive clause; an
articular or verbal infinitive; and a SUBSTANTIVE CLAUSE that is the subject,
in which case the label goes on the clause's verb.")
    ("OBJ"
     . "An ARGUMENT of a verb, adjective or adverb (3.3) -- a constituent
that this verb or class of verbs selects.  `I went TO ROME' is an argument;
`I ate apples YESTERDAY' is not, and is ADV, because a time can modify any
verb at all.

An object CLAUSE takes OBJ on its verb, under the conjunction: see `H'.")
    ("ATR"
     . "Any dependent of a noun (3.4): the article -- which is ALWAYS ATR
 at (2.1) -- an adjective, another noun, a prepositional phrase, or a RELATIVE
CLAUSE, whose verb takes ATR.  A substantivised relative clause instead takes
the label a noun would.")
    ("ADV"
     . "An OPTIONAL modification of a verb, adjective or adverb (3.5), as
against an argument, which is OBJ.  Adverb clauses take ADV on their verb;
so do the circumstantial participle and the infinitive of purpose or result.")
    ("ATV"
     . "An ADJECTIVE OR PARTICIPLE agreeing with the subject but working as an
adjunct.  The guidelines say AGDT 2.0 annotates these as ADV on the governing
verb, ATV and AtvV being the older style of AGDT 1.0, allowed but to be
declared (3.6).

THE DATA SAYS OTHERWISE: ATV appears 3,428 times in the released AGDT 2.1 and
AtvV 1,809, so the older style is very much alive.  Either way it is for a
word agreeing with the subject -- never for the finite verb of a clause,
which takes the function the clause has.")
    ("ATVV" . "See ATV.")
    ("PNOM"
     . "A predicate noun or adjective depending on a COPULA (3.7) -- what
`to be' joins to its subject.  The supplementary participle not in indirect
discourse takes PNOM too.")
    ("OCOMP"
     . "The predicative accusative and any predicative complement NOT
agreeing with the subject (3.8): what the object is called or made.  Also the
supplementary participle with verbs of perceiving and finding.")
    ("COORD"
     . "The coordinating conjunction itself (3.9), which HEADS the
coordination: the things joined hang beneath it, each with its own function
and the suffix _CO.

With correlatives -- `me/n ... de/', `kai\\=' ... kai\\=' -- the LAST one takes
COORD and the earlier ones take AuxY and hang from that last one.  Where
there is no conjunction at all, the COMMA takes COORD.")
    ("APOS"
     . "The appositive, hanging from the noun it stands for (3.10).  That is
the default style.  The older style puts APOS on the COMMA between them and
gives the noun and the appositive their own functions with _AP -- and must be
declared if used.")
    ("AuxP"
     . "A preposition (3.12), and it HEADS its phrase: the noun hangs beneath
the preposition, carrying the function the phrase has.  A preposition is
always AuxP and never anything else.")
    ("AuxC"
     . "A SUBORDINATING conjunction (3.13), and it HEADS its clause: the
clause's verb hangs beneath it and carries the function -- OBJ for an object
clause, ADV for an adverb clause, SBJ for a subject clause.  The conjunction
itself hangs from the word the clause belongs to.

This is the thing most easily got wrong; `H' draws it.")
    ("AuxX"
     . "A comma (3.14) -- unless it is coordinating with no conjunction
present, when it is COORD.  A plain comma hangs from the word BEFORE it.  Two
commas round a vocative or a parenthesis both hang from the vocative, or from
the head of the parenthesis.")
    ("AuxG"
     . "Punctuation other than commas and the final stop (3.15): inverted
commas for direct speech, brackets, and the rest.")
    ("AuxK"
     . "The mark that ENDS the sentence -- full stop, semicolon, or the point
above the line (3.16).  Its head is always 0, the root: it hangs from nothing
in the sentence.")
    ("AuxY"
     . "A technical node (3.17): the earlier members of a correlative pair,
hanging from the last; and sentence adverbs -- the particles of SG 1094 --
but only those whose scope is the whole sentence.")
    ("AuxZ"
     . "An adverb that is a logical operator (3.18): `not', `even', `also'.
It hangs from the word it bears on.")
    ("ExD"
     . "A constituent that does not belong to the sentence syntactically
 at (3.19): a vocative, the head of a parenthesis, an interjection (2.10).  It
hangs from the PRED.")
    ("MWE"
     . "A multi-word expression (3.11) whose words cannot be given functions
of their own: the head takes the function of the whole and the rest hang from
it as MWE.")
    ("UNDEFINED" . "Not decided yet.  Not a label to leave in a finished tree."))
  "What each relation is for, at more length, with the guidelines' sections.

SHOWN BY `e\\=' IN THE EDITOR, on the relation at point or on one asked for.  The
short glosses in `diorisis-relations\\=' are for choosing quickly; these are
for the cases where one has to think, and they are the cases that come up: a
clause, a conjunction, a comma.")

(defconst treebank-annotation-help-text
  "HOW A TREE IS SHAPED

Counts in this page are from the released AGDT 2.1 -- 33 texts, some 570,000
words -- because the guidelines and the data do not always agree, and where
they differ it is worth knowing which way.

At the root, head 0, stands ONE OF TWO THINGS:

  the sentence's verb, PRED                       18,137 sentences
  a coordinating conjunction, COORD               15,311 sentences

A sentence joined to the one before it -- by `de/', `kai/', `a)lla/' -- has
the CONJUNCTION at the root and the verb beneath it as PRED_CO.  `de/' is at
the root 10,853 times in the treebank, labelled COORD.  So a tree whose top
is `de/' is not a mistake; a tree whose top is `de/' labelled AuxY is.

  le/gei   (PRED, head 0)          de/        (COORD, head 0)
    \u2514\u2500 o( pai=s   (SBJ)            \u2514\u2500 le/gei   (PRED_CO)
    \u2514\u2500 .          (AuxK)                \u2514\u2500 o( pai=s (SBJ)

`de/' takes AuxY instead -- 8,695 times -- when it is a particle within the
sentence rather than the thing joining it to the last: then it hangs from the
PRED.  Either is attested; COORD at the root is the commoner.

THE FINAL STOP hangs from 0 as well, AuxK: 33,421 of 33,511 of them.

THE FUNCTION WORDS HEAD WHAT THEY INTRODUCE

This is the convention that surprises everyone, and the whole of what is hard
about conjunctions and clauses.  A preposition is not a satellite of its noun:
it stands ABOVE it.  A subordinating conjunction stands above its whole
clause.  The word beneath then carries the function.

  in the city:                    that he is coming:

  e)n       (AuxP)                o(/ti       (AuxC)
    \u2514\u2500 po/lei  (ADV or OBJ)     \u2514\u2500 e)/rxetai  (OBJ)

The preposition hangs where the phrase belongs; the noun beneath it takes the
function the phrase has.  The conjunction hangs where the clause belongs; the
verb beneath it takes the function the clause has.

AN OBJECT CLAUSE

  `he says that the boy is coming'

  le/gei          (PRED, head 0)
    \u2514\u2500 o(/ti         (AuxC)        -- the conjunction, under the verb
         \u2514\u2500 e)/rxetai  (OBJ)      -- the clause's verb, under o(/ti
              \u2514\u2500 pai=s  (SBJ)      -- and its own subject under it

The clause is the object of `le/gei', so OBJ goes on `e)/rxetai' -- on the
VERB of the clause, not on the conjunction.  A subject clause is the same with
SBJ; a purpose or result or time clause the same with ADV; a relative clause
the same with ATR, and the relative pronoun takes its own function inside the
clause.

RELATIVE WORDS ARE THE EXCEPTION, AND IT CATCHES EVERYONE

A relative pronoun or adverb does NOT head its clause.  It stands inside it,
with its own function, and the clause's verb carries the clause's function:

  o(/qen parece/bhmen                `whence we digressed'

  parece/bhmen  (ADV -- the clause's function, under the main verb)
    \u2514\u2500 o(/qen     (ADV -- its own function, inside the clause)

Guidelines 3.13: AuxC is for subordinating conjunctions ONLY, `excluding the
local ones, which have to be treated as relative pronouns/adverbs'.  So
`o(=', `o(/pou', `o(/qen', `oi(=', `h(=|' are relative adverbs -- Smyth 2498 --
and `o(/qen' is simply `e)c ou(=' in one word (Smyth 2499).  They behave like
`o(/s', not like `o(/ti'.

AND THE DATA AGREES.  Of 64 occurrences of `o(/qen' in the treebank: ADV 40,
OBJ 12, AuxY 8, and AuxC once.  Its head is a verb, and that verb carries
ATR 14, PRED 10, ADV 8, OBJ 6 -- the clause's function.  `e)/nqa' the same,
615 times: ADV 473, OBJ 29, AuxC 5.

Put another way: `o(/ti' and `o(/te' head their clauses; `o(/qen' and `o(/s'
sit in theirs.

  `when he came, he spoke'        `the man who came'

  ei)=pen      (PRED)             a)/nqrwpos    (SBJ or wherever)
    \u2514\u2500 o(/te    (AuxC)          \u2514\u2500 h(=lqen   (ATR)
         \u2514\u2500 h(=lqen (ADV)            \u2514\u2500 o(/s   (SBJ)

WHAT HANGS UNDER A PREPOSITION

The preposition is AuxP and carries no function of its own.  THE WORD BENEATH
IT CARRIES THE FUNCTION OF THE WHOLE PHRASE towards whatever the preposition
hangs from -- which is why the same construction takes different labels in
one sentence:

  e)n Lukei/w| katalipw/n diatriba/s     `the discussions in the Lyceum'
  diatri/beis peri\\ th\\n stoa/n         `you spend your time by the portico'

  diatriba/s   (OBJ)                  diatri/beis  (PRED)
    \u2514\u2500 e)n      (AuxP)               \u2514\u2500 peri/     (AuxP)
         \u2514\u2500 Lukei/w| (ATR)                 \u2514\u2500 stoa/n (ADV)

The first phrase modifies a NOUN, so it is attributive: ATR.  The second
modifies a VERB, so it is adverbial: ADV.  In the treebank, of the phrases
hanging from a noun 1,430 of 1,616 take ATR; of those hanging from a verb,
11,600 take ADV and 7,964 take OBJ.

AND THE OBJ IS THE OTHER HALF OF IT.  A phrase a verb SELECTS is an argument:

  kate/bhn ei)s Peiraia=  meta\\ Glau/kwnos

  kate/bhn       (PRED)
    \u251c\u2500 ei)s        (AuxP)
    \u2502    \u2514\u2500 Peiraia= (OBJ)   -- a verb of motion wants a direction
    \u2514\u2500 meta/       (AuxP)
         \u2514\u2500 Glau/kwnos (ADV) -- company, which any verb may have

`ei)s\=' with a verb of motion is OBJ almost without exception: e)/rxomai 141
against 3, a)fikne/omai 77 against 2, bai/nw 58 against 1.  `meta/\=' of
accompaniment is ADV, nothing having selected it.

COORDINATION

The conjunction heads it, and each thing joined takes its own function with
_CO after it.

  `the boy and the girl came'

  h(=lqon         (PRED)
    \u2514\u2500 kai/         (COORD)
         \u2514\u2500 pai=s   (SBJ_CO)
         \u2514\u2500 ko/rh   (SBJ_CO)

With `me/n ... de/' or `kai\u2026 kai/', the LAST conjunction takes COORD and the
earlier ones AuxY, hanging from that last one.  With no conjunction at all --
asyndeton -- the comma takes COORD and the members hang from it.

PUNCTUATION

  the final stop      AuxK, head 0
  a plain comma       AuxX, hanging from the word before it
  a coordinating comma  COORD, with the members beneath
  anything else       AuxG

PARTICLES, NEGATIVES, VOCATIVES

  a sentence particle   AuxY, if its scope is the whole sentence
  `ou)', `kai/' `also'  AuxZ, hanging from the word it bears on
  a vocative            ExD, hanging from the PRED
  an interjection       ExD

ARGUMENT OR MODIFICATION

OBJ is an argument -- what this verb selects and another could not take.
ADV is an optional modification, which almost any verb could take.

  `I went TO ROME'      OBJ: a verb of motion requires a direction
  `I ate apples TODAY'  ADV: any verb at all can happen today

WHAT NEARLY ALWAYS TAKES ONE LABEL

  the article            ATR, 27,496 times -- but `o(' is also a PRONOUN
                         (guidelines 2.1), and then it takes a noun's label:
                         SBJ 623, OBJ 385, ADV 259
  a preposition          AuxP, 25,588 times; AuxZ 1,576, where the word is
                         doing something else
  an interjection        ExD

THE CONJUNCTIONS, AS THE DATA HAS THEM

  ei)         AuxC 1,630      o(/te   AuxC 409, ADV 163
  e)pei/      AuxC 1,101      i(/na   AuxC 274, ADV 37
  o(/ti       AuxC 613        o(/pws  AuxC 270

And what hangs beneath an AuxC, when it is a verb: ADV 2,771, OBJ 365,
ATR 50, SBJ 35 -- the clause's own function, on the clause's verb, which is
the rule this page began with.

PARTICIPLES AND INFINITIVES

  attributive participle     ATR
  circumstantial participle  ADV
  supplementary participle   OBJ, PNOM or OCOMP
  articular infinitive       whatever a noun would take
  verbal infinitive          SBJ or OBJ; ADV for purpose or result

THE SUFFIXES

  _CO   on every member of a coordination
  _AP   only in the older apposition style, and must be declared

Sections in brackets are Celano's guidelines for the AGDT 2.0; `G' opens
them.  Where this page is too short to be exact, they are the authority."
  "A page on how to annotate, shown by `H\\=' in the tree editor.

WRITTEN AROUND THE THING THAT IS ACTUALLY HARD.  A list of labels does not
tell a reader where to put `o(/ti\\=', and where to put it is a convention and
not a fact about Greek: the conjunction heads its clause and the verb beneath
takes the function.  So the page draws that, three times, and then says what
is always one label and what the suffixes are for.")

(defun treebank-annotation-help ()
  "Show how to annotate, in a buffer beside the tree."
  (interactive)
  (let ((buffer (get-buffer-create "*How to annotate*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert treebank-annotation-help-text)
        (insert "\n")
        (goto-char (point-min)))
      (special-mode)
      (setq-local truncate-lines nil)
      (use-local-map (let ((map (make-sparse-keymap)))
                       (set-keymap-parent map special-mode-map)
                       (keymap-set map "G" #'treebank-open-guidelines)
                       (keymap-set map "q" #'quit-window)
                       map)))
    (display-buffer buffer)))

(defun treebank-open-guidelines ()
  "Open the AGDT guidelines in a browser."
  (interactive)
  (browse-url treebank-guidelines-url))

(defun treebank-explain-relation (relation)
  "Say at length what RELATION is for.

Interactively, the relation of the token at point where it has one, and asked
for otherwise -- so `e\\=' on a word one has just labelled says whether the
label was the right one."
  (interactive
   (list (let* ((here (ignore-errors (treebank--tree-at)))
                (mine (and here (plist-get here :relation))))
           (if (and mine (not (string-empty-p mine)))
               mine
             (completing-read "Explain which relation? "
                              (mapcar #'car diorisis-relations) nil nil)))))
  (let* ((bare (replace-regexp-in-string "_\\(CO\\|AP\\)\\'" "" relation))
         (note (cdr (assoc bare treebank-relation-notes)))
         (gloss (cdr (assoc bare diorisis-relations)))
         (buffer (get-buffer-create "*The relation*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "%s\n" relation) 'face 'bold))
        (when gloss (insert (format "%s\n\n" gloss)))
        (insert (or note "Nothing written down about this one.\n"))
        (when (string-suffix-p "_CO" relation)
          (insert "\n\n_CO: a member of a coordination -- see COORD."))
        (when (string-suffix-p "_AP" relation)
          (insert "\n\n_AP: the older apposition style, which must be \
declared -- see APOS."))
        (insert "\n")
        (goto-char (point-min)))
      (special-mode)
      (setq-local truncate-lines nil))
    (display-buffer buffer)))

(defcustom treebank-tree-columns '(24 18 12)
  "How wide the form, lemma and postag columns are.

Wide enough for what the corpus holds: a Greek form runs to twenty characters
in the compounds, a lemma is shorter, and a postag is nine and fixed.  The
head and the relation follow, and are what a reader is here to change."
  :type '(repeat integer)
  :group 'treebank)

(defcustom treebank-tree-diagram t
  "Whether the tree is drawn under the table of tokens.

An indented tree, in box-drawing characters -- a picture that costs nothing
and cannot break: no image support, no SVG, no font of librsvg's choosing, and
every word in it is real buffer text, so point can be on one and `C-c C-c'
will look it up.

`treebank-tree-widget' is the other way of seeing a tree, and draws it as
the printed diagrams do."
  :type 'boolean
  :group 'treebank)

(defcustom treebank-viewer
  "http://localhost:8087/?doc=%n&chunk=1"
  "Where a tree is opened to be drawn properly, as a URL with %n in it.

THIS NOW HAS A DEFAULT, because the package serves the viewer itself: the
port is `treebank-viewer-port\=', the page is the one in `tools/viewer\=',
and `w\=' starts the server before it asks for the page.  A reader who has
installed Arethusa\='s files there -- see that directory\='s README -- need set
nothing at all.

The %s is filled with the file's own URL.  A deployment of the Arethusa
widget or of `treebank-react' takes the URL of a treebank and a sentence
number, so something of this shape:

    \"http://localhost:8080/?doc=%s&chunk=1\"

Nil opens the file itself, which a browser shows as XML -- correct, and not a
diagram.  There is no default because there is no viewer to default to: both
of those are JavaScript that has to be served from somewhere, and where that
somewhere is, is yours to say."
  :type '(choice (const :tag "The file itself" nil) string)
  :group 'treebank)

(defconst treebank-viewers
  '(("The viewer this package serves, on its own port"
     . "http://localhost:8087/?doc=%n&chunk=1")
    ("The same viewer on the usual port, served by hand"
     . "http://localhost:8080/?doc=%n&chunk=1")
    ("A local Arethusa, reading a file URL"
     . "http://localhost:8080/app/#/staging?doc=%f&chunk=1")
    ("Perseids' own Arethusa (wants a Perseids id, not a file)"
     . "https://www.perseids.org/tools/arethusa/app/#/perseids?doc=%s&chunk=1"))
  "Viewers a tree can be opened in, as (NAME . URL-TEMPLATE).

OFFERED BY `treebank-tree-widget\=' with a prefix argument, and one of them
may be set as `treebank-viewer\='.  The first two want a viewer
served from somewhere -- `treebank-react\=' and the Arethusa widget are
JavaScript and have to be -- and a file:// URL reaches them only if the
browser and the server allow it; a tree copied into the server\='s own
directory always does.

THE PUBLIC PERSEIDS ARETHUSA IS DIFFERENT and is here to be told apart: its
`doc\=' is a Perseids document number, not a URL, so a local file cannot be
handed to it.  A tree has to be deposited on Perseids first, and then the
number is what one opens.")

(defcustom treebank-tree-widget-in-emacs 'auto
  "Whether a treebank viewer opens inside Emacs, in an xwidget.

`auto\=' -- the default -- opens it here where this Emacs was built with
xwidgets and in the browser where it was not.  That is the right default now
that there is something worth seeing in the window: the viewer draws the tree
beside the table and both are in one frame, which is what an embedded viewer
is FOR, and a reader whose build has no xwidgets loses nothing by being sent
to the browser instead.

t forces it here and complains where the build cannot; nil always uses the
browser, which is the answer for a reader who would rather keep the tab open
beside Emacs, or who has met xwidget\='s way of taking a whole session down
with it and would rather not again."
  :type '(choice (const :tag "Here if this Emacs can, else the browser" auto)
                 (const :tag "Always here" t)
                 (const :tag "Always the browser" nil))
  :group 'treebank)

(defcustom treebank-tree-graph-side 'ask
  "Where the drawn tree appears beside the table.

`right\=' and `left\=' put it in a side window down the edge of the frame, which
suits a shallow tree of many words; `above\=' and `below\=' put it across the
width, which suits a deep one.  `other\=' leaves it to `display-buffer\=' and
whatever rules a reader has of their own.

`ask\=' asks, once per `D\=', which is the default -- the right answer depends on
the sentence, and a reader who wants one answer for ever sets it here and is
not asked again.  A prefix argument to `D\=' asks whatever this says."
  :type '(choice (const :tag "Ask each time" ask)
                 (const :tag "To the right" right)
                 (const :tag "To the left" left)
                 (const :tag "Above" above)
                 (const :tag "Below" below)
                 (const :tag "Wherever display-buffer puts it" other))
  :group 'treebank)

(defcustom treebank-tree-graph-size 0.45
  "How much of the frame the drawn tree takes, as a fraction.

Its width where it is to the left or the right, its height where it is above
or below."
  :type 'number
  :group 'treebank)

(defun treebank--graph-action (side)
  "The `display-buffer\=' action for showing the drawing at SIDE.

A SIDE WINDOW, so that it does not take the place of the table: a side window
is not chosen by `other-window\=' for ordinary display, so the buffers that
come and go while annotating -- a lookup, a relation explained -- appear
elsewhere and leave the drawing where it is."
  (pcase side
    ((or 'right 'left)
     `((display-buffer-in-side-window)
       (side . ,side) (slot . 0)
       (window-width . ,treebank-tree-graph-size)))
    ((or 'above 'below)
     `((display-buffer-in-side-window)
       (side . ,(if (eq side 'above) 'top 'bottom)) (slot . 0)
       (window-height . ,treebank-tree-graph-size)))
    (_ nil)))

(defun treebank--read-graph-side ()
  "Where to put the drawing: asked, or as configured."
  (let ((sides '(("to the right" . right) ("to the left" . left)
                 ("below" . below) ("above" . above)
                 ("wherever it likes" . other))))
    (cdr (assoc (completing-read "Draw it: " sides nil t) sides))))

(defun treebank--tree-children (words)
  "A hash from a token's id to the tokens that depend on it."
  (let ((children (make-hash-table :test #'equal)))
    (dolist (word words)
      (let ((head (plist-get word :head)))
        (unless (or (null head) (string-empty-p head))
          (puthash head (append (gethash head children) (list word))
                   children))))
    children))

(defun treebank--tree-draw (words)
  "WORDS as an indented tree, as a string.

DRAWN DOWNWARDS AND NOT ACROSS.  A hanging diagram of the printed sort wants
a canvas and a font it cannot have here; an indented tree says the same thing
-- what depends on what, and in what relation -- in characters, updates with
the table, and keeps every word as text one can put point on.

A CYCLE IS DRAWN ONCE AND STOPPED.  The validation reports it; this must not
hang on it, so a token already drawn is not descended into again.

Tokens with no head yet are listed at the foot, a tree being annotated being
mostly those to begin with: they are the work remaining."
  (let* ((children (treebank--tree-children words))
         (seen (make-hash-table :test #'equal))
         (lines nil))
    (cl-labels
        ((draw (word depth)
           (unless (gethash (plist-get word :id) seen)
             (puthash (plist-get word :id) t seen)
             (push (format "%s%s %s%s"
                           (make-string (* 2 depth) ?\s)
                           (if (= depth 0) "\u2514\u2500" "\u251c\u2500")
                           (plist-get word :form)
                           (let ((relation (plist-get word :relation)))
                             (if (string-empty-p (or relation ""))
                                 (propertize "  (?)" 'face 'shadow)
                               (propertize (format "  (%s)" relation)
                                           'face 'diorisis-form-face))))
                   lines)
             (dolist (child (gethash (plist-get word :id) children))
               (draw child (1+ depth))))))
      (dolist (word words)
        (when (equal (plist-get word :head) "0")
          (draw word 0)))
      (let ((loose (seq-filter
                    (lambda (word)
                      (and (not (gethash (plist-get word :id) seen))
                           (let ((head (plist-get word :head)))
                             (or (null head) (string-empty-p head)))))
                    words)))
        (when loose
          (push (propertize "  not attached yet:" 'face 'shadow) lines)
          (dolist (word loose)
            (push (format "    %s" (plist-get word :form)) lines))))
      ;; A token whose head is real but which the walk never reached is in a
      ;; cycle, or hangs off one: said plainly rather than left out of the
      ;; picture, which would make the picture a lie.
      (let ((unreached (seq-filter
                        (lambda (word)
                          (and (not (gethash (plist-get word :id) seen))
                               (let ((head (plist-get word :head)))
                                 (and head (not (string-empty-p head))))))
                        words)))
        (when unreached
          (push (propertize "  not reachable from the root:" 'face 'error)
                lines)
          (dolist (word unreached)
            (push (format "    %s -> %s" (plist-get word :form)
                          (plist-get word :head))
                  lines)))))
    (string-join (nreverse lines) "\n")))

(defcustom treebank-svg-greek-font nil
  "One font family to set the drawn tree's Greek in, or nil to work it out.

A STRING FORCES IT, and is for the case where the choosing below picks wrong.
Nil is the ordinary answer: see `treebank--svg-greek-family', which
prefers the font this Emacs itself uses for Greek and falls back on the fonts
made for polytonic."
  :type '(choice (const :tag "Work it out" nil) string)
  :group 'treebank)

(defcustom treebank-svg-greek-fonts
  '("New Athena Unicode" "Brill" "GFS Porson")
  "The Greek families to fall back on, in order of preference.

AFTER THE READER'S OWN.  A font set for Greek in an Emacs configuration is a
considered choice and is preferred to anything here; these are for a reader
who has not made one, and are in the order they were asked for: New Athena
Unicode, then Brill, then GFS Porson.

ALL OF THEM ARE OFFERED AT ONCE, not tried one at a time: SVG takes a list of
families and fontconfig uses the first it has, which is the same question
answered by the thing that actually knows which fonts are installed.  Adding
to this list costs nothing."
  :type '(repeat string)
  :group 'treebank)

(defun treebank--emacs-greek-family ()
  "The family this Emacs uses for Greek, or nil.

ASKED OF A GREEK CHARACTER and not of the default face: a configuration that
sets a Greek font does it through the fontset, so the default face's own
family is the Latin one and says nothing about the Greek.  `face-font' with a
character asks the question that was actually configured.

Nil on a terminal, and nil where the answer cannot be parsed -- in which case
the fallbacks stand, which is no worse than not having asked."
  (when (and (display-multi-font-p) (fboundp 'font-spec))
    (ignore-errors
      (let* ((font (face-font 'default nil ?\N{GREEK SMALL LETTER ALPHA}))
             (family (and font (font-get (font-spec :name font) :family))))
        (and family (format "%s" family))))))

(defun treebank--svg-greek-family ()
  "The font-family the drawn tree sets Greek in.

A LIST, QUOTED, IN ORDER OF PREFERENCE: whatever this Emacs uses for Greek,
then `treebank-svg-greek-fonts', then a generic serif so that something is
always named.  `treebank-svg-greek-font' overrides the lot."
  (if treebank-svg-greek-font
      (format "'%s'" treebank-svg-greek-font)
    (let ((families (delete-dups
                     (delq nil (append (list (treebank--emacs-greek-family))
                                       (copy-sequence
                                        treebank-svg-greek-fonts)
                                       (list "serif"))))))
      (mapconcat (lambda (family) (format "'%s'" family)) families ", "))))

(defcustom treebank-svg-label-font "sans-serif"
  "The font family the drawn tree sets the relations in.

A SECOND FAMILY, because the first has no Latin.  The Greek fonts made for
classicists -- GFS Porson and its relations -- carry Greek and little else,
and `PRED\\=' set in one of them is a row of boxes or a row of Greek letters
that happen to share the shapes."
  :type 'string
  :group 'treebank)

(defcustom treebank-svg-metrics '(120 90 20 13)
  "The drawing's measurements: column, row, Greek size, label size."
  :type '(list (integer :tag "Column width")
               (integer :tag "Row height")
               (integer :tag "Greek size")
               (integer :tag "Label size"))
  :group 'treebank)

(defcustom treebank-svg-contrast 3.5
  "How far a word's colour must stand out from the background to be left alone.

The ratio WCAG defines: 1 is the same colour, 21 is black on white, 4.5 is
what that standard asks of body text and 3 of large text.  A colour below
this is moved towards white on a dark background, or black on a light one,
until it reaches it.

WHY AT ALL, when the palettes below are chosen for a dark background and a
light one: because a palette knows only which of the two it is on, and a
reader's background may be a mid grey, a deep blue, or a parchment.  This is
what makes the drawing legible on a background nobody anticipated.

Nil, or a number below 1, uses every colour exactly as it is given."
  :type '(choice (const :tag "Leave the colours alone" nil) number)
  :group 'treebank)

(defun treebank--luminance (colour)
  "COLOUR's relative luminance, as WCAG computes it, or nil.

THE SRGB CURVE AND NOT THE PLAIN MEAN.  The eye is far more sensitive to green
than to blue, and a mean of the three channels calls a saturated blue as
bright as a mid grey -- which on a black background is the difference between
a word one can read and a word one cannot."
  (let ((rgb (color-name-to-rgb colour)))
    (when rgb
      (apply #'+
             (seq-mapn (lambda (channel weight)
                         (* weight
                            (if (<= channel 0.03928)
                                (/ channel 12.92)
                              (expt (/ (+ channel 0.055) 1.055) 2.4))))
                       rgb '(0.2126 0.7152 0.0722))))))

(defun treebank--contrast (one other)
  "The contrast ratio between ONE and OTHER, or nil."
  (let ((a (treebank--luminance one))
        (b (treebank--luminance other)))
    (when (and a b)
      (/ (+ (max a b) 0.05) (+ (min a b) 0.05)))))

(defun treebank--legible (colour background)
  "COLOUR, moved towards white or black until it reads on BACKGROUND.

TOWARDS WHICHEVER THE BACKGROUND IS NOT, and THE HUE IS KEPT: a dark blue for
the adjectives becomes a lighter blue and not a grey, so the parts of speech
stay told apart by the thing that told them apart.

Twenty steps at most, each a twentieth of the way -- enough to reach any ratio
worth asking for, and bounded, so that a colour which cannot reach it comes
back as near as it got instead of looping."
  (if (or (null treebank-svg-contrast)
          (< treebank-svg-contrast 1)
          (null (treebank--contrast colour background)))
      colour
    (let* ((rgb (color-name-to-rgb colour))
           (towards (if (< (or (treebank--luminance background) 0) 0.5)
                        1.0
                      0.0))
           (steps 0))
      (while (and rgb
                  (< (or (treebank--contrast
                          (apply #'color-rgb-to-hex (append rgb '(2)))
                          background)
                         100)
                     treebank-svg-contrast)
                  (< steps 20))
        (setq rgb (seq-map (lambda (channel)
                             (+ channel (/ (- towards channel) 20.0)))
                           rgb))
        (setq steps (1+ steps)))
      (if rgb (apply #'color-rgb-to-hex (append rgb '(2))) colour))))

(defcustom treebank-svg-palette 'distinct
  "Where the colours of the parts of speech come from.

`distinct\=' is a palette chosen so that the twelve are TOLD APART: hues spread
round the circle, no two neighbours near each other, and two sets of them --
one for a dark background and one for a light -- picked by which the frame
has.  It is the default because the point of colouring a tree is to read it
at a glance, and a theme\='s font-lock faces are chosen to sit quietly
together in a page of code, which is the opposite requirement: four of them
are usually shades of blue.

`faces\=' takes them from `treebank-svg-postag-faces\=' instead, which
follows the theme exactly -- for a reader whose theme is already vivid, or who
would rather the drawing matched their buffers than be legible at a glance."
  :type '(choice (const :tag "A palette made to be distinct" distinct)
                 (const :tag "The theme's own faces" faces))
  :group 'treebank)

(defconst treebank-svg-palettes
  '((dark
     (?v . "#da6662")   ; verb
     (?n . "#e9eef2")   ; noun
     (?a . "#9cbae8")   ; adjective
     (?p . "#b262da")   ; pronoun
     (?d . "#e8c49c")   ; adverb
     (?l . "#9ce8db")   ; article
     (?g . "#8fd039")   ; particle
     (?c . "#9ce8ab")   ; conjunction
     (?r . "#daca62")   ; preposition
     (?m . "#39a8d0")   ; numeral
     (?i . "#d0398f")   ; interjection
     (?u . "#8c675a")   ; punctuation
     )
    (light
     (?v . "#7b0e0a")   ; verb
     (?n . "#141414")   ; noun
     (?a . "#1059c6")   ; adjective
     (?p . "#6f0da0")   ; pronoun
     (?d . "#c67110")   ; adverb
     (?l . "#0a7b68")   ; article
     (?g . "#4a7b0a")   ; particle
     (?c . "#0a7b20")   ; conjunction
     (?r . "#7b6c0a")   ; preposition
     (?m . "#0a5d7b")   ; numeral
     (?i . "#c61077")   ; interjection
     (?u . "#7c5c50")   ; punctuation
     ))
  "Two palettes for the parts of speech, by the background they are drawn on.

COMPUTED RATHER THAN CHOSEN BY EYE, because choosing twelve colours by eye is
how the first two attempts came to have five pairs a reader could confuse.
The hues are spread round the circle -- the six that matter most, the verb,
noun, adjective, pronoun, adverb and conjunction, are held at least forty
degrees apart -- and where two hues had to come nearer than that their WEIGHT
was made to differ instead, so that a pair one might call `both orange\=' is
still a light one and a dark one.  Every colour was then checked to read on
its background at a ratio of 3.5 or better.

ONE PAIR REMAINS CLOSE in each: the verb and punctuation, a red and a dim
brown.  Punctuation is dim on purpose -- a comma is not a word and should not
compete with the words for the eye -- and a comma is seldom mistaken for a
verb.

NONE OF THEM IS GREY.  Grey belongs to the relation labels, and an article
drawn in it was indistinguishable from the `ATR\=' written above it.

Which set is used is decided by the frame\='s own background, and then every
colour still goes through `treebank--legible\=': a palette knows only
whether the background is dark or light, not that it is a deep blue or a
parchment.")

(defcustom treebank-svg-postag-faces
  '((?v . font-lock-function-name-face)
    (?n . default)
    (?a . font-lock-type-face)
    (?p . font-lock-variable-name-face)
    (?d . font-lock-builtin-face)
    (?l . shadow)
    (?g . shadow)
    (?c . font-lock-keyword-face)
    (?r . font-lock-constant-face)
    (?m . font-lock-constant-face)
    (?i . font-lock-warning-face)
    (?u . shadow))
  "What face each part of speech is drawn in, by its postag letter.

FACES AND NOT COLOURS, so that the drawing follows the theme.  A colour
written down here would be a colour for ever: the same twelve values on a
light theme and a dark one, half of them unreadable on one of the two, and
none of them changing when a reader changes their theme -- which is not a
thing a package should do to somebody.  A face has a foreground in whatever
theme is loaded, and the drawing asks for it each time it draws.

The font-lock faces are used because every theme defines them and defines
them to contrast with the background, which is the whole of what is wanted
here.  What they are named for does not matter -- a verb is not a function --
but the mapping is not arbitrary either: the faces a theme makes prominent
fall to the parts of speech one looks for first.

The letters are the first place of the nine-place postag -- v verb, n noun, a
adjective, p pronoun, d adverb, l article, g particle, c conjunction, r
preposition, m numeral, i interjection, u punctuation.

A string is taken as a colour, for a reader who wants one exactly; a letter
left out is drawn in the frame\='s own foreground."
  :type '(alist :key-type character
                :value-type (choice face (string :tag "A colour")))
  :group 'treebank)

(defcustom treebank-svg-artificial-root t
  "Whether a node marked ROOT is drawn above the words.

AS ARETHUSA DRAWS IT, and it earns the space.  A sentence properly has one
word depending on nothing -- but a coordinated one has its conjunction there
with the verb beneath, a half-annotated one has two or three, and a reader
cannot see which words those are: a word with nothing above it looks like any
other word.  Hung from a node of their own they are unmistakable, and a tree
with two of them is visibly a tree with two of them.

Nil draws the head-0 words at the top rank with nothing above them."
  :type 'boolean
  :group 'treebank)

(defun treebank--postag-colour (word ink)
  "The colour WORD is drawn in, or INK where its part of speech is unknown.

THE FACE IS ASKED AT DRAWING TIME, so the tree drawn after a theme change is
drawn in the new theme -- and a face a theme does not define, or defines
without a foreground, falls back to INK rather than to nothing, an SVG with
no `fill\=' being drawn in black whatever the background."
  (let* ((postag (or (plist-get word :postag) ""))
         (letter (and (> (length postag) 0) (aref postag 0)))
         (background (or (face-attribute 'default :background nil t) "white"))
         (told
          (if (eq treebank-svg-palette 'distinct)
              (and letter
                   (cdr (assq letter
                              (cdr (assq (if (< (or (treebank--luminance
                                                     background)
                                                    0)
                                                0.5)
                                             'dark 'light)
                                         treebank-svg-palettes)))))
            (and letter
                 (cdr (assq letter treebank-svg-postag-faces))))))
    (treebank--legible
     (cond
      ((stringp told) told)
      ((and told (facep told))
       (let ((colour (face-attribute told :foreground nil t)))
         (if (and colour (not (eq colour 'unspecified))) colour ink)))
      (t ink))
     background)))

(defun treebank--tree-depths (words)
  "How deep each token hangs, as a hash from its id.

Nil for a token with no head and for one in a cycle: neither hangs from the
root, and the drawing shows them along the foot rather than inventing a place
for them."
  (let ((heads (make-hash-table :test #'equal))
        (depths (make-hash-table :test #'equal)))
    (dolist (word words)
      (puthash (plist-get word :id) (plist-get word :head) heads))
    (dolist (word words)
      ;; THE EDGES TO THE ROOT, and not the turns of the loop: the root's own
      ;; head is 0, so the root is at depth 0 and its children at 1.  Counted
      ;; the other way, every word sat one row lower than it belonged and the
      ;; drawing began with an empty rank -- which is what a picture of it
      ;; showed the moment one was drawn.
      (let ((steps 0)
            (at (plist-get word :id))
            (depth nil)
            (lost nil))
        (while (not (or depth lost))
          (let ((head (gethash at heads)))
            (cond
             ((or (null head) (string-empty-p head)) (setq lost t))
             ((equal head "0") (setq depth steps))
             ((> steps (length words)) (setq lost t))
             (t (setq at head) (setq steps (1+ steps))))))
        (when depth
          (puthash (plist-get word :id) depth depths))))
    depths))

(defun treebank--tree-svg (words)
  "WORDS as an SVG image, or nil where SVG cannot be drawn."
  (when (and (fboundp 'svg-create) (image-type-available-p 'svg))
    (require 'svg)
    (let* ((greek-size (nth 2 treebank-svg-metrics))
           ;; THE COLUMN WIDENS TO FIT THE LONGEST WORD, the configured value
           ;; being a minimum and not a ceiling.  A Greek compound of eleven
           ;; characters is some hundred and ten points wide at this size,
           ;; and its number wants fourteen more in front of it: in a column
           ;; of a hundred and twenty there is nowhere for the number to go,
           ;; and holding it inside the column -- which is what the last
           ;; attempt did -- only moved the crowding from between the words
           ;; to between the number and its own word.
           ;;
           ;; Half the point size per character, as above; and the drawing
           ;; simply comes out wider for a sentence of long words, which is
           ;; what a sentence of long words needs.
           (longest (apply #'max 1
                           (mapcar (lambda (word)
                                     (string-width
                                      (or (plist-get word :form) "")))
                                   words)))
           (column (max (nth 0 treebank-svg-metrics)
                        (+ (/ (* longest greek-size) 2) 28)))
           (row (nth 1 treebank-svg-metrics))
           (label-size (nth 3 treebank-svg-metrics))
           (depths (treebank--tree-depths words))
           (places (make-hash-table :test #'equal))
           (deepest 0)
           (width (* column (max 1 (length words))))
           (height 0)
           (greek-family (treebank--svg-greek-family))
           (ink (face-attribute 'default :foreground nil t))
           (faint (face-attribute 'shadow :foreground nil t))
           svg)
      ;; WHERE EACH WORD GOES.  y by depth; x by WALKING THE TREE.
      ;;
      ;; THE LEAVES GET THE SLOTS, one after another in reading order, and
      ;; every other word is centred over its children.  That is the layout
      ;; the printed diagrams have and the one dagre computes for Arethusa: a
      ;; chain hangs vertically, a word governing three sits over the middle
      ;; of them, and nothing lands on top of anything.
      ;;
      ;; TWO EARLIER ATTEMPTS ARE WORTH RECORDING, having each looked right
      ;; until drawn.  Fixing every word at its place in the sentence puts a
      ;; verb at the end of its clause off to the right of everything under
      ;; it, and the picture reads as a list with lines between it.  Centring
      ;; the parents afterwards and sweeping each rank to keep them apart
      ;; pushes whole ranks rightwards, a word with one child landing on the
      ;; child and shoving its siblings along.  Giving the slots to the LEAVES
      ;; is what makes both problems go away, the leaves being the only rank
      ;; that cannot collide.
      (let ((kin (treebank--tree-children words))
            (order (make-hash-table :test #'equal))
            (slot 0)
            (at 0))
        (dolist (word words)
          (setq at (1+ at))
          (puthash (plist-get word :id) at order))
        ;; Children in the order of the sentence, so the walk lays the leaves
        ;; down left to right as one reads them.
        (maphash (lambda (head children)
                   (puthash head
                            (sort (copy-sequence children)
                                  (lambda (a b)
                                    (< (gethash (plist-get a :id) order 0)
                                       (gethash (plist-get b :id) order 0))))
                            kin))
                 kin)
        (cl-labels
            ((walk (word depth)
               (setq deepest (max deepest depth))
               (let ((children
                      (seq-filter
                       (lambda (child)
                         (gethash (plist-get child :id) depths))
                       (gethash (plist-get word :id) kin))))
                 (if (null children)
                     (progn
                       (setq slot (1+ slot))
                       (puthash (plist-get word :id)
                                (cons (- (* column slot) (/ column 2))
                                      (+ 40 (* row depth)))
                                places))
                   (let ((xs nil))
                     (dolist (child children)
                       (walk child (1+ depth))
                       (let ((place (gethash (plist-get child :id) places)))
                         (when place (push (car place) xs))))
                     (puthash (plist-get word :id)
                              (cons (if xs (/ (apply #'+ xs) (length xs))
                                      (- (* column (setq slot (1+ slot)))
                                         (/ column 2)))
                                    (+ 40 (* row depth)))
                              places))))))
          (ignore #'walk)
          ;; EVERY ROOT, and in the order of the sentence: a tree half done
          ;; has more than one, and a coordinated sentence properly has its
          ;; conjunction at the top with the verb beneath -- but a reader
          ;; midway through has two and wants to see both.
          (dolist (word words)
            (when (equal (gethash (plist-get word :id) depths) 0)
              (walk word 0))))
        ;; A RANK MADE FOR THE ROOT NODE.  Everything moves down one row and
      ;; the node goes in at the top, over the middle of the words that hang
      ;; from nothing -- which is where Arethusa puts it, and what makes a
      ;; second root visible as a second root.
      (when (and treebank-svg-artificial-root (> (hash-table-count places) 0))
        (maphash (lambda (_id place) (setcdr place (+ (cdr place) row)))
                 places)
        (setq deepest (1+ deepest)))
      ;; THE WIDTH COVERS BOTH the tree and the sentence along the foot,
        ;; which is drawn in reading order and so is as wide as the sentence
        ;; is long.
        (maphash (lambda (_id place)
                   (setq width (max width (+ (car place) (/ column 2)))))
                 places))
      (setq height (+ 60 (* row (1+ deepest))))
      (setq svg (svg-create width height))
      ;; A BACKGROUND OF ITS OWN, and the reason is not decoration.  An SVG
      ;; with none is rendered by librsvg onto transparency, and what shows
      ;; through depends on the build: where it comes out white, a dark
      ;; theme's own foreground -- a pale grey -- is drawn on white and the
      ;; picture is very nearly invisible.  Which looks exactly like nothing
      ;; having been drawn.
      ;;
      ;; So the frame's own background is painted first and the frame's own
      ;; foreground drawn on it, and the two are known to contrast because a
      ;; reader has been reading text in them all along.
      (svg-rectangle svg 0 0 width height
                     :fill (or (face-attribute 'default :background nil t)
                               "white"))
      ;; THE ROOT NODE, AND ITS EDGES TO THE WORDS THAT HANG FROM NOTHING.
      ;; Drawn before the words for the same reason the other edges are: a
      ;; line under a word is a line, and a line over one is a line through
      ;; it.
      (when (and treebank-svg-artificial-root
                 (> (hash-table-count places) 0))
        (let* ((tops (delq nil
                           (mapcar (lambda (word)
                                     (and (equal (plist-get word :head) "0")
                                          (gethash (plist-get word :id)
                                                   places)))
                                   words)))
               (middle (if tops
                           (/ (apply #'+ (mapcar #'car tops)) (length tops))
                         (/ width 2))))
          (dolist (top tops)
            (svg-line svg middle 48 (car top) (- (cdr top) 14)
                      :stroke (or faint "gray") :stroke-width 1))
          ;; The relation of each, written on its edge as the others are.
          (dolist (word words)
            (when (equal (plist-get word :head) "0")
              (let ((place (gethash (plist-get word :id) places))
                    (relation (plist-get word :relation)))
                (when (and place (not (string-empty-p (or relation ""))))
                  (svg-text svg relation
                            :x (+ middle (/ (* 2 (- (car place) middle)) 5))
                            :y (+ 48 (/ (* 2 (- (cdr place) 14 48)) 5))
                            :font-family treebank-svg-label-font
                            :font-size label-size
                            :fill (or faint "gray")
                            :text-anchor "middle")))))
          (svg-text svg "[ROOT]"
                    :x middle :y 40
                    :font-family treebank-svg-label-font
                    :font-size (+ label-size 3)
                    :fill (or ink "black")
                    :text-anchor "middle")))
      ;; THE EDGES FIRST, so the words are drawn over them and not under.
      (dolist (word words)
        (let* ((here (gethash (plist-get word :id) places))
               (head (plist-get word :head))
               (there (and head (not (equal head "0"))
                           (gethash head places))))
          (when (and here there)
            (svg-line svg (car there) (+ (cdr there) 8)
                      (car here) (- (cdr here) 14)
                      :stroke (or faint "gray") :stroke-width 1)
            ;; THE RELATION TWO FIFTHS OF THE WAY DOWN THE EDGE, near the
            ;; parent rather than at the middle: at the middle the labels of
            ;; two siblings meet in the gap between them, and near the parent
            ;; they fan out as the edges do -- which is where Arethusa's are
            ;; and why they are legible.
            (let ((relation (plist-get word :relation)))
              (unless (string-empty-p (or relation ""))
                (svg-text svg relation
                          :x (+ (car there)
                                (/ (* 2 (- (car here) (car there))) 5))
                          :y (+ (cdr there) 8
                                (/ (* 2 (- (cdr here) 14 (cdr there) 8)) 5))
                          :font-family treebank-svg-label-font
                          :font-size label-size
                          :fill (or faint "gray")
                          :text-anchor "middle"))))))
      ;; AND THEN THE WORDS.  NOTHING IS DRAWN ROUND THE ROOT: the node above
      ;; the tree says which words hang from nothing, and says it better than
      ;; a box round each of them.  The box was put here before there was a
      ;; node and kept afterwards out of habit.
      (dolist (word words)
        (let ((here (gethash (plist-get word :id) places)))
          (when here
            (svg-text svg (plist-get word :form)
                      :x (car here) :y (cdr here)
                      :font-family greek-family
                      :font-size greek-size
                      :fill (treebank--postag-colour word (or ink "black"))
                      :text-anchor "middle")
            ;; THE NUMBER BEFORE THE WORD, on its baseline.  Under it is
            ;; where the edges to its children leave, and the number sat in
            ;; the middle of them.
            ;;
            ;; HALF THE WORD'S WIDTH AND NOT HALF A CHARACTER'S, which the
            ;; first attempt had: a character is about half the point size
            ;; wide in these fonts, so the word is a quarter of the size per
            ;; character from its middle -- and taking the size itself put
            ;; the number twice as far out as it belonged, into whatever
            ;; stood to its left.
            ;;
            ;; AND HELD INSIDE THE WORD'S OWN COLUMN, so that a long word
            ;; cannot push its number into a neighbour: past the column the
            ;; number sits nearer than it would like, which is the lesser
            ;; fault of the two.
            (svg-text svg (format "%s" (plist-get word :id))
                      :x (- (car here)
                            (min (+ 3 (/ (* (string-width
                                             (or (plist-get word :form) ""))
                                            greek-size)
                                         4))
                                 (- (/ column 2) 8)))
                      :y (cdr here)
                      :font-family treebank-svg-label-font
                      :font-size (max 8 (- label-size 3))
                      :fill (or faint "gray")
                      :text-anchor "end"))))
      ;; THE SENTENCE IS NO LONGER DRAWN HERE.  It ran along the foot with
      ;; each word's number under it, and it is now printed ABOVE the image
      ;; as buffer text -- see `treebank--graph-sentence' -- where it is
      ;; set in Emacs' own Greek font, may be copied, and may be looked up
      ;; with point on a word.  Two sentences, one above the picture and one
      ;; inside it, were one too many.
      (svg-image svg :scale 1
                 :background (or (face-attribute 'default :background nil t)
                                 "white")))))

(defun treebank--punctuation-p (word)
  "Whether WORD is a mark rather than a word.

BY THE POSTAG FIRST and by the form only where there is none: `u\=' is
punctuation in the nine-place tagset, and a token annotated as one says so.  A
token from a text that has not been tagged has no postag at all, and then the
form is all there is to go on."
  (let ((postag (or (plist-get word :postag) ""))
        (form (or (plist-get word :form) "")))
    (if (> (length postag) 0)
        (eq (aref postag 0) ?u)
      (and (> (length form) 0)
           (string-match-p "\\`[[:punct:]]+\\'" form)))))

(defun treebank--join-forms (words)
  "WORDS as a sentence, spaced as Greek is written.

NO SPACE BEFORE A MARK.  Every token is a word of its own in a treebank -- a
comma is a token, as ALDT wants -- so joining them all with spaces gave
`smikro/n , oi(\=', which is not how anything is written, and made the line
above the drawing hard to read as a sentence.

The marks that OPEN something take the space before them and not after: a
bracket or an opening quotation mark belongs to what follows it."
  (let ((out ""))
    (dolist (word words)
      (let ((form (or (plist-get word :form) "")))
        (cond
         ((string-empty-p out) (setq out form))
         ((treebank--punctuation-p word)
          (setq out (if (string-match-p "\\`[[(\u2018\u201c]" form)
                        (concat out " " form)
                      (concat out form))))
         ((string-match-p "[[(\u2018\u201c]\\'" out)
          (setq out (concat out form)))
         (t (setq out (concat out " " form))))))
    out))

(defun treebank--graph-sentence (words)
  "WORDS as the sentence, each in the colour its part of speech is drawn in.

ABOVE THE DRAWING AND AS TEXT, not inside the SVG.  Three things follow from
that and all three are wanted: the Greek is set in the font Emacs itself uses
rather than the one librsvg finds, point can sit on a word so `C-c C-c' will
look it up, and the sentence can be copied out of the buffer.

THE SAME COLOURS AS THE TREE, which is the whole point of putting it here: a
reader finds a word in the sentence, sees that it is orange, and knows which
of the twenty words in the picture to look at.  The numbers are the token
ids, so the table, the sentence and the drawing all name a word the same
way."
  (let ((ink (or (face-attribute 'default :foreground nil t) "black"))
        (out nil))
    ;; SPACED AS GREEK IS WRITTEN, which has to be done here rather than
    ;; through `treebank--join-forms': these pieces carry their colour and
    ;; their token with them, so they are joined as text and not as forms.
    ;; The rule is the same one -- no space before a mark, none after a
    ;; bracket that opens.
    (let ((first t)
          (opening nil))
      (dolist (word words)
        (let* ((form (or (plist-get word :form) ""))
               (mark (treebank--punctuation-p word))
               (opens (string-match-p "\\`[[(\u2018\u201c]" form))
               (piece
                (concat
                 (propertize (format "%s" (or (plist-get word :id) "?"))
                             'face '(shadow (:height 0.7)))
                 (propertize form
                             'face (list :foreground
                                         (treebank--postag-colour
                                          word ink))
                             'tei-diorisis-word word))))
          (unless (or first opening (and mark (not opens)))
            (push " " out))
          (push piece out)
          (setq opening opens)
          (setq first nil))))
    (concat (apply #'concat (nreverse out)) "\n\n")))

(defun treebank--graph-heading (words)
  "A line saying what the drawing shows, and what is left to do.

SO THAT AN EMPTY DRAWING IS LEGIBLE.  A tree not yet begun has no edges and
nothing to draw but a row of words, which looks like a fault rather than like
a beginning: this says how many of them are attached, which is none, and what
to press."
  (let* ((attached (seq-count (lambda (word)
                                (let ((head (plist-get word :head)))
                                  (and head (not (string-empty-p head)))))
                              words))
         (total (length words)))
    (propertize
     (format "%d of %d attached%s\n\n" attached total
             (if (zerop attached)
                 " -- nothing yet: RET on a word in the table attaches it"
               ""))
     'face (if (zerop attached) 'shadow 'font-lock-comment-face))))

(defun treebank--close-graph ()
  "Take down every window showing the drawing.

BEFORE DRAWING IT AGAIN.  The buffer is one and the same -- there was never a
second drawing -- but a window is not: asking for it to the right and then
below left it showing in both, and a reader pressing `D\=' three times had
three of them.  So the windows go first and one is made.

The sole window of a frame is left alone: closing it would take the frame
with it, which is not what `D\=' was asked to do."
  (let ((buffer (get-buffer "*Treebank drawn*")))
    (when buffer
      (dolist (window (get-buffer-window-list buffer nil t))
        (unless (one-window-p t (window-frame window))
          (ignore-errors (delete-window window)))))))

(defun treebank-tree-graph-describe ()
  "Say what the drawing computed for each token, and stop.

FOR TELLING THE GEOMETRY FROM THE RENDERING.  A picture that shows nothing
looks the same whether the layout placed nothing, or placed everything and
drew it in a colour the frame cannot show, or the build has no librsvg at
all -- and a reader cannot tell which by looking.  This prints the numbers:
the depth and the place of every token, and how many were placed.

A token with no depth is one whose heads do not reach the root, and is drawn
along the foot rather than in the tree."
  (interactive)
  (let* ((words treebank--tree)
         (depths (treebank--tree-depths words))
         (buffer (get-buffer-create "*Treebank geometry*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "svg available: %s\ngreek family: %s\n"
                        (image-type-available-p 'svg)
                        (treebank--svg-greek-family)))
        (insert (format "%d tokens, %d with a depth\n\n"
                        (length words)
                        (hash-table-count depths)))
        (dolist (word words)
          (insert (format "%4s  %-16s head %-4s %-10s depth %s\n"
                          (plist-get word :id)
                          (or (plist-get word :form) "")
                          (or (plist-get word :head) "-")
                          (or (plist-get word :relation) "-")
                          (or (gethash (plist-get word :id) depths)
                              "none -- not under the root"))))
        (goto-char (point-min)))
      (special-mode))
    (display-buffer buffer)))

(defun treebank-tree-graph (&optional ask)
  "Draw this tree, in a window beside the table.

Where it goes is `treebank-tree-graph-side\=', which by default asks; with
a prefix argument it asks whatever that says.

REDRAWN WITH EVERY EDIT while its window is live: `treebank--tree-render'
looks for it, so an arc moves as soon as a head is set -- which is what one
wants of a picture of something one is changing.

A BUFFER OF ITS OWN and not the table\\='s: an image in the table would push the
columns about, and the table is where point belongs."
  (interactive)
  (let ((image (treebank--tree-svg treebank--tree)))
    (unless image
      (user-error
       "This Emacs cannot draw SVG: `d' draws the tree in characters"))
    (let ((buffer (get-buffer-create "*Treebank drawn*"))
          (words treebank--tree))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (treebank--graph-heading words))
          (insert (treebank--graph-sentence words))
          (insert-image image)
          (insert "\n")
          (goto-char (point-min)))
        (setq-local treebank--tree words)
        (special-mode)
        ;; SCROLLED BY THE MOUSE OR BY `C-x o' AND NOT BY POINT: the window
        ;; holds one image and a heading, and a reader who lands in it wants
        ;; to look rather than to move.
        (setq-local truncate-lines t))
      (treebank--close-graph)
      (let* ((side (if (or ask (eq treebank-tree-graph-side 'ask))
                       (treebank--read-graph-side)
                     treebank-tree-graph-side))
             (action (treebank--graph-action side)))
        ;; REMEMBERED FOR THE REDRAW, so that a tree redrawn after every edit
        ;; does not reopen in another place.
        (setq treebank--graph-side side)
        (if action
            (display-buffer buffer action)
          (display-buffer buffer))))))

(defun treebank--tree-redraw ()
  "Draw the tree again where its window is showing.

ONLY WHERE IT IS ALREADY SHOWING.  A redraw that opened the window would put
a drawing in a reader\='s way every time they set a head, having never asked
for one; and the window it is in was placed by `treebank-tree-graph\=',
which is where it stays."
  (let ((buffer (get-buffer "*Treebank drawn*")))
    (when (and buffer (get-buffer-window buffer t))
      (let ((image (treebank--tree-svg treebank--tree)))
        (when image
          (with-current-buffer buffer
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert (treebank--graph-heading treebank--tree))
              (insert (treebank--graph-sentence treebank--tree))
              (insert-image image)
              (insert "\n"))))))))

(defun treebank-tree-toggle-diagram ()
  "Show or hide the drawing under the table."
  (interactive)
  (setq treebank-tree-diagram (not treebank-tree-diagram))
  (treebank--tree-render))

(defcustom treebank-serve-viewer t
  "Whether Emacs starts the treebank viewer's own server when it is wanted.

Non-nil starts `tools/viewer/serve.py' from this package's own directory on
`treebank-viewer-port', pointed at `treebank-directory', and
kills it when Emacs exits.

Nil leaves the serving to the reader, which is right for a viewer deployed
somewhere else, or one run as a service, or one behind a real web server."
  :type 'boolean
  :group 'treebank)

(defcustom treebank-viewer-port 8087
  "The port the viewer's server listens on.

NOT 8080, which is everybody's: a reader with a development server of their
own would find this one had taken it, or -- worse -- would find their own
answering the viewer's requests and wonder why the tree was a page of theirs."
  :type 'integer
  :group 'treebank)

(defcustom treebank-viewer-directory nil
  "Where the viewer's page and Arethusa's files are.

Nil looks for `tools/viewer' beside this file, which is where the package
keeps it.  Set this where the viewer has been put somewhere else."
  :type '(choice (const :tag "Beside this file" nil) directory)
  :group 'treebank)

(defcustom treebank-arethusa-directory nil
  "Arethusa\='s own source tree, where you have it.

WORTH SETTING FOR TWO QUITE DIFFERENT THINGS, and the first of them is not
optional if the panels are to work.

ITS RUN-TIME TEMPLATES.  A few of Arethusa\='s templates are fetched as it
draws and are not in the built bundles -- `foreign_keys_help.html\=' is one,
and Angular meeting a template it cannot load stops whatever was being
rendered.  They are all in `app/js/**/templates/\=', so with this set they are
answered with themselves instead of with the empty stub the server otherwise
sends.

AND THE WHOLE APPLICATION, at `/app/index.html\=' -- Arethusa proper, the thing
Perseids runs, with its navbar and its menus.  Point
`treebank-viewer\=' at it to use that instead of the embedded
panel:

    \"http://localhost:8087/app/index.html#/staging?doc=/trees/%n&chunk=1\"

Nil serves the embedded panel alone, which works, with stubs for those
templates."
  :type '(choice (const :tag "Not installed" nil) directory)
  :group 'treebank)

(defvar treebank--server nil
  "The viewer's server process, where we started one.")

(defun treebank--viewer-directory ()
  "Where the viewer lives, or nil where it cannot be found.

FOLLOWED THROUGH THE SYMLINK, which is the whole difficulty.  A package
manager does not put the package where its author left it: Straight builds it
into a directory of SYMLINKS to the `.el\=' files, and `tools/viewer\=' -- a
directory, not a Lisp file -- is not among them.  Looking beside the file as
loaded therefore found nothing, and the server was never started.

`file-truename\=' goes back through the link to the repository, where the
viewer is; and the built directory is tried as well, for an installation that
copied rather than linked."
  (or treebank-viewer-directory
      (let* ((loaded (or load-file-name buffer-file-name
                         (locate-library "tei-diorisis")))
             (places (delq nil
                           (list (and loaded (file-name-directory
                                              (file-truename loaded)))
                                 (and loaded (file-name-directory loaded))
                                 default-directory))))
        (let ((found (seq-find
                      (lambda (where)
                        (file-exists-p
                         (expand-file-name "tools/viewer/serve.py" where)))
                      places)))
          (and found (expand-file-name "tools/viewer/" found))))))

(defun treebank--port-answers-p (port)
  "Whether something is already listening on PORT.

ASKED BY OPENING A CONNECTION and closing it again, which is the only way to
know: a port nobody holds refuses at once, and one held by a server of the
reader's own answers.  Cheap, and the alternative is starting a second server
that fails to bind and leaves its complaint in a buffer nobody reads."
  (let ((connection (ignore-errors
                      (open-network-stream "tei-diorisis-port-test" nil
                                           "127.0.0.1" port
                                           :type 'plain :nowait nil))))
    (when connection
      (delete-process connection)
      t)))

(defun treebank-serve ()
  "Start the viewer's server, unless something is already listening."
  (interactive)
  (cond
   ((and treebank--server (process-live-p treebank--server))
    treebank--server)
   ((treebank--port-answers-p treebank-viewer-port)
    (message "Something already answers on port %d; leaving it to it"
             treebank-viewer-port)
    nil)
   (t
    (let ((where (treebank--viewer-directory)))
      (unless where
        (user-error "No viewer found: see treebank-viewer-directory"))
      (setq treebank--server
            (make-process
             :name "tei-diorisis-viewer"
             :buffer (get-buffer-create "*Diorisis viewer server*")
             :command (append
                       (list (or (executable-find "python3")
                                 (user-error "No python3 to run the viewer"))
                             (expand-file-name "serve.py" where)
                             "--port" (number-to-string
                                       treebank-viewer-port)
                             "--trees" (expand-file-name
                                        treebank-directory))
                       ;; AND ARETHUSA'S SOURCE WHERE THERE IS SOME.
                       ;; APPENDED AND NOT PASSED EMPTY: an empty string is
                       ;; an argument, and `--arethusa ""' would have the
                       ;; server refuse to start for want of an `app/'
                       ;; directory in the current one.
                       (when treebank-arethusa-directory
                         (list "--arethusa"
                               (expand-file-name
                                treebank-arethusa-directory))))
             ;; A CHILD OF THIS EMACS, so it goes when Emacs goes.  Emacs
             ;; kills its children on exit where they are not
             ;; `process-query-on-exit-flag' -- which is asked of the reader
             ;; and answered here, a web server for a page being nothing to
             ;; ask about.
             :noquery t
             :sentinel
             (lambda (_process event)
               (unless (string-prefix-p "run" event)
                 (setq treebank--server nil)))))
      ;; A MOMENT TO BIND THE PORT.  The page is asked for immediately after
      ;; this returns, and a request to a socket that is not listening yet
      ;; fails outright rather than waiting.
      (let ((waited 0))
        (while (and (< waited 30)
                    (not (treebank--port-answers-p
                          treebank-viewer-port)))
          (sleep-for 0.05)
          (setq waited (1+ waited))))
      ;; DID IT START?  A `serve.py' that exits at once -- no such trees
      ;; directory, a port taken between the probe and the bind -- left a
      ;; message saying the viewer was served and a page that could not be
      ;; fetched.  So the process is asked, and its own words are where the
      ;; reader is sent.
      (unless (and (process-live-p treebank--server)
                   (treebank--port-answers-p treebank-viewer-port))
        (let ((said (with-current-buffer "*Diorisis viewer server*"
                      (string-trim (buffer-string)))))
          (setq treebank--server nil)
          (user-error "The viewer's server would not start%s"
                      (if (string-empty-p said)
                          " -- see *Diorisis viewer server*"
                        (format ": %s" (car (last (split-string said "\n"))))))))
      (message "The viewer is served on port %d" treebank-viewer-port)
      treebank--server))))

(defun treebank--trees-open-p ()
  "Whether any tree is still being annotated."
  (seq-find (lambda (buffer)
              (with-current-buffer buffer
                (derived-mode-p 'treebank-tree-mode)))
            (buffer-list)))

(defun treebank--maybe-stop-serving ()
  "Stop the viewer's server once the last tree is closed.

WHY THE LAST AND NOT THIS ONE.  Two trees open at once is ordinary -- a
passage and the one it quotes -- and a server stopped when the first of them
was closed would leave the other\='s viewer showing a page it could no longer
reload.  So the count is what matters, and `buffer-list\=' is asked rather than
kept: a count of our own would be wrong the first time a buffer was killed by
something other than `q\='.

Called from `kill-buffer-hook\=', where THIS buffer is still in the list -- so
it is excluded by name rather than by counting to one."
  (unless (seq-find (lambda (buffer)
                      (and (not (eq buffer (current-buffer)))
                           (with-current-buffer buffer
                             (derived-mode-p 'treebank-tree-mode))))
                    (buffer-list))
    (when (and treebank--server (process-live-p treebank--server))
      (delete-process treebank--server)
      (setq treebank--server nil)
      (message "The last tree is closed; the viewer\='s server has stopped"))))

(defun treebank-serve-stop ()
  "Stop the viewer's server, where we started it."
  (interactive)
  (if (and treebank--server (process-live-p treebank--server))
      (progn (delete-process treebank--server)
             (setq treebank--server nil)
             (message "The viewer's server has stopped"))
    (message "No server of ours is running")))

(defun treebank-tree-widget (&optional ask)
  "Open this tree in a treebank viewer, to be drawn as a diagram.

With a prefix argument, choose the viewer from
`treebank-viewers\=' rather than using
`treebank-viewer\='.

Saves first: what a viewer reads is the file, and a viewer showing the tree as
it stood ten edits ago is worse than no viewer at all."
  (interactive "P")
  (unless treebank--tree-file (user-error "This tree has no file"))
  (treebank-tree-save)
  ;; THE SERVER FIRST, where we are to run one: the page is about to be asked
  ;; for and nothing would answer.
  ;;
  ;; AND ITS COMPLAINT IS NOT SWALLOWED.  This was wrapped in `ignore-errors',
  ;; so a server that could not start said nothing and the page was opened at
  ;; a port nobody held -- `Could not connect to localhost', which tells a
  ;; reader nothing about what actually went wrong.
  (when treebank-serve-viewer
    (treebank-serve))
  (let* ((template
          (cond
           (ask (cdr (assoc (completing-read
                             "Open it in: "
                             treebank-viewers nil t)
                            treebank-viewers)))
           (t treebank-viewer)))
         (file (concat "file://" treebank--tree-file))
         ;; `%n\=' AND `%f\='.  A viewer served from somewhere cannot fetch a
         ;; `file://\=' path, the browser refusing it as another origin -- so a
         ;; local viewer is told the FILE NAME and finds the trees itself.
         ;;
         ;; AND ONLY THE NAME.  Arethusa substitutes the name into a route of
         ;; its own and encodes it as one path segment, so a `%n\=' with
         ;; directories in front of it came back as `/%2Ftrees%2Fx.xml\=' and a
         ;; 404: where the trees are belongs in the viewer\='s own
         ;; configuration, not in this template.  `%f\=' is the whole file URL
         ;; for a viewer that can take one, and `%s\=' the same, for templates
         ;; written before there was a choice.
         (url (if template
                  (let ((made template))
                    (setq made (replace-regexp-in-string
                                "%n" (url-hexify-string
                                      (file-name-nondirectory
                                       treebank--tree-file))
                                made t t))
                    (setq made (replace-regexp-in-string
                                "%[fs]" (url-hexify-string file) made t t))
                    made)
                file)))
    (treebank--open-url url)
    (unless template
      (message "No viewer set: showing the file itself.  See %s"
               "treebank-viewer"))))

(defun treebank--xwidgets-p ()
  "Whether this Emacs can show a page in a window of its own."
  (and (featurep 'xwidget-internal)
       (fboundp 'xwidget-webkit-browse-url)
       (display-graphic-p)))

(defun treebank--open-url (url)
  "Open URL, here or in the browser, as `treebank-tree-widget-in-emacs\='
says.

THE BUILD IS ASKED AND NOT ASSUMED.  Xwidgets want an Emacs built
`--with-xwidgets\=', are GTK only, and want a graphical frame -- so `auto\='
tries and falls through quietly, t tries and says where it cannot, and nil
does not try."
  (pcase treebank-tree-widget-in-emacs
    ('nil (browse-url url))
    ('auto (if (treebank--xwidgets-p)
               (xwidget-webkit-browse-url url t)
             ;; QUIETLY: `auto' means `whichever works', and a message every
             ;; time would be a reproach for a build the reader may not have
             ;; chosen.
             (browse-url url)))
    (_ (if (treebank--xwidgets-p)
           (xwidget-webkit-browse-url url t)
         (message "This Emacs has no xwidgets; opening the browser instead")
         (browse-url url)))))

(defun treebank-tree-widget-here ()
  "Open this tree in a viewer INSIDE Emacs, in an xwidget.

For a reader whose `treebank-tree-widget-in-emacs\=' is nil and who wants
it here this once."
  (interactive)
  (let ((treebank-tree-widget-in-emacs t))
    (treebank-tree-widget)))

(defun treebank-tree-widget-browser ()
  "Open this tree in a viewer in the BROWSER, whatever the option says."
  (interactive)
  (let ((treebank-tree-widget-in-emacs nil))
    (treebank-tree-widget)))

(defun treebank--aldt-read (file)
  "Read FILE and return its sentences.

Each is a plist: :id, :document-id, :subdoc, :span and :words, the words being
plists of :id, :form, :lemma, :postag, :relation and :head.

PARSED AS XML AND NOT BY REGEXP, `xml-parse-file\\=' being in Emacs already: a
file that has been round Arethusa comes back with attributes in another order,
with a namespace, and with whitespace where ours had none."
  (let* ((tree (xml-parse-file file))
         (root (car tree))
         (sentences nil))
    (dolist (node (xml-get-children root 'sentence))
      (let ((words nil))
        (dolist (word (xml-get-children node 'word))
          (let ((attributes (xml-node-attributes word)))
            (push (list :id (cdr (assq 'id attributes))
                        :form (cdr (assq 'form attributes))
                        :lemma (cdr (assq 'lemma attributes))
                        :postag (cdr (assq 'postag attributes))
                        :relation (or (cdr (assq 'relation attributes)) "")
                        :head (or (cdr (assq 'head attributes)) ""))
                  words)))
        (push (list :language
                    ;; `xml:lang' ON THE TREEBANK ELEMENT, which every ALDT
                    ;; file carries: `grc' or `lat'.  A tree annotated in
                    ;; Latin opened in a session of Greek would otherwise
                    ;; have its postags read by the wrong table.
                    (let ((lang (or (cdr (assq 'xml:lang
                                               (xml-node-attributes root)))
                                    (cdr (assq 'lang
                                               (xml-node-attributes root))))))
                      (if (and lang (string-prefix-p "lat" lang))
                          'latin 'greek))
                    :id (cdr (assq 'id (xml-node-attributes node)))
                    :document-id (cdr (assq 'document_id
                                            (xml-node-attributes node)))
                    :subdoc (cdr (assq 'subdoc (xml-node-attributes node)))
                    :span (cdr (assq 'span (xml-node-attributes node)))
                    :words (nreverse words))
              sentences)))
    (nreverse sentences)))

(defun treebank--aldt-write (file sentence words)
  "Write WORDS to FILE as one ALDT treebank, SENTENCE giving its attributes."
  (with-temp-file file
    ;; `xml:lang' FROM THE BUFFER'S OWN LANGUAGE, so a Latin tree says it is
    ;; Latin and is read back by the Latin table.  `format="aldt"' is the
    ;; attribute Perseus' files carry for either language: the GREEK corpus is
    ;; the AGDT and the Latin one the LDT, and `aldt' names neither -- it is
    ;; the format, which they share.
    (insert "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            (format "<treebank xml:lang=\"%s\" format=\"aldt\" \
version=\"1.5\">\n"
                    ;; `la\=' AND NOT `lat\='.  The released Latin treebanks
                    ;; carry `xml:lang="la"\=' and the Greek ones `"grc"\=',
                    ;; which is not the symmetry one would guess; our reader
                    ;; takes either, and what we WRITE should be what
                    ;; everything else writes.
                    (if (eq diorisis-language 'latin) "la" "grc")))
    (insert (format "  <sentence id=\"%s\" document_id=\"%s\" subdoc=\"%s\" \
span=\"%s\">\n"
                    (or (plist-get sentence :id) "1")
                    (treebank--xml (or (plist-get sentence :document-id)
                                           ""))
                    (treebank--xml (or (plist-get sentence :subdoc) ""))
                    (treebank--xml (or (plist-get sentence :span) ""))))
    (dolist (word words)
      (insert (format "    <word id=\"%s\" form=\"%s\" lemma=\"%s\" \
postag=\"%s\" relation=\"%s\" head=\"%s\"/>\n"
                      (plist-get word :id)
                      (treebank--xml (or (plist-get word :form) ""))
                      (treebank--xml (or (plist-get word :lemma) ""))
                      (or (plist-get word :postag) "")
                      (treebank--xml (or (plist-get word :relation) ""))
                      (or (plist-get word :head) ""))))
    (insert "  </sentence>\n</treebank>\n")))

(defun treebank--tree-problems (words)
  "What is wrong with the tree WORDS describe, as a list of complaints.

THREE THINGS CAN BE WRONG and all three are worth catching as one works
rather than on being told by a tool afterwards:

  A HEAD THAT IS NOT A TOKEN -- a number left over from renumbering, or a
  typing slip.  Nothing downstream can do anything with it.

  NOT EXACTLY ONE ROOT.  A tree has one word depending on nothing, its head
  written 0; none means the tree is unfinished and two means it is two trees.

  A CYCLE.  Two words each depending on the other is the one fault that looks
  right token by token and is wrong as a whole, and the only way to see it is
  to walk up from every word and count the steps."
  (let* ((ids (mapcar (lambda (word) (plist-get word :id)) words))
         (problems nil)
         (roots 0))
    (dolist (word words)
      (let ((head (plist-get word :head))
            (id (plist-get word :id)))
        (cond
         ((or (null head) (string-empty-p head)) nil)
         ((equal head "0") (setq roots (1+ roots)))
         ((not (member head ids))
          (push (format "%s: head %s is not a token" id head) problems)))))
    (cond ((= roots 0) (push "no root: no token has head 0" problems))
          ((> roots 1) (push (format "%d roots, and a tree has one" roots)
                             problems)))
    ;; THE CYCLE CHECK, walking up from each token.  A chain longer than the
    ;; sentence cannot be a chain, which is cheaper than colouring nodes and
    ;; says the same thing.
    (let ((heads (make-hash-table :test #'equal)))
      (dolist (word words)
        (puthash (plist-get word :id) (plist-get word :head) heads))
      (dolist (word words)
        (let ((seen 0)
              (at (plist-get word :id)))
          (while (and at (not (member at '("0" ""))) (<= seen (length words)))
            (setq at (gethash at heads))
            (setq seen (1+ seen)))
          (when (> seen (length words))
            (push (format "%s: its heads lead in a circle"
                          (plist-get word :id))
                  problems)))))
    (nreverse (delete-dups problems))))

(defcustom treebank-tree-watch t
  "Whether the editor notices the file being written by something else.

ONE FILE, TWO EDITORS.  A tree open here and open in Arethusa is one file, and
whichever wrote it last is right -- so the editor watches, and rereads when
the file changes under it.  That is what makes the three ways at a tree one
job rather than three copies of it: the table and the drawing here, the graph
in the viewer, and the same ALDT between them.

Nil watches nothing, for a reader who would rather reread by hand with `g'."
  :type 'boolean
  :group 'treebank)

(defvar-local treebank--tree-watcher nil
  "The file notification this buffer is listening on.")

(defvar-local treebank--tree-written nil
  "The file as we last wrote it, so that our own writing is not read back.")

(defun treebank--tree-stamp (file)
  "FILE's size and modification time, as a string."
  (let ((attributes (and file (file-attributes file))))
    (and attributes
         (format "%d %s" (file-attribute-size attributes)
                 (float-time (file-attribute-modification-time
                              attributes))))))

(defun treebank--tree-unwatch ()
  "Stop listening for changes to this tree's file."
  (when treebank--tree-watcher
    (ignore-errors (file-notify-rm-watch treebank--tree-watcher))
    (setq treebank--tree-watcher nil)))

(defun treebank--tree-changed (buffer)
  "Reread BUFFER's tree, the file having changed.

OUR OWN WRITING IS NOT READ BACK.  Every save records the file's size and
time, and a change that matches what we wrote is the echo of that save --
rereading it would be harmless and would also move point for nothing.

AND NOTHING IS OVERWRITTEN SILENTLY.  Where this buffer has edits that are
not on disk, the reader is asked: two editors on one file can only be
reconciled by somebody who knows which edit was meant."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((now (treebank--tree-stamp treebank--tree-file)))
        (unless (equal now treebank--tree-written)
          (if (and (buffer-modified-p)
                   (not (y-or-n-p
                         (format "%s changed elsewhere; reread it and lose \
the edits here? "
                                 (file-name-nondirectory
                                  treebank--tree-file)))))
              (message "Keeping what is here; `g' rereads the file")
            (treebank-tree-revert)
            (message "%s changed elsewhere, and was reread"
                     (file-name-nondirectory treebank--tree-file))))))))

(defun treebank--tree-watch ()
  "Listen for this tree's file being written by something else.

`file-notify' AND NOT A TIMER, so that a save in Arethusa is seen at once and
nothing is asked of the disk in between.  Where the system has no notification
to give -- a remote file, a build without inotify -- no watch is made and `g'
remains."
  (when (and treebank-tree-watch
             treebank--tree-file
             (fboundp 'file-notify-add-watch))
    (treebank--tree-unwatch)
    (setq treebank--tree-watcher
          (ignore-errors
            (file-notify-add-watch
             treebank--tree-file '(change)
             (let ((buffer (current-buffer)))
               (lambda (event)
                 (when (memq (nth 1 event) '(changed created renamed))
                   (treebank--tree-changed buffer)))))))))

(defun treebank-tree-revert ()
  "Read this tree from its file again, keeping the token point is on."
  (interactive)
  (unless treebank--tree-file (user-error "This tree has no file"))
  (let* ((at (ignore-errors (plist-get (treebank--tree-at) :id)))
         (sentences (treebank--aldt-read treebank--tree-file))
         (sentence (car sentences)))
    (unless sentence
      (user-error "Nothing to read in %s" treebank--tree-file))
    (setq treebank--tree-sentence sentence)
    (setq treebank--tree (plist-get sentence :words))
    (setq treebank--tree-written
          (treebank--tree-stamp treebank--tree-file))
    (treebank--tree-render)
    (set-buffer-modified-p nil)
    ;; BACK TO THE SAME TOKEN and not to the top: a reader who has just
    ;; watched the graph change wants to go on from where they were.
    (when at
      (goto-char (point-min))
      (let ((found nil))
        (while (and (not found) (not (eobp)))
          (let ((here (get-text-property (point) 'tei-diorisis-word)))
            (when (and here (equal (plist-get here :id) at))
              (setq found (point))))
          (forward-line 1))
        (goto-char (or found (point-min)))))))

(defun treebank--tree-render ()
  "Print the tokens of this buffer's tree."
  (let* ((inhibit-read-only t)
         (widths treebank-tree-columns)
         ;; THE POSTAG COLUMN FITS WHAT IT IS SHOWING.  `n-s---mg-\=' is nine
         ;; characters and `noun sg masc gen\=' is sixteen, so a column set
         ;; for the code truncates the words -- and the words are there to be
         ;; read.  The configured width is the least it may be.
         (postag-width
          (max (nth 2 treebank-tree-columns)
               (+ 2 (apply #'max 1
                           (mapcar (lambda (word)
                                     (string-width
                                      (treebank--postag-said
                                       (plist-get word :postag))))
                                   treebank--tree)))))
         (at (get-text-property (point) 'tei-diorisis-word))
         (words treebank--tree)
         (sentence treebank--tree-sentence)
         (problems (treebank--tree-problems words))
         (landing nil))
    (erase-buffer)
    (insert (propertize
             (format "%s %s\n"
                     (or (plist-get sentence :document-id) "?")
                     (or (plist-get sentence :subdoc) ""))
             'face 'bold))
    (insert (propertize
             ;; SPACED AS GREEK IS WRITTEN and not one space per token: see
             ;; `treebank--join-forms'.
             (concat (treebank--join-forms words) "\n\n")
             'face 'font-lock-comment-face))
    (dolist (word words)
      (let ((start (point)))
        (insert (format "%4s  %s%s%s%s  %s\n"
                        (plist-get word :id)
                        (treebank--pad (plist-get word :form)
                                           (nth 0 widths))
                        (treebank--pad (plist-get word :lemma)
                                           (nth 1 widths))
                        (treebank--pad
                         (treebank--postag-said
                          (plist-get word :postag))
                         postag-width)
                        (let ((head (plist-get word :head)))
                          (propertize (format "%-5s"
                                              (if (or (null head)
                                                      (string-empty-p head))
                                                  "-" head))
                                      'face (if (equal head "0")
                                                'bold 'default)))
                        (let ((relation (plist-get word :relation)))
                          (propertize (if (string-empty-p (or relation ""))
                                          "-" relation)
                                      'face 'diorisis-form-face))))
        (put-text-property start (point) 'tei-diorisis-word word)
        (when (and at (equal (plist-get at :id) (plist-get word :id)))
          (setq landing start))))
    (insert "\n")
    (when treebank-tree-diagram
      (insert (treebank--tree-draw words) "\n\n"))
    (if problems
        (dolist (problem problems)
          (insert (propertize (format "  %s\n" problem) 'face 'error)))
      (insert (propertize "  a tree: one root, every head a token, no cycles\n"
                          'face 'success)))
    (insert (propertize
             (concat "\nRET attaches the word at point: its head, then "
                     "its relation, then on to the next.\n"
                     "At the head prompt, type the WORD (beta code or Greek, "
                     "accents optional) or its id.\n"
                     "f fills it from the corpus \u00b7 L sets its lemma "
                     "\u00b7 F fills them all "
                     "\u00b7 P parses it with Diogenes\n"
                     "?  every other key \u00b7 0 make it the root \u00b7 "
                     "h head \u00b7 r relation \u00b7 t postag \u00b7 x undo\n"
                     "d draw \u00b7 w viewer \u00b7 s save \u00b7 g reread "
                     "\u00b7 q quit "
                     "\u00b7 each is also under C-c\n"
                     "H  how to annotate: where clauses and conjunctions go "
                     "\u00b7 e  this relation\n")
             'face 'shadow))
    (goto-char (or landing (point-min)))
    ;; MODIFIED UNTIL SAVED.  Rendering happens after every edit, so this is
    ;; where the buffer becomes dirty; `treebank-tree-save' and
    ;; `treebank-tree-revert' clear it.  Without it the watch could not
    ;; tell an outside change from this buffer's own unsaved work, and would
    ;; either lose edits or ask about every save.
    (set-buffer-modified-p t)
    (treebank--tree-redraw)))

(defun treebank--pad (string width)
  "STRING padded to WIDTH display columns.
By `string-width', Greek accents being combining characters that take no
column of their own: `length' put the columns out by one per accent."
  (let* ((string (or string ""))
         (pad (max 1 (- width (string-width string)))))
    (concat string (make-string pad ?\s))))

(defun treebank--tree-at ()
  "The token at point, or an error."
  (or (get-text-property (point) 'tei-diorisis-word)
      (user-error "No token here")))

(defun treebank--tree-candidates (word)
  "The tokens one may attach WORD to: (CANDIDATES IDS PAIRS).

CANDIDATES ARE THE WORDS THEMSELVES, and the ids are not in them.  The id
used to come first -- `3  ἐμπέφυκε  v3sria---' -- so typing the word matched
nothing at all: what one types has to be the beginning of the candidate under
every ordinary completion style.  The id and the postag are shown through an
affixation instead, which is display and not text to be matched.

IDS maps a candidate to the id it stands for; PAIRS is the same candidates
with their diacritic-free forms, for the style that matches them -- so
`empefuke' and `ἐμπεφυκε' both find ἐμπέφυκε, as at the lemma prompt.

The root is offered first, and a word cannot be offered itself."
  (let ((ids (make-hash-table :test #'equal))
        (candidates nil)
        (pairs nil))
    (puthash "the root (this word depends on nothing)" "0" ids)
    (push "the root (this word depends on nothing)" candidates)
    (push (cons "the root (this word depends on nothing)" "root") pairs)
    (dolist (other treebank--tree)
      (unless (equal (plist-get other :id) (plist-get word :id))
        (let* ((form (or (plist-get other :form) "?"))
               ;; TWO WORDS OF ONE FORM in a sentence is ordinary -- an
               ;; article twice over -- so the id distinguishes the second,
               ;; and only where it must.
               (candidate (if (gethash form ids)
                              (format "%s  (%s)" form (plist-get other :id))
                            form)))
          (puthash candidate (plist-get other :id) ids)
          (push candidate candidates)
          (push (cons candidate (diorisis--bare form)) pairs))))
    (list (nreverse candidates) ids (nreverse pairs))))

(defun treebank--read-head (word)
  "Read what WORD depends on, and return an id.

A NUMBER MAY BE TYPED INSTEAD: the table shows ids and a reader looking at it
will reach for one, so an answer that is a number and is a token\='s id is
taken as that token."
  (let* ((found (treebank--tree-candidates word))
         (candidates (nth 0 found))
         (ids (nth 1 found))
         (diorisis--completion-pairs (nth 2 found))
         (table (lambda (string predicate action)
                  (pcase action
                    ('metadata
                     '(metadata (category . tei-diorisis-lemma)
                                (display-sort-function . identity)
                                (cycle-sort-function . identity)))
                    (_ (complete-with-action action candidates
                                             string predicate)))))
         ;; THE ID AND THE POSTAG BESIDE EACH, as display: an affixation is
         ;; not matched, so showing them costs nothing and the reader still
         ;; sees which token is which.
         (completion-extra-properties
          (list :annotation-function
                (lambda (candidate)
                  (let* ((id (gethash candidate ids))
                         (other (seq-find
                                 (lambda (one)
                                   (equal (plist-get one :id) id))
                                 treebank--tree)))
                    (if other
                        (format "   %s   %s" id
                                (or (plist-get other :postag) ""))
                      "")))))
         (answer (string-trim
                  (completing-read
                   (format "%s depends on: " (plist-get word :form))
                   table nil nil))))
    (or (gethash answer ids)
        ;; A bare id, typed straight in.
        (and (string-match-p "\\`[0-9]+\\'" answer)
             (seq-find (lambda (other)
                         (equal (plist-get other :id) answer))
                       treebank--tree)
             answer)
        (and (equal answer "0") "0")
        (user-error "No such token: %s" answer))))

(defun treebank-tree-attach ()
  "Attach the token at point: its head, then its relation.

THE TWO GO TOGETHER and are one act of annotation.  Asking for them
separately was the editor's worst feature: a reader had to know that `h' and
`r' both existed and that a word wanted both, and a word with a head and no
relation is not half annotated -- it is wrong.  So `RET' asks for the head,
then for the relation, and a word is done when it is done.

`h' and `r' are still there for correcting one without the other."
  (interactive)
  (treebank-tree-set-head)
  (treebank-tree-set-relation)
  ;; ON TO THE NEXT WORD, which is what one wants after finishing this one:
  ;; annotation is a sentence gone through in order, and a reader who has to
  ;; move by hand between every word feels every keystroke of it.
  (treebank-tree-next))

(defun treebank-tree-next (&optional n)
  "Move to the next token, or the Nth after this one."
  (interactive "p")
  (dotimes (_ (max 1 (or n 1)))
    (let ((match (save-excursion
                   (text-property-search-forward
                    'tei-diorisis-word nil nil t))))
      (if match
          (goto-char (prop-match-beginning match))
        (message "The last token")))))

(defun treebank-tree-previous (&optional n)
  "Move to the previous token, or the Nth before this one."
  (interactive "p")
  (dotimes (_ (max 1 (or n 1)))
    (let ((match (save-excursion
                   (text-property-search-backward
                    'tei-diorisis-word nil nil t))))
      (if match
          (goto-char (prop-match-beginning match))
        (message "The first token")))))

(defun treebank-tree-set-root ()
  "Make the token at point the root of the sentence.

THE FIRST THING ONE DOES to a tree, and it wanted two prompts and an answer
of `0\=' typed into a list of words.  `0\=' does it."
  (interactive)
  (let ((word (treebank--tree-at)))
    (plist-put word :head "0")
    (plist-put word :relation (treebank--read-relation word))
    (treebank--tree-render)))

(defun treebank-tree-set-lemma ()
  "Set the lemma of the token at point by finding it.

FOR WHEN NEITHER THE CORPUS NOR THE PARSER HAS IT.  `f\=' asks the corpus and
`P\=' asks Diogenes, and between them they answer for most words -- but a form
the corpus does not attest and Morpheus cannot make leaves a reader with
nothing to do but type, and nowhere to type it.

THE LEMMA PROMPT IS THE WHOLE OF IT: beta code or Greek, accents optional,
completing on the corpus\=' own 63,718 lemmata, and an inflected form settled
into its lemma -- see `diorisis-read-lemma\='.  What is set is the Greek,
which is what ALDT wants in the attribute.

The postag is left alone; `t\=' sets that, and a reader correcting a lemma
usually has the morphology right already."
  (interactive)
  (let* ((word (treebank--tree-at))
         (lemma (diorisis-read-lemma
                 (format "%s is a form of: " (plist-get word :form)))))
    (unless (string-empty-p lemma)
      (plist-put word :lemma (diorisis--greek lemma))
      (treebank--tree-render))))

(defun treebank-tree-unattach ()
  "Forget the head and the relation of the token at point."
  (interactive)
  (let ((word (treebank--tree-at)))
    (plist-put word :head "")
    (plist-put word :relation "")
    (treebank--tree-render)))

(defvar treebank--form-index-declined nil
  "Non-nil where the reader has said no to the form index this session.")

(defun treebank--form-indexed-p ()
  "Whether the corpus is indexed by form."
  (ignore-errors
    (car (diorisis--select
          "SELECT 1 FROM sqlite_master WHERE type = \'index\'\
 AND tbl_name = \'occurrences\' AND sql LIKE \'%(form)%\'"))))

(defun treebank--want-form-index ()
  "Offer the form index before a lookup that would be slow without it.

WHY THIS IS ASKED HERE AND NOT LEFT IN A MANUAL.  `form\=' is not indexed --
the corpus is indexed by lemma, a lemma being what it is for -- so `f\=' is a
pass over ten million rows and `F\=' is one pass for the sentence, which is
better and still seconds.  The index makes both immediate, costs some minutes
once and a few tens of megabytes, and nobody who has not read
`diorisis-index-forms\=' knows it exists.

Asked once a session at most: a reader who says no is not asked again until
Emacs is restarted, since the answer to `would you like to wait five minutes\='
does not change in an afternoon."
  (unless (or (treebank--form-indexed-p)
              treebank--form-index-declined)
    (if (y-or-n-p "Looking a form up scans ten million rows.  \
Index the corpus by form now?  Some minutes, once: ")
        (progn
          (message "Indexing by form; this is the wait, and the last one ...")
          (sqlite-execute
           (diorisis--db)
           "CREATE INDEX IF NOT EXISTS occurrences_form ON occurrences (form)")
          (message "Indexed by form: `f\' and `F\' are immediate now"))
      (setq treebank--form-index-declined t))))

(defun treebank--form-variants (form)
  "FORM as beta code, in every spelling the corpus might have it.

THE ASTERISK IS THE WHOLE OF THE PROBLEM.  Beta code marks a capital by
putting an asterisk in front of it -- Κατέβην is `*kate/bhn\=' -- and the
first word of a sentence is capitalised in the text and lower case in the
lexicon.
So `f\=' on the first word of every sentence answered `the corpus does not
attest it\=', which was true of the spelling and false of the word.

Both are asked for, and the accents are left alone: a capital is a difference
in how the word is written and an accent is a difference in what it is."
  (let* ((beta (diorisis--beta form))
         (bare (replace-regexp-in-string "\\*" "" beta)))
    (delete-dups (list beta bare (concat "*" bare)))))

(defun treebank--rows-for (form table)
  "The rows TABLE holds for FORM, under whichever spelling answered.

The table is keyed by what the corpus has, and what the corpus has may be the
capitalised spelling or the plain one -- see
`treebank--form-variants\='."
  (seq-some (lambda (variant) (gethash variant table))
            (treebank--form-variants form)))

(defun treebank--forms-in-corpus (forms)
  "What the corpus knows about FORMS, as a hash from form to rows.

ONE PASS FOR ALL OF THEM.  `form' is not indexed, so a lookup is a pass over
ten million rows -- and one pass answering twenty words costs what one word
used to.  `IN (...)' rather than a query each: the placeholders are built from
the list, since a form is a reader's text and has no business being pasted
into SQL."
  (treebank--want-form-index)
  (let ((table (make-hash-table :test #'equal))
        (beta (delete-dups
               (apply #'append
                      (mapcar #'treebank--form-variants forms)))))
    (when beta
      (dolist (row (diorisis--select
                    (format "SELECT form, lemma, pos, morph, COUNT(*)\
 FROM occurrences WHERE form IN (%s)\
 GROUP BY form, lemma, pos, morph ORDER BY 5 DESC"
                            (string-join (make-list (length beta) "?") ", "))
                    beta))
        (puthash (nth 0 row)
                 (append (gethash (nth 0 row) table) (list (cdr row)))
                 table)))
    table))

(defun treebank--fill-word (word rows &optional ask)
  "Fill WORD's lemma and postag from ROWS.  Return non-nil where it did.

UNAMBIGUOUS WITHOUT ASKING, AMBIGUOUS ONLY WHEN ASKED.  A form the corpus
attests under one lemma is filled; a form under two is a question, and the
answer depends on the sentence, which the corpus had and this has not.  With
ASK the reader is shown the lemmata with their frequencies and chooses --
which is the right thing when they have asked about this word in particular,
and the wrong thing to do twenty times over unprompted."
  (let ((lemmata (delete-dups (mapcar #'car rows))))
    (cond
     ((null rows) nil)
     ((null (cdr lemmata))
      (plist-put word :lemma (diorisis--greek (car lemmata)))
      (plist-put word :postag (treebank--postag (nth 1 (car rows))
                                                    (nth 2 (car rows))))
      t)
     (ask
      (let* ((labels
              (mapcar (lambda (row)
                        (cons (format "%-14s %-22s %s"
                                      (diorisis--greek (nth 0 row))
                                      (or (nth 2 row) "")
                                      (nth 3 row))
                              row))
                      rows))
             (chosen (cdr (assoc (completing-read
                                  (format "%s is: " (plist-get word :form))
                                  labels nil t)
                                 labels))))
        (when chosen
          (plist-put word :lemma (diorisis--greek (nth 0 chosen)))
          (plist-put word :postag (treebank--postag (nth 1 chosen)
                                                        (nth 2 chosen)))
          t)))
     (t nil))))

(defun treebank-tree-fill ()
  "Fill the lemma and postag of the token at point from the corpus.

Asks where the form is ambiguous: a reader who has asked about THIS word
wants the choice, and there is nobody else to make it."
  (interactive)
  (let* ((word (treebank--tree-at))
         (form (or (plist-get word :form) ""))
         (rows (treebank--rows-for
                form (treebank--forms-in-corpus (list form)))))
    (if (treebank--fill-word word rows t)
        (treebank--tree-render)
      (message "The corpus does not attest %s" form))))

(defun treebank-tree-fill-all ()
  "Fill every token the corpus knows unambiguously, in one pass.

THE AMBIGUOUS ARE LEFT ALONE and counted, so that a reader knows how many
words are still theirs to decide.  `f' on each of those asks."
  (interactive)
  (let* ((words treebank--tree)
         (forms (delq nil (mapcar (lambda (word)
                                    (let ((form (plist-get word :form)))
                                      (and form (not (string-empty-p form))
                                           form)))
                                  words)))
         (table (treebank--forms-in-corpus forms))
         (filled 0)
         (left 0))
    (dolist (word words)
      (let ((rows (treebank--rows-for (or (plist-get word :form) "")
                                          table)))
        (cond
         ((treebank--fill-word word rows nil) (setq filled (1+ filled)))
         (rows (setq left (1+ left))))))
    (treebank--tree-render)
    (message "%d filled, %d ambiguous and left to you" filled left)))

(defun treebank--analysis-postag (analysis)
  "ANALYSIS, as Diogenes\=' parser writes it, as an ALDT postag.

THE PART OF SPEECH IS INFERRED, there being none in the string: Diogenes
writes `1st sg pres subj act\=' or `fem gen sg\=' and leaves the class to be read
off the categories.  A mood or a person makes it a verb; a case without one
makes it a noun, which is a guess between a noun, an adjective and a pronoun
and is the commonest of the three; anything else is left open.

`t\=' in the editor sets the postag by hand, which is what a reader does when
this guesses an adjective into a noun -- and the guess is worth making, the
alternative being nine dashes."
  (let* ((words (split-string (or analysis "") " " t))
         (verbal '("ind" "subj" "opt" "inf" "imperat" "part"
                   "1st" "2nd" "3rd"))
         (nominal '("nom" "gen" "dat" "acc" "voc"))
         (pos (cond ((seq-intersection words verbal) "verb")
                    ((seq-intersection words nominal) "noun")
                    (t ""))))
    (treebank--postag pos analysis)))

(defun treebank-tree-parse ()
  "Parse the token at point with Diogenes, and choose among its analyses.

FOR THE WORDS THE CORPUS HAS NOT GOT.  Diorisis is 820 texts, and a reader
annotating Galen or a papyrus meets forms it never saw; Diogenes knows the
whole word list and every form Morpheus makes of it.

THE ANALYSES ARE THE PROMPT.  This used to open Diogenes\=' dictionary buffer
and then ask for a lemma -- two windows, and the reader answering a question
about what they had just been shown somewhere else.  `diogenes--parse-word\='
hands back the analyses as data: the headword, what it means, and the
morphology.  So they are the candidates, and choosing one sets the lemma AND
the postag, as `f\=' does from the corpus.

The translation is shown because it is what tells two homographs apart:
`le/gw\=' to say from `le/gw\=' to gather is a question about meaning and not
about morphology."
  (interactive)
  (let* ((word (treebank--tree-at))
         (form (or (plist-get word :form) "")))
    (when (string-empty-p form) (user-error "No word here"))
    (unless (or (fboundp 'classicist--parse-word)
                (fboundp 'diogenes--parse-word))
      (user-error "Diogenes\' parser is not available"))
    (let* ((parsed (car (ignore-errors
                          (funcall (if (fboundp 'classicist--parse-word)
                                       'classicist--parse-word
                                     'diogenes--parse-word)
                                   form "greek"))))
           (labels
            (mapcar
             (lambda (entry)
               ;; (HEADWORD LEMMA NUMBER TRANSLATION ANALYSIS)
               (let ((headword (or (nth 0 entry) ""))
                     (translation (or (nth 3 entry) ""))
                     (analysis (or (nth 4 entry) "")))
                 (cons (format "%-16s %-34s %s"
                               headword
                               (if (> (length translation) 32)
                                   (concat (substring translation 0 32) "...")
                                 translation)
                               analysis)
                       entry)))
             parsed)))
      (unless labels
        (user-error "Diogenes cannot parse %s" form))
      (let ((chosen (cdr (assoc (completing-read
                                 (format "%s is: " form)
                                 labels nil t)
                                labels))))
        (when chosen
          (plist-put word :lemma (nth 0 chosen))
          (plist-put word :postag
                     (treebank--analysis-postag (nth 4 chosen)))
          (treebank--tree-render))))))

(defun treebank-tree-set-head ()
  "Set the head of the token at point."
  (interactive)
  (let ((word (treebank--tree-at)))
    (plist-put word :head (treebank--read-head word))
    (treebank--tree-render)))

(defun treebank--read-relation (word)
  "Read a relation for WORD, with what each one means beside it."
  (let* ((names (mapcar #'car diorisis-relations))
         (completion-extra-properties
          (list :annotation-function
                (lambda (candidate)
                  ;; THE SUFFIXES TOO: `ATR_CO' is `ATR' in a coordination,
                  ;; and a reader who types one should see as much.
                  (let* ((bare (replace-regexp-in-string "_\\(CO\\|AP\\)\\'" ""
                                                        candidate))
                         (gloss (cdr (assoc bare diorisis-relations))))
                    (concat (and gloss (format "   %s" gloss))
                            (cond ((string-suffix-p "_CO" candidate)
                                   "   (a member of a coordination)")
                                  ((string-suffix-p "_AP" candidate)
                                   "   (a member of an apposition)")
                                  (""))))))))
    (string-trim
     (completing-read (format "%s stands in relation: "
                              (plist-get word :form))
                      names nil nil (plist-get word :relation)))))

(defun treebank-tree-set-relation ()
  "Set the relation of the token at point."
  (interactive)
  (let ((word (treebank--tree-at)))
    (plist-put word :relation (treebank--read-relation word))
    (treebank--tree-render)))

(defun treebank-tree-set-postag ()
  "Set the postag of the token at point, reading the features by name."
  (interactive)
  (let* ((word (treebank--tree-at))
         (features (diorisis-read-morphology
                    (format "%s is (e.g. verb,aor,part): "
                            (plist-get word :form))))
         (postag (treebank--postag
                  (car (split-string features " " t))
                  (string-join (cdr (split-string features " " t)) " "))))
    (plist-put word :postag postag)
    (treebank--tree-render)
    ;; SAID BACK AS WORDS AND AS THE CODE.  A reader who has just typed
    ;; `verb,aor,part' wants to see that it became what they meant, and the
    ;; nine places are what the file will hold.
    (message "%s: %s  (%s)"
             (plist-get word :form)
             (string-join (treebank--postag-words postag) " ")
             postag)))

(defun treebank-tree-goto-head ()
  "Move to the head of the token at point."
  (interactive)
  (let* ((word (treebank--tree-at))
         (head (plist-get word :head)))
    (cond
     ((or (null head) (string-empty-p head)) (message "No head yet"))
     ((equal head "0") (message "This is the root"))
     (t (let ((found (save-excursion
                       (goto-char (point-min))
                       (let ((where nil))
                         (while (and (not where) (not (eobp)))
                           (let ((here (get-text-property
                                        (point) 'tei-diorisis-word)))
                             (when (and here (equal (plist-get here :id) head))
                               (setq where (point))))
                           (forward-line 1))
                         where))))
          (if found (goto-char found) (message "Head %s is not here" head)))))))

(defun treebank-tree-save ()
  "Write this tree back to its file.

SAVED WITH ITS FAULTS, and told about them.  A tree half annotated is the
normal state of one being annotated, and a save that refused until the tree
were finished would mean losing an hour's work to a missing root."
  (interactive)
  (unless treebank--tree-file (user-error "This tree has no file"))
  (treebank--aldt-write treebank--tree-file
                            treebank--tree-sentence
                            treebank--tree)
  ;; RECORDED, so that the hit it came from is marked in the results, `A' on
  ;; that hit opens this tree rather than starting another, and the work can
  ;; be asked what has been annotated of it.
  ;;
  ;; FROM THE SENTENCE'S OWN ATTRIBUTES and not from the file's name.  The
  ;; name was parsed for its three pieces, which worked for a sentence of the
  ;; corpus and lost the citation of a region -- `1.19.5' becoming `1_19_5'
  ;; on the way into a file name, and a list of annotations reading the worse
  ;; for it.  The `document_id' carries the author and the work, the `subdoc'
  ;; the citation, and both were written by whichever command made the tree.
  (let* ((sentence treebank--tree-sentence)
         (urn (or (plist-get sentence :document-id) ""))
         (where (or (plist-get sentence :subdoc) ""))
         (numbers (and (string-match
                        "tlg\\([0-9a-z]+\\)\\.tlg\\([0-9a-z]+\\)" urn)
                       (list (match-string 1 urn) (match-string 2 urn))))
         (parts (split-string (file-name-base treebank--tree-file) "-"))
         (author (or (nth 0 numbers) (nth 0 parts)))
         (work (or (nth 1 numbers) (nth 1 parts))))
    (when (and author work)
      (treebank--record-annotation
       author work
       (if (string-empty-p where) (or (nth 2 parts) "") where)
       treebank--tree-file
       ;; A REGION HAS NO SENTENCE NUMBER, its citation being the edition's;
       ;; a sentence of the corpus is numbered, and that is the difference
       ;; the index keeps.
       (if (string-match-p "\\`[0-9]+\\'" (or (nth 2 parts) ""))
           'corpus 'region))))
  ;; WHAT WE WROTE, so that the watch does not read our own save back.
  (setq treebank--tree-written
        (treebank--tree-stamp treebank--tree-file))
  (set-buffer-modified-p nil)
  (let ((problems (treebank--tree-problems treebank--tree)))
    (message "Wrote %s%s" treebank--tree-file
             (if problems
                 (format " -- %d thing%s still wrong" (length problems)
                         (if (= (length problems) 1) "" "s"))
               ""))))

(defun treebank-tree-browse ()
  "Open this tree in whatever draws treebanks in a browser.

THE GRAPH IS SOMEBODY ELSE'S JOB.  `treebank-react' and the Arethusa widget
draw it well and want a browser engine; Emacs has none of its own, and an
embedded web view would be a mouse-driven interface in a window that cannot
talk to point.  So the file goes to the browser and the editing stays here."
  (interactive)
  (unless treebank--tree-file (user-error "This tree has no file"))
  (treebank-tree-save)
  (browse-url (concat "file://" treebank--tree-file)))

(transient-define-prefix treebank-tree-menu ()
  "What can be done to this tree.

WHY A MENU AT ALL.  The editor is a dozen single letters over a table, and a
reader meeting it for the first time has no way to find out what they are
except the two lines at the foot.  `?' shows them all, with what each does,
and is reachable in any state."
  ["The token at point"
   ("RET" "Attach it: head, then relation" treebank-tree-attach)
   ("h" "Its head" treebank-tree-set-head)
   ("r" "Its relation" treebank-tree-set-relation)
   ("t" "Its postag" treebank-tree-set-postag)
   ("f" "Fill it from the corpus" treebank-tree-fill)
   ("L" "Set its lemma, finding it by name" treebank-tree-set-lemma)
   ("P" "Parse it with Diogenes" treebank-tree-parse)
   ("0" "Make it the root" treebank-tree-set-root)
   ("x" "Forget both" treebank-tree-unattach)]
  ["Moving"
   ("n" "The next token" treebank-tree-next)
   ("p" "The one before" treebank-tree-previous)
   ("u" "Up to its head" treebank-tree-goto-head)
   ("C-c C-c" "Look this word up" diorisis-lookup-word)]
  ["Learning it"
   ("H" "How to annotate: clauses, conjunctions, punctuation"
    treebank-annotation-help)
   ("e" "What this relation is for" treebank-explain-relation)
   ("G" "The guidelines themselves" treebank-open-guidelines)]
  ["The whole sentence"
   ("F" "Fill every word the corpus knows" treebank-tree-fill-all)]
  ["The tree"
   ("d" "Draw it in characters, or hide it"
    treebank-tree-toggle-diagram)
   ("D" "Draw it as a diagram, beside (C-u to choose where)"
    treebank-tree-graph)
   ("w" "Open it in a viewer (C-u to choose which)"
    treebank-tree-widget)
   ("W" "Open it in a viewer inside Emacs" treebank-tree-widget-here)
   ("B" "Open it in a viewer in the browser"
    treebank-tree-widget-browser)
   ("s" "Write it back" treebank-tree-save)
   ("g" "Read it from the file again" treebank-tree-revert)
   ("q" "Leave it" quit-window)])

(defvar-keymap treebank-tree-mode-map
  :doc "Keys while annotating a tree."
  "RET" #'treebank-tree-attach
  "?" #'treebank-tree-menu
  "H" #'treebank-annotation-help
  "e" #'treebank-explain-relation
  "x" #'treebank-tree-unattach
  "0" #'treebank-tree-set-root
  "h" #'treebank-tree-set-head
  "r" #'treebank-tree-set-relation
  "t" #'treebank-tree-set-postag
  "f" #'treebank-tree-fill
  "L" #'treebank-tree-set-lemma
  "F" #'treebank-tree-fill-all
  "P" #'treebank-tree-parse
  "u" #'treebank-tree-goto-head
  "s" #'treebank-tree-save
  "g" #'treebank-tree-revert
  "d" #'treebank-tree-toggle-diagram
  "D" #'treebank-tree-graph
  "w" #'treebank-tree-widget
  "W" #'treebank-tree-widget-here
  "B" #'treebank-tree-widget-browser
  "G" #'treebank-tree-browse
  "C-c C-c" #'diorisis-lookup-word
  "n" #'treebank-tree-next
  "p" #'treebank-tree-previous
  "q" #'quit-window
  ;; AND EACH UNDER `C-c' as well, for the same reason as in the query
  ;; builder: a letter is evil's before it is ours, and a `C-c' key is
  ;; nobody's.
  "C-c RET" #'treebank-tree-attach
  "C-c ?" #'treebank-tree-menu
  "C-c H" #'treebank-annotation-help
  "C-c e" #'treebank-explain-relation
  "C-c x" #'treebank-tree-unattach
  "C-c 0" #'treebank-tree-set-root
  "C-c h" #'treebank-tree-set-head
  "C-c r" #'treebank-tree-set-relation
  "C-c t" #'treebank-tree-set-postag
  "C-c f" #'treebank-tree-fill
  "C-c L" #'treebank-tree-set-lemma
  "C-c F" #'treebank-tree-fill-all
  "C-c P" #'treebank-tree-parse
  "C-c u" #'treebank-tree-goto-head
  "C-c s" #'treebank-tree-save
  "C-c v" #'treebank-tree-revert
  "C-c C-d" #'treebank-tree-toggle-diagram
  "C-c D" #'treebank-tree-graph
  "C-c w" #'treebank-tree-widget
  "C-c W" #'treebank-tree-widget-here
  "C-c B" #'treebank-tree-widget-browser
  "C-c g" #'treebank-tree-browse)

(define-derived-mode treebank-tree-mode special-mode "Treebank"
  "Annotating the syntax of one sentence.

\\{treebank-tree-mode-map}"
  (setq-local truncate-lines t)
  ;; WHICH SCHEME THIS TREE IS ANNOTATED BY, in the mode line.  `Diorisis
  ;; tree\=' was wrong twice: Diorisis has no syntax and offers no annotation
  ;; -- it gives the lemma and the postag of a Greek sentence and nothing
  ;; else -- and the conventions being followed are the Ancient Greek
  ;; Dependency Treebank\='s, or the Latin Dependency Treebank\='s for a Latin
  ;; text.  The package\='s prefix stays `tei-diorisis-\=', one package keeping
  ;; one namespace; what a reader SEES should be true.
  (setq-local mode-name
              (if (eq diorisis-language 'latin) "LDT tree" "AGDT tree"))
  ;; THE COLUMNS NAMED, once, above the table rather than in it: which of
  ;; those numbers is the head was the other thing nobody could tell.
  ;; THE HEADER IS SET AT MODE START, when there is no tree to measure, so it
  ;; uses the configured widths and the columns under it may be wider.  Naming
  ;; them is what it is for; lining them up to the character is not worth a
  ;; second pass over the tokens every render.
  (setq-local header-line-format
              (format "  id  %s%s%s%s  %s"
                      (treebank--pad "form" (nth 0 treebank-tree-columns))
                      (treebank--pad "lemma" (nth 1 treebank-tree-columns))
                      (treebank--pad
                       (if (eq diorisis-postag-style 'code)
                           "postag" "morphology")
                       (nth 2 treebank-tree-columns))
                      (treebank--pad "head" 5)
                      "relation"))
  (hl-line-mode 1)
  (diorisis--evil-enter-state)
  (diorisis--evil-keys treebank-tree-mode-map))

(defun treebank-annotate (&optional hit)
  "Annotate the syntax of HIT's sentence, or of the hit at point.

The sentence is written out as ALDT if it has not been already, and opened for
annotation: its forms, lemmata and postags from the corpus, its heads and
relations to be filled in."
  (interactive)
  (let* ((hit (or hit (diorisis--hit-at)))
         (name (format "%s-%s-%s"
                       (plist-get hit :author-id)
                       (plist-get hit :work-id)
                       (plist-get hit :sentence)))
         (file (expand-file-name (concat name ".xml")
                                 treebank-directory)))
    (unless (file-exists-p file)
      (let ((treebank-format 'aldt))
        (treebank--write-treebank
         (list (list (plist-get hit :author-id)
                     (plist-get hit :work-id)
                     (plist-get hit :sentence)))
         name)))
    (treebank-open-treebank file)))

(defun treebank-open-treebank (file &optional number)
  "Annotate a sentence of FILE, NUMBER choosing which where there are several."
  (interactive "fTreebank file: ")
  (let* ((sentences (treebank--aldt-read file))
         (sentence
          (cond ((null sentences) (user-error "No sentences in %s" file))
                ((null (cdr sentences)) (car sentences))
                (number (nth (1- number) sentences))
                (t (let* ((labels
                           (mapcar (lambda (one)
                                     (cons (format "%s  %s"
                                                   (plist-get one :id)
                                                   (or (plist-get one :subdoc)
                                                       ""))
                                           one))
                                   sentences)))
                     (cdr (assoc (completing-read "Which sentence? "
                                                  labels nil t)
                                 labels))))))
         ;; NAMED FOR WHAT IT IS.  `*Diorisis tree*' said the corpus had
         ;; something to do with the syntax, which it has not.
         (buffer (get-buffer-create
                  (format "*Treebank: %s %s*"
                          (file-name-base file)
                          (or (plist-get sentence :id) "")))))
    (with-current-buffer buffer
      (treebank-tree-mode)
      (setq treebank--tree-file (expand-file-name file))
      (setq treebank--tree-sentence sentence)
      (setq treebank--tree (plist-get sentence :words))
      ;; SET IN THIS BUFFER ONLY.  `diorisis-language' is the option a
      ;; reader annotates in by default, and a tree read from a file knows
      ;; better -- `xml:lang' says which language the treebank is in.
      ;; `setq-local' does that to a defcustom without its wanting a second
      ;; declaration, which is what a `defvar-local' of the same name would
      ;; have been.
      (setq-local diorisis-language
                  (or (plist-get sentence :language) 'greek))
      ;; AND THE MODE LINE AGAIN.  It was set when the mode started, which is
      ;; before the file had been read and so before the language was known.
      (setq-local mode-name
                  (if (eq diorisis-language 'latin) "LDT tree"
                    "AGDT tree"))
      (setq treebank--tree-written
            (treebank--tree-stamp treebank--tree-file))
      (treebank--tree-render)
      (set-buffer-modified-p nil)
      (treebank--tree-watch)
      ;; THE WATCH GOES WITH THE BUFFER.  A notification held for a buffer
      ;; that has been killed is a leak, and worse, a callback into a dead
      ;; buffer every time the file is touched.
      (add-hook 'kill-buffer-hook #'treebank--tree-unwatch nil t)
      (add-hook 'kill-buffer-hook #'treebank--maybe-stop-serving
                nil t))
    (diorisis--display buffer)))

(defcustom treebank-fill-from-corpus nil
  "Whether to fill lemmata and postags from the corpus while opening a text.

NIL, AND FOR A REASON WORTH KNOWING.  Each form is looked up with `WHERE form
= ?\=', and `form\=' is not indexed -- the corpus is indexed by lemma, a lemma
being what it is for -- so every word is a pass over ten million rows.  A
sentence of twenty words is twenty passes, and a reader who marked a region
waited a minute or more for something they had not asked for.

SO IT IS DONE IN THE EDITOR INSTEAD, AND BY THE WORD.  `f\=' fills the token at
point from the corpus, `F\=' fills the whole sentence in ONE pass, and `P\='
parses the word with Diogenes and offers what it says.  The reader decides
which words are worth waiting for, which is the right way round.

Non-nil restores the old behaviour and is reasonable once
`diorisis-index-forms\=' has been run: with an index on the form a lookup
is immediate, and filling twenty of them costs nothing."
  :type 'boolean
  :group 'treebank)

(defun treebank--region-tokens (start end)
  "The words and marks between START and END, in order.

Each is (FORM . KIND), KIND being `word\\=' or `punct\\='.

THE CITATION COLUMN IS SKIPPED, by the property Diogenes puts on it -- so a
region marked across three lines of a browser gives the words of the text and
not the numbers down its left-hand side.  Line breaks and the spaces are
dropped; punctuation becomes a token of its own, as the corpus has it and as
ALDT expects."
  (let ((tokens nil))
    (save-excursion
      (goto-char start)
      (while (< (point) end)
        (cond
         ((get-text-property (point) 'diogenes-citation)
          (goto-char (or (next-single-property-change
                          (point) 'diogenes-citation nil end)
                         end)))
         ((looking-at "[[:space:]\n]+") (goto-char (match-end 0)))
         ((looking-at "[[:alpha:]\u0300-\u036f\u2019']+")
          ;; AN APOSTROPHE IS PART OF THE WORD, an elision being written with
          ;; one: `d\u2019' is a word and not a word and a mark.
          (let ((word (match-string-no-properties 0)))
            (goto-char (match-end 0))
            ;; A WORD BROKEN OVER A LINE IS ONE WORD.  An edition hyphenates
            ;; at the end of a line and Diogenes prints what the edition has,
            ;; so a region marked across the break gave `e)mpe/-', `-' and
            ;; `fuke' -- three tokens, one of them a hyphen, none of them the
            ;; word.  Where a hyphen is followed by the end of a line, it and
            ;; the break are swallowed and the letters after them belong to
            ;; the same word.
            ;;
            ;; THE CITATION COLUMN MAY SIT BETWEEN THE TWO HALVES, the next
            ;; line beginning with its number, so that is skipped as well --
            ;; the same property as above, and the reason this is a loop and
            ;; not a single look.
            (while (and (< (point) end)
                        (looking-at "-[[:space:]]*\n"))
              (goto-char (match-end 0))
              (while (and (< (point) end)
                          (or (get-text-property (point) 'diogenes-citation)
                              (looking-at "[[:space:]]+")))
                (goto-char (or (and (get-text-property (point)
                                                       'diogenes-citation)
                                    (next-single-property-change
                                     (point) 'diogenes-citation nil end))
                               (match-end 0)
                               end)))
              (when (looking-at "[[:alpha:]\u0300-\u036f\u2019']+")
                (setq word (concat word (match-string-no-properties 0)))
                (goto-char (match-end 0))))
            (push (cons word 'word) tokens)))
         ((looking-at "[[:punct:]]")
          (push (cons (match-string-no-properties 0) 'punct) tokens)
          (goto-char (match-end 0)))
         (t (forward-char 1)))))
    (nreverse tokens)))

(defun treebank--guess-token (form)
  "What the corpus knows about FORM, as (LEMMA POSTAG), or nil.

ONE LEMMA OR NOTHING.  A form the corpus attests under two lemmata is left to
the reader: the corpus itself had the sentence in front of it and a tagger to
weigh them, and this has neither.  The commonest analysis of the one lemma
fills the postag, which is a guess of the same kind the tagger made and is
marked as such by being editable."
  (when (and treebank-fill-from-corpus diorisis-database)
    (ignore-errors
      ;; EVERY SPELLING, as `f' asks: the first word of a sentence is
      ;; capitalised in the text and lower case in the lexicon, and beta code
      ;; writes the difference with an asterisk.
      (let* ((variants (treebank--form-variants form))
             (rows (diorisis--select
                    (format "SELECT lemma, pos, morph, COUNT(*)\
 FROM occurrences WHERE form IN (%s)\
 GROUP BY lemma, pos, morph ORDER BY 4 DESC"
                            (string-join (make-list (length variants) "?")
                                         ", "))
                    variants))
             (lemmata (delete-dups (mapcar (lambda (row) (nth 0 row)) rows))))
        (when (and rows (null (cdr lemmata)))
          (list (diorisis--greek (nth 0 (car rows)))
                (treebank--postag (nth 1 (car rows))
                                      (nth 2 (car rows)))))))))

(defun treebank-annotate-region (start end &optional citation)
  "Annotate the marked text as one sentence.

FOR A TEXT THAT IS NOT IN THE CORPUS.  Mark a sentence in Diogenes\\=' browser,
or in a TEI text, or anywhere, and this writes it out as a treebank sentence
and opens the editor on it: the region is the sentence, the citation comes
from the buffer where there is one, and the lemmata and postags are filled
from Diorisis where the form is unambiguous -- see
`treebank-fill-from-corpus\\='.

CITATION, given, overrides what the buffer says; asked for where the buffer
says nothing."
  (interactive "r")
  (let* ((tokens (treebank--region-tokens start end))
         (reference (and (fboundp 'classicist-browser-reference)
                         (ignore-errors (classicist-browser-reference))))
         (author (or (plist-get reference :author) "0000"))
         (work (or (plist-get reference :work) "000"))
         ;; THE CORPUS SAYS WHICH LANGUAGE.  `tlg\=' is Greek and `phi\=' the
         ;; Latin authors, so a region marked in Cicero is annotated by the
         ;; Latin Dependency Treebank\='s postag scheme without anybody being
         ;; asked -- and the file says `xml:lang="lat"\=', so it is read back
         ;; by the same scheme.  Where the buffer will not say, the option
         ;; stands.
         (corpus (plist-get reference :corpus))
         (language (cond ((equal corpus "phi") 'latin)
                         ((equal corpus "tlg") 'greek)
                         (t diorisis-language)))
         (where (or citation
                    (plist-get reference :text)
                    (read-string "Citation for this sentence: ")))
         (number 0)
         (lines nil))
    (unless tokens (user-error "No words in the region"))
    (dolist (token tokens)
      (setq number (1+ number))
      (let* ((form (car token))
             (punct (eq (cdr token) 'punct))
             (guess (unless punct (treebank--guess-token form))))
        (push (format
               "    <word id=\"%d\" form=\"%s\" lemma=\"%s\" postag=\"%s\"\
 relation=\"\" head=\"\"/>"
               number
               (treebank--xml form)
               (treebank--xml (cond (punct form)
                                        (guess (nth 0 guess))
                                        ("")))
               (cond (punct "u--------")
                     (guess (nth 1 guess))
                     ("")))
              lines)))
    (make-directory treebank-directory t)
    (let* ((name (format "%s-%s-%s" author work
                         (replace-regexp-in-string
                          "[^[:alnum:]]+" "_" (or where "1"))))
           (file (expand-file-name (concat name ".xml")
                                   treebank-directory)))
      (with-temp-file file
        (insert "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                (format "<treebank xml:lang=\"%s\" format=\"aldt\"\
 version=\"1.5\">\n"
                        (if (eq language 'latin) "la" "grc"))
                (format "  <sentence id=\"1\" document_id=\"%s\" subdoc=\"%s\"\
 span=\"\">\n"
                        (treebank--xml (treebank--cts-urn author work))
                        (treebank--xml (or where "")))
                (string-join (nreverse lines) "\n")
                "\n  </sentence>\n</treebank>\n"))
      (message "%d tokens from %s" number (or where "here"))
      (treebank-open-treebank file))))

(defcustom treebank-workbook-directory
  (expand-file-name "diorisis-workbooks/" user-emacs-directory)
  "Where exported workbooks are written."
  :type 'directory
  :group 'treebank)

(defcustom treebank-workbook-analyses nil
  "Whether a workbook shows each form's lemma and analysis by default.

Nil for a handout, which wants the Greek and the reference and nothing else.
Non-nil for a gloss list or an appendix, where the morphology is the point.  A
prefix argument to `treebank-workbook-export' gives the other one, so a
handout and a gloss list are one collection exported twice."
  :type 'boolean
  :group 'treebank)

(defcustom treebank-workbook-emphasis 'bold
  "How the word searched for is marked in the workbook.

`bold' or `italic' -- Org's own emphasis, which survives into every format it
exports to.  Nil leaves the sentence plain, for a workbook that someone else
will typeset."
  :type '(choice (const :tag "Bold" bold) (const :tag "Italic" italic)
                 (const :tag "Unmarked" nil))
  :group 'treebank)

(defvar treebank--collection nil
  "The hits collected for a workbook, in the order they were collected.")

(defun treebank-collect (&optional hit)
  "Add HIT, or the hit at point, to the workbook."
  (interactive)
  (let ((hit (or hit (diorisis--hit-at))))
    ;; ONE SENTENCE, ONCE.  A sentence with two occurrences of the word gives
    ;; two hits and one example, and collecting it twice would print it twice.
    (unless (seq-find (lambda (one)
                        (and (equal (plist-get one :author-id)
                                    (plist-get hit :author-id))
                             (equal (plist-get one :work-id)
                                    (plist-get hit :work-id))
                             (equal (plist-get one :sentence)
                                    (plist-get hit :sentence))))
                      treebank--collection)
      (setq treebank--collection
            (append treebank--collection (list hit))))
    (message "%d in the workbook" (length treebank--collection))))

(defun treebank-collect-all ()
  "Add every hit in this buffer to the workbook."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (let ((hit (get-text-property (point) 'tei-diorisis-hit)))
        (when hit (treebank-collect hit)))
      (forward-line 1))
    (message "%d in the workbook" (length treebank--collection))))

(defun treebank-workbook-clear ()
  "Empty the workbook."
  (interactive)
  (when (or (null treebank--collection)
            (y-or-n-p (format "Forget %d collected sentences? "
                              (length treebank--collection))))
    (setq treebank--collection nil)
    ;; REWRITTEN WHERE IT IS.  `treebank-workbook' both writes the buffer
    ;; and shows it, and showing a buffer that is already in a window opened
    ;; a second window onto it.  The display is left to whoever opened it;
    ;; this only redraws what is there.
    (let ((buffer (get-buffer "*Diorisis workbook*")))
      (when buffer
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (propertize "The workbook is empty.\n\n" 'face 'bold))
            (insert "`c\=' on a hit collects it, `C\=' collects them all.\n")))))
    (message "The workbook is empty")))

(defun treebank--workbook-link (hit)
  "A `diogenes:' link to HIT's passage, or plain text where there is none.

THE SAME STRING `diogenes-org--store-passage' WRITES: the type, then
`passage', the corpus, the author, the work, and the citation with a stop
between every level.  Built here rather than asked for, that function reading
a browser buffer and there being none.

The work is the TLG's number where ours differs -- see
`diorisis--work-number' -- a link being followed by Diogenes, which knows
the TLG's."
  (let* ((levels (diorisis--levels (plist-get hit :location)))
         (key (and levels (string-join levels ".")))
         (shown (format "%s, %s %s"
                        (or (plist-get hit :author) "?")
                        (or (plist-get hit :work) "?")
                        (diorisis--citation-string hit))))
    (if key
        (format "[[diogenes:passage:%s:%s:%s:%s][%s]]"
                diorisis-corpus
                (plist-get hit :author-id)
                (diorisis--work-number hit)
                key shown)
      shown)))

(defun treebank--workbook-lemma (hit)
  "A `diogenes:' link to HIT's lemma in the dictionary."
  (let ((lemma (diorisis--lemma-for-lookup (plist-get hit :lemma))))
    (if (string-empty-p lemma)
        ""
      (format "[[diogenes:entry:greek:%s][%s]]"
              lemma (diorisis--greek lemma)))))

(defun treebank--workbook-sentence (hit)
  "HIT's sentence in Greek, with the form marked as Org marks emphasis."
  (let* ((words (plist-get hit :words))
         (text (diorisis--greek (or words "")))
         (form (diorisis--greek (or (plist-get hit :form) "")))
         (mark (pcase treebank-workbook-emphasis
                 ('bold "*") ('italic "/") (_ nil))))
    (cond
     ((string-empty-p text) "[the corpus keeps no sentence here]")
     ((or (null mark) (string-empty-p form)) text)
     ;; ORG'S EMPHASIS IS FRAGILE ABOUT ITS EDGES -- a marker has to sit next
     ;; to a word character -- so a form actually found in the sentence is
     ;; wrapped, and a form not found is left alone rather than marked at a
     ;; guess.
     ((string-search form text)
      (replace-regexp-in-string (regexp-quote form)
                                (concat mark form mark) text t t))
     (t text))))

(defun treebank-workbook ()
  "Show what is in the workbook."
  (interactive)
  (let ((buffer (get-buffer-create "*Diorisis workbook*"))
        (collection treebank--collection))
    (with-current-buffer buffer
      (treebank-workbook-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "%d sentence%s collected\n\n"
                                    (length collection)
                                    (if (= (length collection) 1) "" "s"))
                            'face 'bold))
        (if (null collection)
            (insert "  Nothing yet: `c' on a hit collects it, `C' collects\n"
                    "  every hit in the buffer.\n")
          (let ((number 0))
            (dolist (hit collection)
              (setq number (1+ number))
              (let ((start (point)))
                (insert (format "%3d. %s, %s %s\n     %s\n\n"
                                number
                                (or (plist-get hit :author) "?")
                                (or (plist-get hit :work) "?")
                                (diorisis--citation-string hit)
                                (let ((text (diorisis--greek
                                             (or (plist-get hit :words) ""))))
                                  (if (> (length text) 110)
                                      (concat (substring text 0 110) " ...")
                                    text))))
                (put-text-property start (point) 'tei-diorisis-hit hit)))))
        (insert (propertize
                 "\ne exports it as Org - d deletes one - k empties it - q quits\n"
                 'face 'shadow))
        (goto-char (point-min))))
    (diorisis--display buffer t)))

(defun treebank-workbook-delete ()
  "Take the sentence at point out of the workbook."
  (interactive)
  (let ((hit (diorisis--hit-at)))
    (setq treebank--collection (delq hit treebank--collection))
    (treebank-workbook)))

(defun treebank--workbook-header (name analyses)
  "The head of an exported workbook: NAME, and how to use the file.

THE INSTRUCTIONS TRAVEL WITH IT.  A file that has to be explained elsewhere is
a file whose instructions are lost by the time anybody opens it -- so the
export keys, the font, the links and the lookup are all written into the
document, under a heading marked `:noexport:' so that none of it reaches the
handout."
  (concat
   "#+title: " name "\n"
   "#+date: " (format-time-string "%F") "\n"
   "#+options: toc:nil\n"
   ;; THE GREEK FONT, NAMED FOR LaTeX.  The default `pdflatex' cannot set
   ;; polytonic Greek at all; `lualatex' with these two lines can, and a
   ;; reader exporting without them gets a page of errors and no Greek.
   "#+latex_compiler: lualatex\n"
   "#+latex_header: \\usepackage{fontspec}\n"
   "#+latex_header: \\setmainfont{GFS Porson}\n"
   "\n* How to use this file        :noexport:\n"
   "\nWritten by tei-diorisis from a Diorisis search.  The sentences are\n"
   "below, numbered, with their references.\n"
   "\n** Making something of it\n"
   "\n- a PDF :: =C-c C-e l p=.  It wants lualatex, which the header asks\n"
   "  for, and a Greek font: change =\\setmainfont= if you have not got GFS\n"
   "  Porson.\n"
   "- a Word document :: =C-c C-e o o= for ODT, which Word opens; or\n"
   "  =pandoc -o handout.docx thisfile.org=.  Pandoc takes\n"
   "  =--reference-doc=mystyle.docx= to carry a Greek font across.\n"
   "- HTML, Markdown, plain text :: =C-c C-e= and the letter for it.  Org\n"
   "  does all of them with nothing else installed.\n"
   "- LaTeX for a paper :: =C-c C-e l b= writes the body without a preamble.\n"
   "\n** The references are links\n"
   "\nEach is a =diogenes:= link: =C-c C-o= on one opens the passage in\n"
   "Diogenes' browser, at that line.  On export it flattens to its text, so\n"
   "a handout reads `Aelian, De natura animalium 1.19.5' and nothing of\n"
   "Emacs shows.\n"
   (if analyses
       "Each lemma is a link too, and opens its LSJ article.\n" "")
   "\n** Looking a word up in here\n"
   "\n=C-c w= on any Greek word looks it up: the corpus' own lemma where\n"
   "Diorisis knows the form, and Diogenes' parser where it does not.  The\n"
   "key belongs to =tei-diorisis-collection-mode=, which =M-x= turns on --\n"
   "the export turns it on for you when it opens the file.\n"
   "\n** Editing it\n"
   "\nFreely: it is your file.  Add a remark under a sentence, reorder them,\n"
   "cut what you do not want.  The collection is still in Emacs, so\n"
   "exporting again gives the list back as it was: this file is the handout\n"
   "and not the record.\n"
   (if analyses
       "\nExported WITH the analyses; =C-u= on the export gives the other.\n"
     "\nExported without the analyses, for a handout; =C-u= on the export\nadds them.\n")
   "\n* Sentences\n\n"))

(defun treebank-workbook-export (&optional other)
  "Write the workbook as an Org file, and open it.

OTHER, the prefix argument, takes the other answer to
`treebank-workbook-analyses': a handout and a gloss list are the same
collection exported twice."
  (interactive "P")
  (unless treebank--collection (user-error "The workbook is empty"))
  (let* ((analyses (if other (not treebank-workbook-analyses)
                     treebank-workbook-analyses))
         (name (read-string "Name this workbook: " "workbook"))
         (file (expand-file-name
                (concat (replace-regexp-in-string "[^[:alnum:]._-]+" "-" name)
                        ".org")
                treebank-workbook-directory))
         (number 0))
    (make-directory treebank-workbook-directory t)
    (with-temp-file file
      (insert (treebank--workbook-header name analyses))
      (dolist (hit treebank--collection)
        (setq number (1+ number))
        (insert (format "%d. %s\n   %s\n" number
                        (treebank--workbook-sentence hit)
                        (treebank--workbook-link hit)))
        (when analyses
          (insert (format "   - lemma :: %s\n"
                          (treebank--workbook-lemma hit)))
          (insert (format "   - form :: %s\n"
                          (diorisis--greek
                           (or (plist-get hit :form) ""))))
          (let ((morph (plist-get hit :morph)))
            (when morph
              (insert (format "   - analysis :: %s\n"
                              (string-join
                               (split-string morph " *| *" t) "; ")))))
          (let ((date (diorisis--year (plist-get hit :date))))
            (when date (insert (format "   - date :: %s\n" date)))))
        (insert "\n")))
    (message "%d sentences to %s" number file)
    (find-file file)
    (treebank-collection-mode 1)))

(defvar-keymap treebank-workbook-mode-map
  :doc "Keys in the workbook."
  "e" #'treebank-workbook-export
  "d" #'treebank-workbook-delete
  "k" #'treebank-workbook-clear
  "q" #'quit-window
  "C-c e" #'treebank-workbook-export
  "C-c C-d" #'treebank-workbook-delete
  "C-c k" #'treebank-workbook-clear)

(define-derived-mode treebank-workbook-mode special-mode
  "Diorisis workbook"
  "The sentences collected for a handout or a gloss list.

\\{treebank-workbook-mode-map}"
  (setq-local truncate-lines nil)
  (visual-line-mode 1)
  (diorisis--evil-enter-state)
  (diorisis--evil-keys treebank-workbook-mode-map))

(defvar-keymap treebank-collection-mode-map
  :doc "Keys in an exported workbook.

`C-c w' AND NOT `C-c C-c'.  An exported workbook is an Org buffer and
`C-c C-c' is Org's most important key -- it acts on whatever point is in --
so a mode that took it would break the file it is meant to help with.
`C-c w' Org leaves free."
  "C-c w" #'diorisis-lookup-word)

(define-minor-mode treebank-collection-mode
  "Look Greek words up in an exported workbook.

`C-c w' on a word: the corpus' own lemma where Diorisis knows the form, and
Diogenes' parser where it does not.  Nothing else changes -- the buffer is an
ordinary Org buffer and every Org key does what it always did."
  :lighter " Diorisis"
  :keymap treebank-collection-mode-map)

(defvar treebank--annotations nil
  "Sentences that have trees: (STAMP . HASH), the hash from a key to a file.")

(defun treebank--annotation-index ()
  "Where the record of annotated sentences is kept."
  (expand-file-name "annotations.tsv" treebank-directory))

(defun treebank--annotation-key (author work sentence)
  "The key a sentence is recorded under."
  (format "%s-%s-%s" author work sentence))

(defun treebank-annotations ()
  "Every annotated sentence, as a list of plists.

Each is :key, :file, :author, :work, :where and :kind -- `corpus' for a
sentence of Diorisis and `region' for a stretch marked in a text that is not
in it.

REREAD WHEN THE FILE CHANGES and not oftener: this is consulted once per hit
while the results are printed, and a file read two hundred times would be
felt.

THE OLD TWO-COLUMN LINES ARE STILL READ.  The index used to hold a key and a
file and nothing else -- enough to mark a hit, and not enough to answer `what
have I annotated of this work', the author and the work being buried in the
key.  A line of two fields is taken as before and its pieces read out of the
key."
  (let* ((file (treebank--annotation-index))
         (stamp (and (file-readable-p file)
                     (float-time (file-attribute-modification-time
                                  (file-attributes file))))))
    (unless (and treebank--annotations
                 (equal (car treebank--annotations) stamp))
      (let ((all nil))
        (when stamp
          (ignore-errors
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (while (not (eobp))
                (let* ((line (buffer-substring-no-properties
                              (point) (line-end-position)))
                       (fields (and (not (string-prefix-p "#" line))
                                    (split-string line "\t"))))
                  (cond
                   ((>= (length fields) 6)
                    (push (list :key (nth 0 fields) :file (nth 1 fields)
                                :author (nth 2 fields) :work (nth 3 fields)
                                :where (nth 4 fields)
                                :kind (intern (nth 5 fields)))
                          all))
                   ((= (length fields) 2)
                    (let ((parts (split-string (nth 0 fields) "-")))
                      (push (list :key (nth 0 fields) :file (nth 1 fields)
                                  :author (or (nth 0 parts) "")
                                  :work (or (nth 1 parts) "")
                                  :where (or (nth 2 parts) "")
                                  :kind 'corpus)
                            all)))))
                (forward-line 1)))))
        (setq treebank--annotations (cons stamp (nreverse all)))))
    (cdr treebank--annotations)))

(defun treebank--write-annotations (all)
  "Write ALL to the index."
  (condition-case error
      (progn
        (make-directory treebank-directory t)
        (with-temp-file (treebank--annotation-index)
          (insert "# tei-diorisis annotations 2\t"
                  "key\tfile\tauthor\twork\twhere\tkind\n")
          (dolist (one all)
            (insert (string-join
                     (list (or (plist-get one :key) "")
                           (or (plist-get one :file) "")
                           (or (plist-get one :author) "")
                           (or (plist-get one :work) "")
                           (or (plist-get one :where) "")
                           (format "%s" (or (plist-get one :kind) 'corpus)))
                     "\t")
                    "\n"))))
    (error (message "Could not write the annotation index: %s"
                    (error-message-string error))))
  (setq treebank--annotations nil))

(defun treebank--record-annotation (author work where file &optional kind)
  "Record that AUTHOR WORK at WHERE is annotated in FILE.

REWRITTEN RATHER THAN APPENDED TO, so that a sentence annotated twice appears
once: the file is a few hundred lines and rewriting it is cheaper than reading
it back to find out whether appending would duplicate."
  (when (and author work file)
    (let* ((key (treebank--annotation-key author work where))
           (kept (seq-remove (lambda (one)
                               (equal (plist-get one :key) key))
                             (treebank-annotations))))
      (treebank--write-annotations
       (append kept
               (list (list :key key :file file :author author :work work
                           :where (or where "") :kind (or kind 'corpus))))))))

(defun treebank-annotation-for (hit)
  "The file HIT's sentence is annotated in, or nil."
  (let ((key (treebank--annotation-key (plist-get hit :author-id)
                                           (plist-get hit :work-id)
                                           (plist-get hit :sentence))))
    (plist-get (seq-find (lambda (one) (equal (plist-get one :key) key))
                         (treebank-annotations))
               :file)))

(defun treebank--work-said (author work)
  "AUTHOR and WORK as a reader would name them, or their numbers.

ASKED OF THE CORPUS AND NOT REQUIRED OF IT.  A tree taken from a text
Diorisis does not have -- which is what `treebank-annotate-region' is
for -- has an author and a work the corpus cannot name, and the numbers are
then what there is.  Diogenes could name them; asking it would mean loading
it to read a list."
  (let ((named (ignore-errors
                 (car (diorisis--select
                       "SELECT author, work FROM texts\
 WHERE author_id = ? AND work_id = ?"
                       (list author work))))))
    (if named
        (format "%s, %s" (nth 0 named) (nth 1 named))
      (format "%s %s" author work))))

(defun treebank--annotation-labels (all)
  "ALL as an alist of (LABEL . PLIST), newest citation last.

Sorted by author, work and then by where in the work: a list of annotations
is read as a table of contents, and a table of contents is in the order of
the text."
  (mapcar
   (lambda (one)
     (cons (format "%-34s %-14s %s"
                   (treebank--work-said (plist-get one :author)
                                            (plist-get one :work))
                   (or (plist-get one :where) "")
                   (if (eq (plist-get one :kind) 'region) "(a region)" ""))
           one))
   (sort (copy-sequence all)
         (lambda (a b)
           (let ((one (format "%s %s %s" (plist-get a :author)
                              (plist-get a :work) (plist-get a :where)))
                 (two (format "%s %s %s" (plist-get b :author)
                              (plist-get b :work) (plist-get b :where))))
             (string-lessp one two))))))

(defun treebank-list-annotations (&optional all)
  "Open a tree that has been annotated, chosen from those recorded.

WHICH IS THE OTHER WAY IN.  A tree is found from its hit and a hit from a
search; this is for the reader who remembers annotating a passage and not
what they searched for to reach it -- and for the trees that came from no
search at all, a region marked in a Diogenes browser having no hit behind it.

ALL, the prefix argument, lists every work; without it the list is narrowed
to one work first, there being no use in scrolling past Aristotle to reach
Aristides."
  (interactive "P")
  (let* ((recorded (treebank-annotations)))
    (unless recorded (user-error "Nothing annotated yet"))
    (let* ((chosen-work
            (unless all
              (let ((works (delete-dups
                            (mapcar (lambda (one)
                                      (cons (treebank--work-said
                                             (plist-get one :author)
                                             (plist-get one :work))
                                            (list (plist-get one :author)
                                                  (plist-get one :work))))
                                    recorded))))
                (if (null (cdr works))
                    (cdr (car works))
                  (cdr (assoc (completing-read "Annotations of which work? "
                                               works nil t)
                              works))))))
           (shown (if chosen-work
                      (seq-filter
                       (lambda (one)
                         (and (equal (plist-get one :author)
                                     (nth 0 chosen-work))
                              (equal (plist-get one :work)
                                     (nth 1 chosen-work))))
                       recorded)
                    recorded))
           (labels (treebank--annotation-labels shown)))
      (treebank-open-treebank
       (plist-get (cdr (assoc (completing-read
                               (format "Open which of the %d? " (length labels))
                               labels nil t)
                              labels))
                  :file)))))

(defun treebank-annotations-here ()
  "List what has been annotated of the work this buffer is showing.

FROM A BROWSER OR A READER, and asking the buffer rather than the reader:
`classicist-browser-reference' says which work a Diogenes browser has open, and
our own text reader knows its own.  So a reader looking at Plato can see
what of Plato they have annotated without naming it."
  (interactive)
  (let* ((reference (and (fboundp 'classicist-browser-reference)
                         (ignore-errors (classicist-browser-reference))))
         (author (or (plist-get reference :author)
                     (bound-and-true-p tei-diorisis--author)))
         (work (or (plist-get reference :work)
                   (bound-and-true-p tei-diorisis--work))))
    (unless (and author work)
      (user-error "This buffer does not say which work it is showing"))
    (let* ((shown (seq-filter (lambda (one)
                                (and (equal (plist-get one :author) author)
                                     (equal (plist-get one :work) work)))
                              (treebank-annotations)))
           (labels (treebank--annotation-labels shown)))
      (unless labels
        (user-error "Nothing annotated of %s"
                    (treebank--work-said author work)))
      (treebank-open-treebank
       (plist-get (cdr (assoc (completing-read
                               (format "%d annotated here: "
                                       (length labels))
                               labels nil t)
                              labels))
                  :file)))))

;; NAMEABLE BEFORE THIS FILE LOADS, because diorisis.el names it in a menu
;; append that runs on a fresh Emacs.  NOT with a cookie: that copies the
;; whole macro call into the autoloads, where transient-define-prefix is
;; itself undefined and the file cannot be read at all -- void, at the
;; next doom sync.
;;
;; The cookie below declares the autoload without copying the form, which
;; is what a macro-defined command wants.
;;;###autoload (autoload 'treebank-annotations-menu "treebank" nil t)
(transient-define-prefix treebank-annotations-menu ()
  "The trees that have been annotated, and the ways to make another.

WHY A MENU.  The annotations were reachable three ways and none of them
obvious: `L' inside the search transient, which is where one goes to search
and not to read; `M-x' for the rest; and `A' on a hit, which only exists
where there is a hit.  A tree annotated from a Diogenes browser had no hit
behind it and so no way back to it but the file system.

This is that way back, and it asks the buffer where it can: `here' works in a
Diogenes browser or in the Diorisis reader without being told which work is
open."
  ["Open a tree"
   ("o" "By work, then passage" treebank-list-annotations)
   ("a" "Every work at once"
    (lambda () (interactive) (treebank-list-annotations t)))
   ("h" "Annotated of the work in this buffer"
    treebank-annotations-here)
   ("f" "By file name" treebank-open-treebank)]
  ["Make one"
   ("r" "Annotate the marked region" treebank-annotate-region)
   ("s" "Annotate the hit at point" treebank-annotate)]
  ["Where they are"
   ("d" "Open the treebank directory"
    (lambda () (interactive) (dired treebank-directory)))
   ("i" "Show the annotation index"
    (lambda () (interactive)
      (find-file (treebank--annotation-index))))])

(defun treebank-install-results-keys ()
  "Bind the treebank keys in the Diorisis results buffer.
Called at load, and again after `classicist-features' changes so that a
reader who turns the treebank on need not restart.

IN THE CORPUS BUFFER, because that is where a reader is when they want a tree:
looking at a hit.  Which makes these the second of this package's five
seams, and the reason they are installed by a function rather than written
into `diorisis-results-mode-map''s own definition -- a `defvar-keymap' is
a literal and cannot ask whether the treebank is wanted.

Modelled on `classicist-browser-install-mouse-keys', which is
`interactive' and asks `boundp' for the same reasons."
  (interactive)
  (when (and (boundp 'diorisis-results-mode-map)
             (or (not (fboundp 'classicist-feature-p))
                 (classicist-feature-p 'treebank)))
    (dolist (cell '(("T" . treebank-export-sentence)
                    ("A" . treebank-annotate)
                    ("c" . treebank-collect)
                    ("C" . treebank-collect-all)
                    ("b" . treebank-workbook)
                    ("C-c C-t" . treebank-export-hits)))
      (keymap-set diorisis-results-mode-map (car cell) (cdr cell)))))

;; AT LOAD, and after the corpus has made its keymap.
(with-eval-after-load 'diorisis (treebank-install-results-keys))

(provide 'treebank)

;;; treebank.el ends here
