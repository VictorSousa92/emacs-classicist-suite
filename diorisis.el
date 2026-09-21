;;; diorisis.el --- the Diorisis corpus: search and reading -*- lexical-binding: t; -*-

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

;; THE CORPUS, AND NOT THE TREEBANK.  The database, the query
;; a transient builds, the hit list, reading a text at a hit,
;; and the searches kept.
;;
;; `treebank.el' annotates what is found here and requires this
;; file.  The few names below go the other way and are declared,
;; each of them reached at a keypress.

;;; Code:

(require 'seq)

(require 'subr-x)

(require 'cl-lib)

(require 'ucs-normalize)

(require 'transient)

(require 'text-property-search)

;; THE SUITE FEATURE LIST, if this file is part of a suite at all.
;; Declared and not required: this file stands alone -- absent the suite the
;; guards fall back to what they did before, which is why the one in the
;; autoloaded form asks fboundp first.
(declare-function classicist-feature-p "classicist-groups" (feature))

(declare-function diogenes--beta-to-utf8 "diogenes-utils" (str))

(declare-function diogenes--utf8-to-beta "diogenes-utils" (str))

(declare-function classicist-open-passage "classicist-browser"
                  (corpus author work &optional passage))

(declare-function classicist-lookup-greek "classicist" (word &optional dictionary))

(declare-function classicist-parse-and-lookup-greek "classicist" (word &optional dictionary))

(declare-function classicist-display-buffer "classicist-windows" t)

(defvar diorisisrowser-mouse-keys)

(defgroup diorisis nil
  "Searching the Diorisis corpus of lemmatised Greek.

Its own group and not a child of `tei\\=', so that this file stands alone: a
reader who wants the search and not the TEI reader loads one file, and the
group exists whichever loaded first."
  :group 'tools
  :prefix "diorisis-")

(defcustom diorisis-database nil
  "Where `diorisis.db\\=' is, or nil for none.

    (setq diorisis-database
          \"/mnt/archive/Diogenes Data/Diorisis/diorisis.db\")

Written by `diorisis-index.py\\=', which is in this repository beside this
file:

    python3 diorisis-index.py CORPUS --catalogue catalog.tsv

Nothing here works until it is set, and everything says so rather than failing
obscurely."
  :type '(choice (const :tag "None" nil) file)
  :group 'diorisis)

(defcustom diorisis-corpus "tlg"
  "Which Diogenes corpus the numbers in the database belong to.

The TLG, and there is no other answer: Diorisis is Greek literary texts filed
under the TLG's own author and work numbers, which is what lets a hit be
opened in Diogenes' browser.  A defcustom rather than a constant because
`classicist-open-passage\\=' takes the corpus as an argument and a reader with a
custom corpus of the same texts may want to say so."
  :type 'string
  :group 'diorisis)

(defcustom diorisis-open-with '(diogenes diorisis)
  "Where a hit opens, tried in order.

`diogenes' is the browser: the real text, in the edition, with the paging and
the printed page and everything else the browser can do.  It wants the CD-ROM
databases, which not every reader has -- and a reader without them was until
now offered a link that could not lead anywhere.

`diorisis' is this corpus read out of the index: the sentences as the corpus
tokenised them, no edition and no line breaks, but the passage, and every text
Diorisis holds whether the CDs have it or not.  See
`diorisis-open-work'.

BOTH, IN THAT ORDER, by default, and the second is reached in two ways -- by
Diogenes not being installed, and by its failing to open the passage.  Put
`diorisis' first to read here always; leave one out to have only the other."
  :type '(repeat (choice (const :tag "Diogenes' browser" diogenes)
                         (const :tag "The Diorisis text" diorisis)))
  :group 'diorisis)

(defcustom diorisis-limit 200
  "How many hits to fetch at once.

The whole count is always reported -- `4218 hits, showing 200' -- so a limit
does not hide how common a word is.  `+\\=' in the results buffer doubles it and
searches again, which is cheaper than reading four thousand sentences nobody
asked for."
  :type 'integer
  :group 'diorisis)

(defcustom diorisis-snippet-width 150
  "How much of a sentence to show against a hit, in characters.

A window around the hit rather than the head of the sentence: some sentences
in the corpus run to three hundred characters and the word searched for may be
anywhere in them, so showing the beginning would often not show the word."
  :type 'integer
  :group 'diorisis)

(defcustom diorisis-lookup-from 'lemma
  "Where a lookup of a word in a snippet starts.

`lemma' asks the CORPUS.  Every token in Diorisis is lemmatised, so the word
under point has an answer recorded against it already -- and that is better
than parsing it, not merely quicker: a parser offered `memuko/tos' must guess
among the lemmata that could produce it, where the corpus has been
disambiguated and says which, with the tagger's confidence beside it.  The
lemma is also Diogenes' own string, the corpus having been lemmatised from its
word list, so the entry is reached with nothing translated in between.

`form' parses instead, as `C-c C-c' does in the browser, which is what one
wants where the corpus is doubted -- a low confidence, or an analysis that
looks wrong for the passage.

Either way the other is one prefix argument away: `C-u C-c C-c' takes the
route this is not set to."
  :type '(choice (const :tag "The lemma the corpus records" lemma)
                 (const :tag "Parse the form" form))
  :group 'diorisis)

(defcustom diorisis-show-beta-code nil
  "Whether to show the corpus's beta code as it stands, rather than Greek.

Nil converts for display, which is what a reader wants.  Non-nil is for
checking a lemma against the database, or for a session where the conversion
is not available -- it lives in Diogenes\\=' `diogenes-utils.el\\=', and without
Diogenes there is nothing to convert with and the beta code is shown either
way."
  :type 'boolean
  :group 'diorisis)

(defvar diorisis--connection nil
  "The database as last opened: (FILE . HANDLE).

KEPT OPEN between searches.  Opening is cheap and the handle is not, the first
query against a fresh handle having to read the index's root pages; and a
reader searching for one lemma after another would pay that each time.  The
file is remembered beside the handle so that changing
`diorisis-database\\=' opens the new one rather than going on quietly
answering from the old.")

(defcustom diorisis-merged-database nil
  "Where a MERGED `diorisis.db\=' is, or nil for none.

THE SAME CORPUS WITH MORE COLUMNS ON IT.  Bilby\='s DuckDB compilation of
Diorisis carries what the corpus itself does not expose -- the morphology
decomposed into a column per category, the dialect, and the prosody -- and
`tools/diorisis-merge-duckdb.py --into\=' writes those onto a COPY:

    ~/.venvs/duckdb/bin/python tools/diorisis-merge-duckdb.py \\
        ~/Downloads/diorisis.duckdb diorisis.db \\
        --into diorisis-merged.db --write

WHY BOTH AND NOT ONE.  The plain database is what the corpus publishes and
what everything here has been tested against; the merged one answers
questions the other cannot -- `tense = \='perf\=' AND mood = \='part\='\=' instead of
`morph LIKE \='%perf part%\='\=', which depends on the order of words in a string
and matches across the bar when a form has several analyses.  Keeping both
costs a gigabyte and settles nothing prematurely.

`diorisis-use-merged\=' chooses between them and
`diorisis-switch-database\=' toggles it."
  :type '(choice (const :tag "None" nil) file)
  :group 'diorisis)

(defcustom diorisis-use-merged nil
  "Whether to work with `diorisis-merged-database\=' rather than the plain one.

Nil where there is no merged database, and nil by default where there is: the
plain corpus is what this has been tested against, and a reader should meet
the extra columns because they asked for them."
  :type 'boolean
  :group 'diorisis)

(defun diorisis-switch-database ()
  "Work with the other database, and forget what was read from this one.

EVERYTHING CACHED IS FORGOTTEN, which is the whole of what makes this safe:
the lemmata, the candidates, the tagset and the text list were read from one
database and mean nothing about another -- the merged copy has the same
lemmata today and need not tomorrow.  `diorisis-close\=' does that and
closes the connection with it."
  (interactive)
  (unless diorisis-merged-database
    (user-error "No merged database: see diorisis-merged-database"))
  (setq diorisis-use-merged (not diorisis-use-merged))
  (diorisis-close)
  (message "Now working with the %s database: %s"
           (if diorisis-use-merged "merged" "plain")
           (file-name-nondirectory (diorisis--file))))

(defun diorisis--file ()
  "The database\='s path, or an error saying what to do about it.

WHICHEVER IS IN USE: the plain corpus, or the merged copy where
`diorisis-use-merged\=' says so and there is one.  A merged database asked
for and not there falls back on the plain one with a word, rather than
refusing to search at all."
  (let ((file (or (and diorisis-use-merged
                       diorisis-merged-database
                       (let ((merged (expand-file-name
                                      diorisis-merged-database)))
                         (if (file-readable-p merged)
                             merged
                           (message "No merged database at %s; using the plain one"
                                    merged)
                           nil)))
                  (and diorisis-database
                       (expand-file-name diorisis-database)))))
    (cond
     ((null file)
      (user-error
       (concat "diorisis-database is not set.  Build the index with "
               "diorisis-index.py and point this at the diorisis.db it "
               "writes")))
     ((not (file-readable-p file))
      (user-error "No readable database at %s" file))
     (t file))))

(defun diorisis--db ()
  "The open database, opening it if need be."
  (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (user-error
     "This Emacs cannot read SQLite: 29 or later, built with sqlite3"))
  (let ((file (diorisis--file)))
    (unless (and diorisis--connection
                 (equal (car diorisis--connection) file)
                 (sqlitep (cdr diorisis--connection)))
      (setq diorisis--connection (cons file (sqlite-open file))))
    (cdr diorisis--connection)))

(defun diorisis-close ()
  "Close the database.

Wanted after rebuilding the index under a running Emacs: the handle held open
refers to the file that was replaced, and SQLite is entitled to be unhappy
about it."
  (interactive)
  (when (and diorisis--connection
             (sqlitep (cdr diorisis--connection)))
    (sqlite-close (cdr diorisis--connection)))
  (setq diorisis--connection nil)
  (diorisis-forget-vocabulary)
  (message "The Diorisis database is closed"))

(defun diorisis--select (query &optional values)
  "Run QUERY with VALUES and return its rows."
  (sqlite-select (diorisis--db) query values))

(defun diorisis--utils ()
  "Load Diogenes' beta code conversions, and say whether there are any."
  (or (featurep 'diogenes-utils)
      (and (locate-library "diogenes-utils")
           (require 'diogenes-utils nil t))))

(defun diorisis--greek (beta)
  "BETA as Greek, or as it stands where it cannot be converted."
  (cond
   ((or (null beta) (string-empty-p beta)) (or beta ""))
   (diorisis-show-beta-code beta)
   ((and (diorisis--utils) (fboundp 'diogenes--beta-to-utf8))
    (diogenes--beta-to-utf8 beta))
   (t beta)))

(defun diorisis--beta (string)
  "STRING as beta code, converting it where it is Greek.

A reader may type either, and the database holds only beta code."
  (cond
   ((or (null string) (string-empty-p string)) string)
   ;; `\\cg' is the Greek script category: any Greek letter at all means the
   ;; string was typed as Greek rather than as beta code.
   ((and (string-match-p "\\cg" string)
         (diorisis--utils)
         (fboundp 'diogenes--utf8-to-beta))
    (diogenes--utf8-to-beta string))
   (t string)))

(defun diorisis--year (date)
  "DATE, a year as the catalogue writes it, as `230 A.D.\\=' or `750 B.C.\\='.

Nil where DATE is not a year.  The catalogue's dates are numbers as strings
and negative for B.C., but the column also holds the JSON release's version
string for a text the catalogue does not cover -- `1.51', which is not a date
and must not be shown as one."
  (when (and date (string-match-p "\\`-?[0-9]+\\'" date))
    (let ((year (string-to-number date)))
      (if (< year 0)
          (format "%d B.C." (- year))
        (format "A.D. %d" year)))))

(defconst diorisis--select-columns
  "SELECT t.author, t.work, o.author_id, o.work_id, o.location,
       o.sentence, o.form, o.lemma, o.morph, o.confidence,
       t.genre, t.subgenre, t.date, s.words,
       (SELECT s2.location FROM sentences s2
          WHERE s2.author_id=o.author_id AND s2.work_id=o.work_id
            AND s2.sentence > o.sentence
          ORDER BY s2.sentence LIMIT 1),
       (SELECT s2.sentence FROM sentences s2
          WHERE s2.author_id=o.author_id AND s2.work_id=o.work_id
            AND s2.sentence > o.sentence
          ORDER BY s2.sentence LIMIT 1)"
  "The columns every hit is read from, less the one that may not be there.

WHERE THE NEXT SENTENCE BEGINS, and why a hit wants to know.  A sentence is
not a line: Apollonius\=' `i(/eto d\=' h(/ge\=' is the tail of 3.806 and runs into
3.807, so a hit cited as a point says less than the corpus knows.  The line
the following sentence begins on bounds this one -- it ends there or earlier
-- which makes the hit an INTERVAL, which is what Diogenes\=' own citations
are: `classicist-citation-interval-from-key\=' reads `3.806-3.807\='.

Its sentence number comes back too, because the bound is only good if the
next sentence is the next one: our `sentences\=' table has gaps where the
indexer could not put a sentence back together, and the stored one after a
gap may be several sentences later.  See `diorisis--interval\='.

See `diorisis--select-clause\=', which puts `tlg_work_id\=' after these.")

(defconst diorisis--select-joins
  "
FROM occurrences o
JOIN texts t ON o.author_id=t.author_id AND o.work_id=t.work_id
LEFT JOIN sentences s ON s.author_id=o.author_id
  AND s.work_id=o.work_id AND s.sentence=o.sentence"
  "The joins every hit is read through.

LEFT JOIN ON `sentences\\=' DELIBERATELY.  A hit whose sentence is missing --
the indexer stores a sentence only where it could put one back together from
its tokens -- is still a hit, at a real citation, and must be listed with
nothing to show for it rather than silently dropped.  An inner join loses it.

The order of the columns is `diorisis--hit\\='s business and nothing else\\='s.")

(defvar diorisis--columns nil
  "Which columns each table has, as (TABLE . COLUMNS), read once.")

(defun diorisis--column-p (table column)
  "Whether TABLE has COLUMN in this database.

FEATURE DETECTION, because the database grows.  `diorisis-tlg-numbers.py\='
adds `tlg_work_id\=' to `texts\=' and `diorisis-merge-duckdb.py\=' adds ten
columns to `occurrences\=', and both are things a reader may not have run.
Naming a column that is not there is not a wrong answer but a failed query,
so what is there is asked rather than assumed."
  (let ((known (assoc table diorisis--columns)))
    (unless known
      (setq known (cons table
                        (mapcar (lambda (row) (nth 1 row))
                                (diorisis--select
                                 (format "PRAGMA table_info(%s)" table)))))
      (push known diorisis--columns))
    (and (member column (cdr known)) t)))

(defun diorisis--select-clause ()
  "The columns and the joins, with the TLG work number where there is one.

WHY THE NUMBER IS ASKED FOR AT ALL.  This package was built believing that
the Diorisis filenames carry the TLG\='s own numbers, so that a hit could be
opened in Diogenes with nothing translated.  For 792 texts that is true.  For
nineteen it is not: Diorisis numbers Euripides\=' Hecuba 040 where the TLG
numbers it 0006.007, and the thirteen plays run 040 to 052 against the TLG\='s
007 to 019 -- in a different order, so it is not even an offset.  `RET\=' on a
Euripides hit was asking for a work that is something else or nothing.

`diorisis-tlg-numbers.py\=' writes the right number into `texts.tlg_work_id\=',
deriving it from Bilby\='s DuckDB compilation, whose ids were conformed to the
TLG\='s convention.  Where a reader has not run it the column is absent and
NULL is selected in its place, which is the same thing as `use ours\='."
  (concat diorisis--select-columns
          (if (diorisis--column-p "texts" "tlg_work_id")
              ",\n       t.tlg_work_id"
            ",\n       NULL")
          diorisis--select-joins))

(defconst diorisis--dated
  "t.date IS NOT NULL AND t.date GLOB '*[0-9]*' \
AND NOT t.date GLOB '*[^-0-9]*'"
  "What it is for a text to have a date that can be compared.

THE COLUMN IS NOT ALWAYS A YEAR.  Where the catalogue covers a text the date
is a year as a string, negative for B.C.; where it does not, the indexer falls
back on the JSON release's version and the column holds `1.51'.  `CAST' would
read that as the year 1 and put the text in the first century, so a century
filter asks for a value that is digits and an optional minus and nothing else.
A text with no date is not in any century and is excluded by the same clause.")

(defun diorisis--pattern (value)
  "VALUE as (OPERATOR . VALUE) for a text column.

`=\\=' for a plain string, `LIKE\\=' where VALUE holds a `%\\='.

THE WILDCARD IS `%\\=' AND CANNOT BE `*\\=', which is what one would rather type.
Beta code marks a CAPITAL with an asterisk: Achilles is `*)axilleu/s\\=', and a
quarter of the proper names in the corpus begin with one.  Taking `*\\=' for a
wildcard would have turned every search for a name into a search for anything
ending in it -- which mostly finds the name, and so would have looked like it
worked.

`_\\=' is SQL\='s single character and is left alone for the same reason: the
Perseus word list writes a macron with an underscore.  Where a pattern holds
both, the underscore means any character, as it does in SQL."
  (if (string-search "%" value)
      (cons "LIKE" value)
    (cons "=" value)))

(defconst diorisis--scopes
  '((within . "%s BETWEEN 1 AND %d")
    (between . "%s BETWEEN %d AND %d")
    (exactly . "%s = %d")
    ;; ORDERED, LIKE THE OTHERS.  This was `<> 0' -- any position but the
    ;; same word -- so `followed by, anywhere in the same sentence' also
    ;; matched a sentence with the second word BEFORE the first, and said
    ;; `followed by' while meaning `near'.  The distance is signed and every
    ;; other scope uses the sign; this one did not.
    ;;
    ;; AND THE UNORDERED READING NEEDS NOTHING HERE: `followed or preceded
    ;; by' wraps the distance in ABS before this template is filled, and
    ;; `ABS(x) > 0' is exactly `x <> 0'.
    (sentence . "%s > 0"))
  "How each scope reads as arithmetic on the distance.

`sentence' CONSTRAINS THE ORDER AND NOT THE DISTANCE.  Two elements in the
same sentence with no distance asked for may be any distance apart -- but in
the order asked for, and not the same word, which would let a single form
satisfy both halves of a query and report every occurrence of it as a
sequence.")

(defun diorisis--element-conditions (element alias)
  "What ELEMENT requires of the row ALIAS, as (SQL . VALUES).

NEGATION IS ON THE CONDITION and not on the row: the app\\='s `anything but the
exact form\\=' means a word that is there and is something else, not the absence
of a word.  So the clause is wrapped in NOT -- and the column is wrapped in
COALESCE first, because NOT of NULL is NULL and a word with no morphology
recorded would otherwise fail to be `anything but a participle\\='."
  (let* ((kind (plist-get element :kind))
         (value (or (plist-get element :value) ""))
         (bare (plist-get element :bare))
         (contains (eq (plist-get element :match) 'contains))
         (clauses nil)
         (values nil))
    (pcase kind
      ('punct
       (push (format "%s.mark = ?" alias) clauses)
       (push value values))
      ('morph
       ;; ONE CLAUSE PER FEATURE, as everywhere else.  This place was missed
       ;; when the rest were changed: an element whose own KIND is `morph\='
       ;; built its clause here, and went on asking for the features as a
       ;; PHRASE -- `LIKE \'%part gen%\'\=', which no analysis contains, the
       ;; corpus writing `aor part act masc gen sg\='.  So a query for a
       ;; genitive participle found nothing, which is what it was reported
       ;; as doing.
       (let ((made (diorisis--morph-clauses alias value)))
         (dolist (clause (car made)) (push clause clauses))
         (dolist (one (cdr made)) (push one values))))
      ((or 'form 'lemma)
       (let* ((column (if (eq kind 'form) "form" "lemma"))
              (column (if bare (concat column "_bare") column))
              (wanted (if bare
                          (diorisis--bare
                           (diorisis--greek
                            (diorisis--beta value)))
                        (diorisis--beta value))))
         (when (and bare (not (diorisis--column-p
                               "occurrences" "form_bare")))
           (user-error
            (concat "This index has no diacritic-free columns: rebuild it "
                    "with the current diorisis-index.py to search that way")))
         (if (or contains (string-search "%" wanted))
             (progn
               (push (format "COALESCE(%s.%s, '') LIKE ?" alias column)
                     clauses)
               (push (if contains (format "%%%s%%" wanted) wanted) values))
           (push (format "COALESCE(%s.%s, '') = ?" alias column) clauses)
           (push wanted values))))
      (_ nil))
    (let ((morph (plist-get element :morph)))
      (when (and morph (not (string-empty-p morph))
                 (memq kind '(form lemma)))
        ;; THE FURTHER ANALYSIS is never negated with the rest: `a form of
        ;; mu/w that is not a participle' negates the analysis, and the app
        ;; asks for the two separately for that reason.
        (let ((made (diorisis--morph-clauses alias morph)))
          (dolist (clause (car made)) (push clause clauses))
          (dolist (value (cdr made)) (push value values)))))
    (let ((sql (mapconcat #'identity (nreverse clauses) " AND ")))
      (cons (cond ((string-empty-p sql) "1")
                  ((plist-get element :negate) (format "NOT (%s)" sql))
                  (t sql))
            (nreverse values)))))

(defun diorisis--element-table (element)
  "Which table ELEMENT is found in."
  (if (eq (plist-get element :kind) 'punct) "punctuation" "occurrences"))

(defun diorisis--distance (element previous alias)
  "The arithmetic ELEMENT\\='s scope asks for, against PREVIOUS at ALIAS.

`nodes\\=' COUNTS THE PUNCTUATION and `words\\=' does not, which is the whole of
the difference between the app\\='s `followed by\\=' and its `followed by (ignore
punctuation)\\='.  In `w) a)/ndres , e)gw\\=', the last word is one word after
`a)/ndres\\=' and two nodes after it; a query asking for a distance of one finds
it one way and not the other.  Punctuation itself is only ever placed by
nodes, having no place among the words at all."
  (let* ((by (if (or (eq (plist-get element :count) 'nodes)
                     (eq (plist-get element :kind) 'punct)
                     (eq (plist-get previous :kind) 'punct))
                 "node_index" "word_index"))
         (difference (format "(%s.%s - %s.%s)" alias by
                             (plist-get previous :alias) by))
         (difference (if (eq (plist-get element :relation) 'either)
                         (format "ABS%s" difference)
                       difference))
         (scope (or (plist-get element :scope) '(sentence)))
         (template (cdr (assq (car scope) diorisis--scopes))))
    (pcase (car scope)
      ('within (format template difference (or (nth 1 scope) 1)))
      ('between (format template difference (or (nth 1 scope) 1)
                        (or (nth 2 scope) 1)))
      ('exactly (format template difference (or (nth 1 scope) 1)))
      (_ (format template difference)))))

(defun diorisis--elements (elements)
  "ELEMENTS as (JOINS CONDITIONS VALUES), the first being the hit.

The first element is `o\\=', which is what `diorisis--select-clause\\=' calls
the occurrences it reads a hit from -- so a query of one element is the
ordinary search and a query of three is the same query with joins on it."
  (let ((joins nil)
        (conditions nil)
        (values nil)
        (previous nil)
        (index 1))
    (dolist (element elements)
      (let* ((alias (if (null previous) "o" (format "e%d" index)))
             (element (plist-put (copy-sequence element) :alias alias))
             (own (diorisis--element-conditions element alias)))
        (when previous
          (push (format
                 "JOIN %s %s ON %s.author_id=o.author_id\
 AND %s.work_id=o.work_id AND %s.sentence=o.sentence AND %s"
                 (diorisis--element-table element) alias
                 alias alias alias
                 (diorisis--distance element previous alias))
                joins))
        (unless (equal (car own) "1")
          (push (car own) conditions)
          (setq values (append values (cdr own))))
        (setq previous element)
        (setq index (1+ index))))
    (list (mapconcat #'identity (nreverse joins) "\n")
          (nreverse conditions)
          values)))

(defun diorisis--where (spec)
  "The WHERE clause SPEC asks for, as (SQL . VALUES).

`1\\=' where SPEC asks for nothing, which is a search of the whole corpus and is
the caller's business to warn about."
  (let ((clauses nil)
        (values nil))
    ;; PUSHED IN PAIRS.  A clause and the values it binds go on together, so
    ;; that the two lists cannot fall out of step -- which is the one way a
    ;; query builder goes wrong silently, binding a lemma to a genre.
    (let ((lemma (plist-get spec :lemma)))
      (when (and lemma (not (string-empty-p lemma)))
        (let ((pattern (diorisis--pattern (diorisis--beta lemma))))
          (push (format "o.lemma %s ?" (car pattern)) clauses)
          (push (cdr pattern) values))))
    (let ((form (plist-get spec :form)))
      (when (and form (not (string-empty-p form)))
        (let ((pattern (diorisis--pattern (diorisis--beta form))))
          (push (format "o.form %s ?" (car pattern)) clauses)
          (push (cdr pattern) values))))
    (let ((pos (plist-get spec :pos)))
      (when (and pos (not (string-empty-p pos)))
        (push "o.pos = ?" clauses)
        (push pos values)))
    ;; MORPHOLOGY MATCHES THE MIDDLE.  `morph' holds every analysis the form
    ;; admits, joined by ` | ', because a form may admit several -- so asking
    ;; for an aorist participle means asking for a form whose analyses INCLUDE
    ;; one, not only those where it is the single possibility.  The reader's
    ;; own wildcards are left alone: `aor part act' and `aor%sg' both work.
    (let ((morph (plist-get spec :morph)))
      (when (and morph (not (string-empty-p morph)))
        (let ((made (diorisis--morph-clauses "o" morph)))
          (dolist (clause (car made)) (push clause clauses))
          (dolist (value (cdr made)) (push value values)))))
    (let ((author (plist-get spec :author)))
      (when (and author (not (string-empty-p author)))
        (push "o.author_id = ?" clauses)
        (push author values)))
    (let ((work (plist-get spec :work)))
      (when (and work (not (string-empty-p work)))
        (push "o.work_id = ?" clauses)
        (push work values)))
    (let ((genre (plist-get spec :genre)))
      (when (and genre (not (string-empty-p genre)))
        (push "t.genre = ?" clauses)
        (push genre values)))
    (let ((subgenre (plist-get spec :subgenre)))
      (when (and subgenre (not (string-empty-p subgenre)))
        (push "t.subgenre = ?" clauses)
        (push subgenre values)))
    (let ((from (plist-get spec :from))
          (to (plist-get spec :to)))
      (when (or from to)
        ;; THE GUARD BINDS NOTHING, so nothing goes on the value list.  The
        ;; two lists are kept in step by pushing a clause and its values
        ;; together, and a clause with no values is where that goes wrong if
        ;; a placeholder is pushed to keep them the same length.
        (push diorisis--dated clauses)
        (when from
          (push "CAST(t.date AS INTEGER) >= ?" clauses)
          (push from values))
        (when to
          (push "CAST(t.date AS INTEGER) <= ?" clauses)
          (push to values))))
    ;; CONFIDENCE, AND WHY NULL IS THE CERTAIN CASE.  The column is the
    ;; tagger's confidence where it had to choose between lemmata, and NULL
    ;; where the form admitted only one -- so NULL is not missing information
    ;; but the absence of any doubt, and a reader asking for hits of at least
    ;; some confidence wants those too.  Reading it the other way round
    ;; excludes precisely the hits that need no checking.
    (let ((confidence (plist-get spec :confidence)))
      (when confidence
        (push "(o.confidence IS NULL OR o.confidence >= ?)" clauses)
        (push confidence values)))
    (when (plist-get spec :unambiguous)
      (push "o.confidence IS NULL" clauses))
    ;; AND THE ELEMENTS, whose first is this same `o'.  The text-level
    ;; narrowings above -- genre, date, author -- apply to a query of several
    ;; elements exactly as they do to one, there being one sentence and one
    ;; text under all of them.
    (let ((elements (diorisis--elements (plist-get spec :elements))))
      (dolist (condition (nth 1 elements))
        (push condition clauses))
      (setq values (append (reverse (nth 2 elements)) values)))
    (cons (if clauses
              (mapconcat #'identity (nreverse clauses) "\n  AND ")
            "1")
          (nreverse values))))

(defun diorisis--order (spec)
  "How SPEC wants its hits ordered.

CORPUS ORDER BY DEFAULT -- author, work, sentence -- which is the order the
texts are numbered in and puts a work\\='s hits together and in the order they
are read.  By date where asked: a word\\='s history is what one wants when the
question is when it came into use, and undated texts come last rather than
sorting as the year nothing."
  (if (plist-get spec :by-date)
      (concat "CASE WHEN " diorisis--dated
              " THEN 0 ELSE 1 END, CAST(t.date AS INTEGER),"
              " o.author_id, o.work_id, o.sentence")
    "o.author_id, o.work_id, o.sentence"))

(defcustom diorisis-hit-per-sentence t
  "Whether a query of several elements lists a sentence once.

A sentence with four forms of `le/gw\=' in it satisfies a query four times over
and is four hits -- which is true, and is not what a reader who asked about
sentences wants to read four times with the window in a different place each
time.

NIL LISTS EVERY OCCURRENCE, which is the honest concordance reading and what a
one-element search does regardless: there, every instance of the word is the
whole point."
  :type 'boolean
  :group 'diorisis)

(defun diorisis-count (spec)
  "How many occurrences SPEC has in the corpus.

WITHOUT THE SENTENCES.  Counting does not need them and the join over ten
million rows is what would be felt."
  (let* ((where (diorisis--where spec))
         (joins (car (diorisis--elements (plist-get spec :elements))))
         (rows (diorisis--select
                ;; DISTINCT ON THE HIT, for the reason `diorisis-hits'
                ;; groups: with joins, a sentence satisfying the later
                ;; elements several ways counts several times, so `6146 hits'
                ;; was four thousand more than there are sentences to show.
                ;; COUNTED AS THE HITS ARE LISTED, or the number above the
                ;; results is not the number of results: with joins a
                ;; sentence satisfying the later elements several ways counts
                ;; several times, and with `diorisis-hit-per-sentence' it
                ;; is one hit however many forms in it satisfy the first.
                (concat (cond
                         ((null (cdr (plist-get spec :elements)))
                          "SELECT COUNT(*) FROM occurrences o\n")
                         (diorisis-hit-per-sentence
                          "SELECT COUNT(DISTINCT o.author_id || '-' ||\
 o.work_id || '-' || o.sentence) FROM occurrences o\n")
                         (t
                          "SELECT COUNT(DISTINCT o.rowid) FROM occurrences o\n"))
                        "JOIN texts t ON o.author_id=t.author_id"
                        " AND o.work_id=t.work_id\n"
                        (if (string-empty-p joins) "" (concat joins "\n"))
                        "WHERE " (car where))
                (cdr where))))
    (or (caar rows) 0)))

(defun diorisis-hits (spec)
  "The occurrences SPEC asks for, each as a plist."
  (let* ((where (diorisis--where spec))
         (limit (or (plist-get spec :limit) diorisis-limit))
         (elements (plist-get spec :elements))
         (joins (car (diorisis--elements elements)))
         ;; THE OTHER ELEMENTS\=' WORDS, so that they can be marked in the
         ;; sentence and the window drawn wide enough to hold them.  A query
         ;; of three elements found three words and showed one, the other two
         ;; often outside the window -- which read as the search having found
         ;; a sentence for no reason.
         (extra (when (cdr elements)
                  (mapconcat (lambda (index) (format ", e%d.form" index))
                             (number-sequence 2 (length elements))
                             "")))
         ;; ONE ROW PER OCCURRENCE.  The join multiplies: a sentence where
         ;; four words satisfy the second element and three the third gives
         ;; twelve rows of the same hit, which is what filled the results
         ;; with the same Thucydides forty times over.  Grouping on the hit\='s
         ;; own rowid keeps one of each and leaves a plain search -- which has
         ;; no joins to multiply anything -- exactly as it was.
         ;; ONE HIT PER SENTENCE, where a query has several elements.  The
         ;; rowid grouping cured the join multiplying, and left a second and
         ;; truer multiplication: a sentence with four forms of `le/gw' in
         ;; it is four occurrences and four hits, and was listed four times
         ;; over with the window in a different place -- which is right by
         ;; the query and wrong for a reader, who asked about sentences.
         ;;
         ;; A PLAIN SEARCH IS STILL PER OCCURRENCE, that being what a
         ;; concordance is: every instance of the word, including two in one
         ;; sentence.  `diorisis-hit-per-sentence' set to nil restores
         ;; the old behaviour for queries too.
         (group (cond ((null (cdr elements)) "")
                      (diorisis-hit-per-sentence
                       "\nGROUP BY o.author_id, o.work_id, o.sentence")
                      (t "\nGROUP BY o.rowid")))
         ;; SPLICED INTO THE COLUMN LIST AND NOT APPENDED.  The clause is
         ;; the whole of `SELECT ... FROM occurrences o JOIN texts ...\=', so
         ;; adding `, e2.form\=' to the end of it put a column among the
         ;; tables: `no such table: e2.form\='.  The columns go before the
         ;; FROM, which is where columns go.
         (clause (let ((whole (diorisis--select-clause)))
                   (if (or (null extra) (string-empty-p extra))
                       whole
                     (let ((at (string-search "\nFROM occurrences o" whole)))
                       (if at
                           (concat (substring whole 0 at) extra
                                   (substring whole at))
                         whole)))))
         (rows (diorisis--select
                (concat clause
                        (if (string-empty-p joins) "" (concat "\n" joins))
                        "\nWHERE " (car where)
                        group
                        "\nORDER BY " (diorisis--order spec)
                        "\nLIMIT ?")
                (append (cdr where) (list limit)))))
    (mapcar #'diorisis--hit rows)))

(defun diorisis--hit (row)
  "ROW, as `diorisis--select-clause\\=' returns it, as a plist."
  (list :author (nth 0 row) :work (nth 1 row)
        :author-id (nth 2 row) :work-id (nth 3 row)
        :location (nth 4 row) :sentence (nth 5 row)
        :form (nth 6 row) :lemma (nth 7 row) :morph (nth 8 row)
        :confidence (nth 9 row)
        :genre (nth 10 row) :subgenre (nth 11 row) :date (nth 12 row)
        :words (nth 13 row)
        ;; THE FORMS THE OTHER ELEMENTS MATCHED, where there were any: the
        ;; columns after the seventeen this clause always selects.
        :others (nthcdr 17 row)
        :next-location (nth 14 row) :next-sentence (nth 15 row)
        ;; The TLG's own work number, or nil where the database does not
        ;; carry one.  See `diorisis--select-clause'.
        :tlg-work-id (nth 16 row)))

(defun diorisis-distribution (spec)
  "SPEC's hits counted by text, commonest first.

Each is (AUTHOR WORK DATE COUNT WORDS): what a reader asking whether a word is
Attic or Hellenistic wants, which is not a list of passages."
  (let* ((where (diorisis--where spec))
         (rows (diorisis--select
                (concat "SELECT t.author, t.work, t.date, COUNT(*) AS hits,"
                        " t.words\nFROM occurrences o\n"
                        "JOIN texts t ON o.author_id=t.author_id"
                        " AND o.work_id=t.work_id\nWHERE " (car where)
                        "\nGROUP BY o.author_id, o.work_id"
                        "\nORDER BY hits DESC, t.author, t.work")
                (cdr where))))
    rows))

(defvar diorisis--vocabulary nil
  "The lemmata and the tagset as last read, or nil.
A plist: :stamp, :lemmata as (BETA . COUNT), :pos as strings.")

(defvar diorisis--candidate-cache nil
  "The candidates with their bare forms: (STAMP . [(CANDIDATE . BARE) ...]).

BARED ONCE AND NOT PER KEYSTROKE.  Sixty-three thousand conversions take a
second or two; doing them on every character typed would make the prompt
unusable, and the bare form of a lemma cannot change between keystrokes.")

(defvar diorisis--source-cache nil
  "Candidate pairs by source: an alist of (SOURCE . PAIRS).

Cached because the Greek is converted one lemma at a time and Diogenes\\=' list
is the longer: this is seconds the first time and nothing afterwards.")

(defvar diorisis--source-beta nil
  "An alist of (SOURCE . HASH), each from a candidate to its beta code.")

(defvar diorisis--lemma-table nil
  "The completion table as last built: (STAMP CANDIDATES BETA COUNTS).

DECLARED HERE, BESIDE THE OTHER CACHE, and not down beside the function that
builds it.  `diorisis-forget-vocabulary\=' clears both and is above that
point, and a `defvar\=' later in the file does not help it: at compile time the
assignment is to a variable not yet declared, which is a warning and would be
a genuine bug in a file loaded in a different order.")

(defun diorisis--vocabulary-file ()
  "Where the lemmata are cached, beside the database."
  (expand-file-name "diorisis-lemmata.tsv"
                    (file-name-directory (diorisis--file))))

(defun diorisis--stamp ()
  "When the database was last written, as a number.

A NUMBER AND NOT A TIMESTAMP, because this is written to a file and read back:
Emacs\\=' timestamps have had three representations and two of them do not
compare `equal\\=' to the third.  Seconds as a float survive being written down."
  (float-time (file-attribute-modification-time
               (file-attributes (diorisis--file)))))

(defun diorisis--conversion-probe ()
  "What the beta code `mu/w\\=' converts to here and now.

THE GUARD ON THE CACHE, and the reason the Greek can be cached at all.  The
conversion belongs to Diogenes: a cache written in a session where Diogenes
was not loaded would hold beta code in the Greek column and look like an
answer for ever after.  So one word is converted and written in the header,
and a cache whose probe does not match what this session converts is passed
over and built again.

`mu/w\\=' because it is short and carries an accent, so a conversion that half
works does not pass."
  (diorisis--greek "mu/w"))

(defun diorisis--read-vocabulary ()
  "The lemmata from the cache file, or nil where there is none to trust.

READ WITH ONE `insert-file-contents\\=' AND A SPLIT, which for sixty-odd
thousand lines is a moment.  What is cached is the whole of the work: the
lemma as the corpus spells it, as Greek, and as bare letters, with its count
-- so a session that has a cache converts nothing at all, where before it
converted 63,718 lemmata one at a time and a reader waited for it at the first
prompt."
  (let ((file (diorisis--vocabulary-file)))
    (when (file-readable-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (let ((header (buffer-substring-no-properties
                           (point) (line-end-position)))
                  (wanted (format "# tei-diorisis 2\t%s\t%s"
                                  (diorisis--stamp)
                                  (diorisis--conversion-probe))))
              ;; STALE OR CONVERTED OTHERWISE IS WORSE THAN ABSENT: an index
              ;; rebuilt with more texts, or a cache written without the
              ;; conversion, would answer wrongly and quietly.
              (when (equal header wanted)
                (forward-line 1)
                (let ((pos (split-string
                            (buffer-substring-no-properties
                             (point) (line-end-position))
                            "\t" t))
                      (records nil))
                  (forward-line 1)
                  (while (not (eobp))
                    (let ((fields (split-string
                                   (buffer-substring-no-properties
                                    (point) (line-end-position))
                                   "\t")))
                      (when (= (length fields) 4)
                        (push (list (nth 0 fields) (nth 1 fields)
                                    (nth 2 fields)
                                    (string-to-number (nth 3 fields)))
                              records)))
                    (forward-line 1))
                  (list :stamp (diorisis--stamp)
                        :records (nreverse records)
                        :pos (cdr pos))))))
        (error nil)))))

(defun diorisis--build-vocabulary ()
  "Read every lemma out of the database, convert it, and cache the lot.

ONE PASS FOR THE LEMMATA AND THE TAGSET.  Grouping by lemma and part of speech
together gives the counts by adding up and the tagset by collecting, where
asking separately would mean a second scan of ten million rows for a list of
eleven strings.

AND THE CONVERSION HAPPENS HERE, ONCE.  Each lemma is turned into Greek and
into bare letters and written down beside its beta code; every session after
this one reads the three and converts nothing."
  (message "Reading the Diorisis lemmata ...")
  (let ((counts (make-hash-table :test #'equal))
        (parts (make-hash-table :test #'equal))
        (records nil))
    (dolist (row (diorisis--select
                  "SELECT lemma, pos, COUNT(*) FROM occurrences\
 GROUP BY lemma, pos"))
      (let ((lemma (nth 0 row))
            (pos (nth 1 row))
            (count (or (nth 2 row) 0)))
        (puthash lemma (+ count (or (gethash lemma counts) 0)) counts)
        (when (and pos (not (string-empty-p pos)))
          (puthash pos t parts))))
    (message "Converting %d lemmata, once ..." (hash-table-count counts))
    (maphash
     (lambda (lemma count)
       (let ((shown (diorisis--greek lemma)))
         (push (list lemma shown (diorisis--bare shown) count) records)))
     counts)
    (setq records (sort records (lambda (a b)
                                  (string-lessp (car a) (car b)))))
    (let ((datum (list :stamp (diorisis--stamp)
                       :records records
                       :pos (sort (hash-table-keys parts) #'string-lessp))))
      (diorisis--write-vocabulary datum)
      datum)))

(defun diorisis--write-vocabulary (datum)
  "Write DATUM to the cache file.

WRITTEN BESIDE THE DATABASE, and not minded if it cannot be: a read-only
archive directory is a normal way to keep a corpus, and the only cost is
doing the work once a session."
  (condition-case error
      (with-temp-file (diorisis--vocabulary-file)
        (insert (format "# tei-diorisis 2\t%s\t%s\n"
                        (plist-get datum :stamp)
                        (diorisis--conversion-probe)))
        (insert "# pos\t" (string-join (plist-get datum :pos) "\t") "\n")
        (dolist (record (plist-get datum :records))
          (insert (nth 0 record) "\t" (nth 1 record) "\t"
                  (nth 2 record) "\t"
                  (number-to-string (nth 3 record)) "\n")))
    (error (message "Could not cache the lemmata: %s"
                    (error-message-string error)))))

(defun diorisis-vocabulary ()
  "The lemmata and the tagset, read once and kept."
  (or diorisis--vocabulary
      (setq diorisis--vocabulary
            (or (diorisis--read-vocabulary)
                (diorisis--build-vocabulary)))))

(defun diorisis-lemma-records ()
  "Every lemma as (BETA GREEK BARE COUNT)."
  (plist-get (diorisis-vocabulary) :records))

(defun diorisis-lemmata ()
  "Every lemma in the corpus, as (BETA . COUNT)."
  (mapcar (lambda (record) (cons (nth 0 record) (nth 3 record)))
          (diorisis-lemma-records)))

(defun diorisis-parts-of-speech ()
  "Every part of speech the corpus uses."
  (plist-get (diorisis-vocabulary) :pos))

(defun diorisis-forget-vocabulary ()
  "Forget the lemmata read from the database.

Wanted after rebuilding the index, and called when the database is closed.
The cache file is left alone: it carries the database's own timestamp and is
passed over of its own accord once that has changed."
  (interactive)
  (setq diorisis--vocabulary nil)
  (setq diorisis--lemma-table nil)
  (setq diorisis--candidate-cache nil)
  (setq diorisis--source-cache nil)
  (setq diorisis--source-beta nil))

(defun diorisis--lemma-completion ()
  "The lemmata as something to complete on.

Returns (CANDIDATES BETA COUNTS BARE): the candidates as Greek strings, a hash
from a candidate to the beta code it stands for, a hash from a candidate to
how often it occurs, and a list of (BARE BETA GREEK COUNT) for matching by
approximation.

GREEK TO CHOOSE FROM AND BETA CODE TO SEARCH WITH.  A reader completing on
`memuk' would be completing on nothing they can read; and the database holds
beta code, so the choice has to come back as beta code.  Where two lemmata
convert to the same Greek -- homographs distinguished by a trailing digit in
the word list do not, but nothing promises that -- the beta code is shown
beside the second to keep the candidates distinct.

AND THE BARE FORMS BESIDE THEM, which is what lets an approximation be
narrowed.  Built in the same pass: the conversion of sixty-three thousand
lemmata is the expensive part and is not worth doing twice."
  (let ((stamp (ignore-errors (diorisis--stamp))))
    (unless (and diorisis--lemma-table
                 (equal (car diorisis--lemma-table) stamp))
      (let ((beta (make-hash-table :test #'equal))
            (counts (make-hash-table :test #'equal))
            (candidates nil)
            (bare nil))
        ;; THE GREEK COMES OUT OF THE CACHE.  It was converted here, one
        ;; lemma at a time, at the first prompt of every session -- a second
        ;; or two if the conversion was warm and a good deal more if it was
        ;; not.  It is written down now: see `diorisis--build-vocabulary'.
        (dolist (entry (diorisis-lemma-records))
          (let* ((raw (nth 0 entry))
                 (shown (nth 1 entry))
                 (candidate (if (gethash shown beta)
                                (format "%s (%s)" shown raw)
                              shown)))
            (puthash candidate raw beta)
            (puthash candidate (nth 3 entry) counts)
            (push candidate candidates)
            (push (list (nth 2 entry) raw shown (nth 3 entry)) bare)))
        (setq diorisis--lemma-table
              (list stamp
                    ;; COMMONEST FIRST, and the display keeps this order --
                    ;; see `diorisis--lemma-table'.  Filtered to forty
                    ;; candidates by a few letters, the one wanted is far
                    ;; likelier to be the common word than the
                    ;; alphabetically first; and sorting once a session is
                    ;; nothing, where sorting per keystroke would not be.
                    (sort (nreverse candidates)
                          (lambda (a b)
                            (> (or (gethash a counts) 0)
                               (or (gethash b counts) 0))))
                    beta counts
                    (nreverse bare)))))
    (cdr diorisis--lemma-table)))

(defun diorisis--input-greek (input)
  "INPUT as Greek, whether it was typed as beta code or as Greek."
  (diorisis--greek (diorisis--beta input)))

(defun diorisis--marked-p (input)
  "Whether INPUT carries any diacritic at all.

WHAT DECIDES HOW STRICTLY IT IS MATCHED.  `mu/w' and `μύω' carry accents and
mean that word; `muw' and `μυω' carry none and mean whatever is spelled with
those letters.  So the presence of a mark is the reader saying which they
want, and nothing has to be configured.

In beta code the marks are punctuation -- `)(/\\=|+*' -- and in Greek they are
combining characters once the string is decomposed, or are built into a
precomposed letter, which decomposing brings out."
  (or (string-match-p "[()/\\\\=|+*]" input)
      (seq-some (lambda (character)
                  (memq (get-char-code-property character 'general-category)
                        '(Mn Mc Me)))
                (string-to-list (ucs-normalize-NFD-string input)))))

(defvar diorisis--completion-pairs nil
  "The candidates the style should filter, or nil for the corpus\='s own.

BOUND AROUND A PROMPT and not set.  The same style serves the corpus search,
which completes on the 63,718 lemmata Diorisis attests, and Diogenes\=' own
commands, which complete on its whole word list -- and the style is handed its
set rather than going to look for one, so that neither prompt has to know
about the other.")

(defun diorisis--candidate-pairs ()
  "Every candidate with its diacritic-free form, as a list of conses."
  (let ((stamp (ignore-errors (diorisis--stamp))))
    (unless (and diorisis--candidate-cache
                 (equal (car diorisis--candidate-cache) stamp))
      ;; FROM THE CACHE AS WELL: the bare form of every candidate is one of
      ;; the three things written down, so this is a walk over a list and not
      ;; sixty-three thousand conversions.
      (let* ((table (diorisis--lemma-completion))
             (bare (make-hash-table :test #'equal)))
        (dolist (entry (nth 3 table))
          ;; (BARE BETA GREEK COUNT), as `--lemma-completion' builds it.
          (puthash (nth 2 entry) (nth 0 entry) bare))
        (setq diorisis--candidate-cache
              (cons stamp
                    (mapcar (lambda (candidate)
                              (cons candidate
                                    (or (gethash candidate bare)
                                        (diorisis--bare candidate))))
                            (nth 0 table))))))
    (cdr diorisis--candidate-cache)))

(defun diorisis--filter (input candidates)
  "The CANDIDATES that INPUT points at, prefixes first.

THE RULE, WHICH IS THE WHOLE POINT OF THE STYLE.  Input is converted to Greek
whether it was typed as beta code or as Greek -- so `mu/w' and `μύω' are one
question -- and then:

  WITH DIACRITICS, matched against the candidates as they are spelled, so
  `mu/' reaches μύω and not μυῶν: the marks were typed and are meant.

  WITHOUT, matched against the candidates with their diacritics taken off,
  so `muw' and `μυω' reach μύω, μυῶν and μύωψ alike -- which is what a
  reader unsure where the breathing goes needs, and is the common case.

Prefixes are offered before the middle of a word, and the middle only where no
prefix matches: `lo' means λόγος before it means ἀναλογία."
  (let* ((greek (diorisis--input-greek input))
         (marked (diorisis--marked-p input))
         (needle (if marked greek (diorisis--bare greek)))
         (get (if marked #'car #'cdr)))
    (if (string-empty-p needle)
        (mapcar #'car candidates)
      (let ((prefixes nil)
            (inside nil))
        (dolist (pair candidates)
          (let ((against (funcall get pair)))
            (cond ((string-prefix-p needle against) (push (car pair) prefixes))
                  ((string-search needle against) (push (car pair) inside)))))
        (or (nreverse prefixes) (nreverse inside))))))

(defun diorisis--style-all (string _table pred _point)
  "Every completion of STRING, by our own rule.

THE CACHED CANDIDATES AND NOT THE TABLE\='S, deliberately.  The style is
registered for one category, which one prompt announces, so the two are the
same set -- and asking the table instead cost a `member\=' over sixty-three
thousand candidates for each of sixty-three thousand candidates, which is
four billion comparisons at every keystroke.  The prompt was not failing to
match; it was dead.

A PREDICATE IS STILL HONOURED, that being cheap: it is called once per
candidate, not once per pair of them."
  (let ((pairs (or diorisis--completion-pairs
                   (diorisis--candidate-pairs))))
    (when pred
      (setq pairs (seq-filter (lambda (pair) (funcall pred (car pair)))
                              pairs)))
    (diorisis--filter string pairs)))

(defun diorisis-show-matches (input)
  "Say which lemmata INPUT matches, without a completion prompt in the way.

FOR TELLING WHOSE FAULT IT IS.  A prompt that shows nothing may be the
matching rule, the conversion from beta code, the completion framework, or a
cache built before Diogenes was loaded -- and from inside the minibuffer they
all look alike.  This calls the matcher directly and says what it got, so the
answer names the layer."
  (interactive "sInput (beta code or Greek): ")
  (let* ((greek (diorisis--input-greek input))
         (matches (diorisis--style-all input nil nil 0)))
    (message "%s -> %s (%s) : %d matches%s"
             input greek
             (if (diorisis--marked-p input) "with diacritics"
               "diacritics ignored")
             (length matches)
             (if matches
                 (format " -- %s" (string-join (seq-take matches 12) ", "))
               ""))))

(defun diorisis--style-try (string table pred point)
  "Complete STRING in TABLE as far as it goes.

A SINGLE MATCH IS TAKEN and anything else is left as typed: the interesting
work is in `diorisis--style-all', which is what a framework displays, and
`TAB' has nothing useful to do with forty Greek words beyond showing them."
  (let ((matches (diorisis--style-all string table pred point)))
    (cond
     ((null matches) nil)
     ((and (null (cdr matches)) (not (equal (car matches) string)))
      (cons (car matches) (length (car matches))))
     (t (cons string point)))))

(add-to-list 'completion-styles-alist
             '(tei-diorisis-greek
               diorisis--style-try
               diorisis--style-all
               "Greek lemmata by beta code or Unicode, diacritics optional."))

(add-to-list 'completion-category-overrides
             '(tei-diorisis-lemma (styles tei-diorisis-greek)))

(defcustom diorisis-lemma-greek-width 18
  "How wide the Greek column is in the lemma prompt, in display columns.

The beta code follows the Greek in each candidate -- see
`diorisis--lemma-completion-table\=' for why it is there and not in an
annotation -- and this pads the Greek so that the beta lines up down the page.
A column that wandered with the length of each Greek word would be harder to
read than no column at all.

Eighteen, because `a)/nqrwpos\=' converted is nine and the compounds run to
about eighteen.  Nil for a single space and no alignment."
  :type '(choice (const :tag "No column, one space" nil) integer)
  :group 'diorisis)

(defun diorisis--lemma-candidate (greek beta)
  "GREEK and BETA as one completion candidate.

BOTH IN THE CANDIDATE, because nothing matches against an annotation.  The
beta code was one, so `le/gw\=' matched no candidate and the prompt relied on
the framework passing an unmatched string through to
`diorisis--approximate\=' -- which vertico does and helm does not.  In the
candidate it matches by substring under either, and under anything else."
  (if (and beta (not (string= beta greek)))
      (concat (if diorisis-lemma-greek-width
                  (truncate-string-to-width
                   greek diorisis-lemma-greek-width nil ?\s)
                greek)
              "  " beta
              ;; AND THE BARE LETTERS, MATCHABLE BUT UNSEEN.  le/g matches
              ;; the beta and leg matches nothing, the slash being in the
              ;; way -- so the letters alone go in too, the diacritics
              ;; being optional here as they are in the approximation.
              ;;
              ;; INVISIBLE, because a column of legw beside le/gw is noise
              ;; to read: the property hides it from the display and leaves
              ;; it in the string the styles compare against.  Left off
              ;; where the two are the same, a word with no diacritics
              ;; having nothing to add.
              (let ((plain (ignore-errors (diorisis--bare beta))))
                (and plain (not (string= plain beta))
                     (propertize (concat "  " plain)
                                 'invisible t))))
    greek))

(defun diorisis--lemma-candidate-greek (candidate)
  "The Greek part of CANDIDATE, which is what the tables are keyed on.
Two spaces separate it from the beta code, and neither a Greek lemma nor a
beta one contains two spaces."
  (car (split-string candidate "  " t)))

(defun diorisis--lemma-completion-table (candidates counts beta)
  "CANDIDATES as a completion table that announces our category.

AND IN OUR OWN ORDER.  `display-sort-function' is `identity' so that the
frequencies decide what a reader sees first: filtered to forty candidates, the
one wanted is far likelier to be the common word than the alphabetically first
one."
  ;; THE BETA IN THE CANDIDATE AND THE COUNT IN THE ANNOTATION.  Nothing
  ;; matches against an annotation, so the beta was unmatchable and the prompt
  ;; relied on the framework passing an unmatched string through -- which
  ;; vertico does and helm does not.  The count stays out of the matching
  ;; because nobody searches by frequency.
  (let* ((shown (mapcar (lambda (greek)
                          (diorisis--lemma-candidate
                           greek (gethash greek beta)))
                        candidates))
         (greek-of (let ((h (make-hash-table :test 'equal)))
                     (dolist (candidate shown h)
                       (puthash candidate
                                (diorisis--lemma-candidate-greek candidate)
                                h)))))
   (lambda (string predicate action)
    (pcase action
      ('metadata
       `(metadata
         (category . diorisis-lemma)
         (annotation-function
          . ,(lambda (candidate)
               (let ((count (gethash (gethash candidate greek-of candidate)
                                     counts)))
                 (and count (format "   %d" count)))))
         (display-sort-function . identity)
         (cycle-sort-function . identity)))
      (_ (complete-with-action action shown string predicate))))))

(defun diorisis--approximate (input)
  "The lemmata INPUT might mean, as (BETA GREEK COUNT), likeliest first.

WHAT AN APPROXIMATION IS.  Beta code or Greek, with the diacritics or
without them, and `%' as a wildcard anywhere: `mu/w', `muw', `μύω',
`μυω' and `mu%' all reach `mu/w'.

The comparison is on the letters alone -- what `diorisis--bare' leaves
of either script -- so nothing depends on the reader knowing where the
breathing goes, and half a word is enough to find the word.

PREFIXES FIRST, AND THE MIDDLE ONLY IF THEY FAIL.  A reader typing `lo'
means `lo/gos' before they mean `a)nalogi/a', and four hundred lemmata that
merely contain the letters would bury the one they were after.  Where no
prefix matches, the middle is tried, that being better than an empty
prompt."
  (let* ((table (diorisis--lemma-completion))
         (bare (nth 3 table))
         (wanted (diorisis--bare
                  (diorisis--greek (diorisis--beta input))))
         ;; A WILDCARD SURVIVES THE BARING, which strips everything that is
         ;; not a letter -- so it is looked for in the input and put back as a
         ;; regexp.
         ;; SPLIT ON THE WILDCARD BEFORE BARING, and not after.  Baring keeps
         ;; the letters and throws away everything else -- which is the whole
         ;; point of it, and includes the `%': a pattern bared first came out
         ;; as a plain word and matched only itself.
         (pattern (and (string-search "%" input)
                       (concat "\\`"
                               (mapconcat
                                (lambda (piece)
                                  (regexp-quote
                                   (diorisis--bare
                                    (diorisis--greek
                                     (diorisis--beta piece)))))
                                (split-string input "%")
                                ".*")
                               "\\'")))
         (matching
          (lambda (test)
            (delq nil (mapcar (lambda (entry)
                                (and (car entry)
                                     (funcall test (car entry))
                                     (list (nth 1 entry) (nth 2 entry)
                                           (nth 3 entry))))
                              bare))))
         (found
          (cond
           ((string-empty-p wanted) nil)
           (pattern (funcall matching
                             (lambda (one) (string-match-p pattern one))))
           (t (or (funcall matching
                           (lambda (one) (string-prefix-p wanted one)))
                  (funcall matching
                           (lambda (one) (string-search wanted one))))))))
    ;; THE COMMONEST FIRST, the counts being the only thing here that says
    ;; which of forty candidates a reader is likely to have meant.
    (sort found (lambda (a b) (> (or (nth 2 a) 0) (or (nth 2 b) 0))))))

(defun diorisis--choose-lemma (found input)
  "Ask which of FOUND was meant, INPUT having been an approximation."
  (pcase (length found)
    (0 nil)
    (1 (message "%s: %s" input (nth 1 (car found)))
       (car (car found)))
    (_
     (let ((labels (mapcar (lambda (entry)
                             (cons (format "%-20s %-16s %d"
                                           (nth 1 entry) (nth 0 entry)
                                           (or (nth 2 entry) 0))
                                   (nth 0 entry)))
                           found)))
       (cdr (assoc (completing-read (format "%s -- which lemma? " input)
                                    labels nil t)
                   labels))))))

(defun diorisis-lemmata-of-form (form)
  "Every lemma the corpus assigns to FORM, as (LEMMA . COUNT), commonest first.

THE CORPUS SETTLES IT.  A form is not a word: `memuko/tos' is a form of `mu/w'
and the corpus says so, having been lemmatised and disambiguated -- which is a
better answer than a parser's, and is the answer this database exists to give.
Several where the form is genuinely ambiguous across lemmata, and the counts
say which reading is the common one.

Not indexed unless `diorisis-index-forms' has been run, so this is a
column read: seconds on the real corpus, and worth it once to turn a form into
the lemma the rest of the search is answered by."
  (let ((beta (diorisis--beta form)))
    (mapcar (lambda (row) (cons (nth 0 row) (nth 1 row)))
            (diorisis--select
             "SELECT lemma, COUNT(*) FROM occurrences WHERE form = ?\
 GROUP BY lemma ORDER BY 2 DESC"
             (list beta)))))

(defun diorisis-lemma-of-form (form &optional quietly)
  "The one lemma FORM belongs to, asking where the corpus gives several.
Nil where the corpus has no such form.  QUIETLY suppresses the message saying
what was settled."
  (let ((lemmata (diorisis-lemmata-of-form form)))
    (cond
     ((null lemmata) nil)
     ((= (length lemmata) 1)
      (unless quietly
        (message "%s is a form of %s"
                 (diorisis--greek (diorisis--beta form))
                 (diorisis--greek (car (car lemmata)))))
      (car (car lemmata)))
     (t
      ;; SEVERAL, AND THE READER CHOOSES.  Guessing the commonest would be
      ;; right most of the time and wrong silently, which is the one thing
      ;; this project keeps refusing to do.
      (let* ((labels (mapcar (lambda (entry)
                               (cons (format "%-18s %d occurrences"
                                             (diorisis--greek
                                              (car entry))
                                             (cdr entry))
                                     (car entry)))
                             lemmata))
             (chosen (completing-read
                      (format "%s is a form of: "
                              (diorisis--greek
                               (diorisis--beta form)))
                      labels nil t)))
        (cdr (assoc chosen labels)))))))

(defun diorisis-read-lemma (&optional prompt initial)
  "Read a lemma and return it as beta code.

TYPE ANYTHING THAT POINTS AT IT.  The prompt completes on the corpus's own
63,718 lemmata in Greek, and what is typed need not be one of them: beta code,
Greek, either without its diacritics, `%' as a wildcard, or an inflected form.
Whatever it is, it is turned into the lemmata it could mean and -- where there
is more than one -- the reader is shown them with their frequencies and
chooses.

WHY THE COMPLETION ALONE WOULD NOT DO.  The candidates are accented Greek, so
`μυω' matches none of them and `mu/w' matches none of them either: the one
thing the prompt would not accept was the two ways a classicist actually
types.  Narrowing by approximation happens after the prompt rather than inside
it, which works whatever completion framework a reader has -- and gives a
second, shorter list to choose from, which is the point."
  (let* ((table (diorisis--lemma-completion))
         (candidates (nth 0 table))
         (beta (nth 1 table))
         (counts (nth 2 table))
         (table (diorisis--lemma-completion-table candidates counts beta))
         (answer (string-trim
                  (completing-read (or prompt
                                       "Lemma (Greek or beta, accents \
optional): ")
                                   table nil nil initial))))
    ;; WHAT COMES BACK may be a candidate, or whatever was typed where the
    ;; framework allowed it through.  Both are handled below, in order of how
    ;; exact they are.
    ;;
    ;; A CANDIDATE NOW CARRIES ITS BETA CODE, so that beta matches under any
    ;; framework -- see `diorisis--lemma-candidate'.  The Greek is cut back
    ;; out here, the tables below being keyed on it, and a string that was
    ;; typed rather than chosen has no two spaces in it and comes through
    ;; unchanged.
    (setq answer (diorisis--lemma-candidate-greek answer))
    (or
     ;; A lemma chosen from the list.
     (gethash answer beta)
     ;; A LEMMA TYPED, and known.  A reader who knows the word list types beta
     ;; code and is not made to complete on it.
     (let ((typed (diorisis--beta answer)))
       (and (gethash (diorisis--greek typed) beta) typed))
     ;; OR AN APPROXIMATION of one, which is the common case: the accents left
     ;; off, or beta code, or half the word and a wildcard.
     (diorisis--choose-lemma (diorisis--approximate answer) answer)
     ;; OR A FORM, which the corpus settles.  `memuko/tos' is not a lemma and
     ;; matches no lemma by approximation either; it is a form of `mu/w', the
     ;; corpus says which, and what the reader meant was the word.
     (diorisis-lemma-of-form answer)
     ;; Or something the corpus has never seen, which is the reader's answer
     ;; and is searched for as given -- finding nothing being the right report.
     (diorisis--beta answer))))

(defun diorisis--column (column)
  "Every value of COLUMN in `texts\\=', for completion.

The catalogue is 817 rows: asking it for its genres costs nothing, and asking
it is better than keeping a list of them here that a new catalogue would
falsify."
  (delq nil (mapcar #'car
                    (diorisis--select
                     (format "SELECT DISTINCT %s FROM texts\
 WHERE %s IS NOT NULL AND %s <> '' ORDER BY %s"
                             column column column column)))))

(defun diorisis-read-text ()
  "Read an author and a work, and return (AUTHOR-ID . WORK-ID).

WORK-ID nil for the whole author.  ASKED FOR TOGETHER because a work number
means nothing without an author -- `018\\=' is the Charmides only of Plato -- and
asking for them as two independent narrowings would let a reader set the
second and not the first and search every author\\='s eighteenth work."
  (let* ((authors (diorisis--select
                   "SELECT DISTINCT author_id, author FROM texts\
 ORDER BY author"))
         (labels (mapcar (lambda (row)
                           (cons (format "%s (%s)" (or (nth 1 row) "?")
                                         (nth 0 row))
                                 (nth 0 row)))
                         authors))
         (author (cdr (assoc (completing-read "Author: " labels nil t)
                             labels)))
         (works (diorisis--select
                 "SELECT work_id, work, words FROM texts\
 WHERE author_id = ? ORDER BY work_id"
                 (list author)))
         (choices (cons (cons "All of them" nil)
                        (mapcar (lambda (row)
                                  (cons (format "%s (%s), %s words"
                                                (or (nth 1 row) "?")
                                                (nth 0 row)
                                                (or (nth 2 row) "?"))
                                        (nth 0 row)))
                                works))))
    (cons author
          (cdr (assoc (completing-read "Work: " choices nil t) choices)))))

(defun diorisis--levels (location)
  "LOCATION as the levels of a citation, as strings.

    \"1.19.5\"    -> (\"1\" \"19\" \"5\")
    \"153c\"      -> (\"153c\")
    \"'513.3'\"   -> (\"513\" \"3\")

THREE THINGS ABOUT THIS COLUMN.  It is not uniformly shaped: one level for
Aristides, three for Aelian, four for Achilles Tatius, and a Stephanus page is
not a number.  Some values carry QUOTATION MARKS INSIDE THE VALUE -- `\\='513.3\\='
is how the corpus holds Aristides, who is cited by Dindorf page -- and those
have to come off or the first level is not a number and nothing will open.
And the levels are strings by the time Diogenes takes them, which is what
`classicist-citation-from-key\\=' returns and what `classicist-open-passage\\=' takes,
so no attempt is made to guess which were numbers.

Nil where LOCATION is empty or is nothing but punctuation, which is a work to
be opened at its beginning rather than an error."
  (when location
    (let ((clean (string-trim
                  (replace-regexp-in-string "[\"'`]" "" location))))
      (unless (string-empty-p clean)
        (split-string clean "[.]" t "[ \t]+")))))

(defun diorisis--work-number (hit)
  "The work number to ask Diogenes\=' browser for.

THE TLG'S, WHERE WE KNOW IT DIFFERS FROM OURS.  Ours is the key of the index
and stays what it is; the browser is asked for the number the TLG uses, which
for nineteen texts is not the same thing -- Diorisis numbers Euripides\='
Hecuba 040 and the TLG numbers it 007.

AND WITHOUT THE PART LETTER.  Six of those nineteen are not renumberings at
all: `0007-051b\=' is the second part of Plutarch\='s Agis and Cleomenes, which
Diorisis keeps as two files and the TLG as one work, 051.  Asking the browser
for `051b\=' would fail where asking for ours succeeded, so the letter comes
off -- it says which half of the work a text is, and the work is what can be
opened.  What is lost by dropping it is nothing the browser could have used."
  (let ((tlg (plist-get hit :tlg-work-id)))
    (or (and tlg (stringp tlg)
             (let ((bare (replace-regexp-in-string "[a-z]+\\'" "" tlg)))
               (and (not (string-empty-p bare)) bare)))
        (plist-get hit :work-id))))

(defun diorisis--citation (hit)
  "HIT's citation, as a reader writes it."
  (let ((levels (diorisis--levels (plist-get hit :location))))
    (if levels (mapconcat #'identity levels ".") "?")))

(defun diorisis--interval (hit)
  "How far HIT's sentence runs, as (FROM . TO), or nil for a point.

THE SENTENCE IS NOT THE LINE.  It begins where the citation says and ends
somewhere at or before the next sentence begins, so a hit spans an interval
and is worth saying so: a note made on `3.806\=' alone omits the half of the
sentence that is in 3.807.

Nil rather than a guess in three cases.  Where the next sentence begins on
the same citation -- two sentences to a line, which stichomythia is full of
-- there is nothing to add.  Where the next STORED sentence is not the next
sentence, our table having a gap there, the bound may be a hundred lines out
and a wrong interval is worse than none.  And where either citation will not
parse."
  (let* ((from (diorisis--levels (plist-get hit :location)))
         (to (diorisis--levels (plist-get hit :next-location)))
         (mine (plist-get hit :sentence))
         (next (plist-get hit :next-sentence)))
    (and from to mine next
         (numberp mine) (numberp next)
         (= next (1+ mine))
         (not (equal from to))
         (cons from to))))

(defun diorisis--citation-string (hit)
  "HIT's citation, as an interval where it is one.

    (\"3\" \"806\") to (\"3\" \"807\")   ->   3.806-807

THE LEVELS IN COMMON ARE SAID ONCE, as a reader writes them: `3.806-807\=' and
not `3.806-3.807\='.  The reversible form is what a LINK wants and is
`classicist-citation-to-key\='s business; this is for reading."
  (let* ((interval (diorisis--interval hit))
         (from (car interval))
         (to (cdr interval)))
    (if (not interval)
        (diorisis--citation hit)
      (let ((shared 0))
        (while (and (< shared (length from))
                    (< shared (1- (length to)))
                    (equal (nth shared from) (nth shared to)))
          (setq shared (1+ shared)))
        (format "%s-%s"
                (mapconcat #'identity from ".")
                (mapconcat #'identity (nthcdr shared to) "."))))))

(defcustom diorisis-display-kind 'search
  "Which kind of Diogenes buffer the hits count as, for display.

A category of its own by default, so that `diogenes-window-behaviour' can
speak about it -- `(diorisis . split)' in the alist -- without saying anything
about the browser or the lookups.

Set it to `browser', `lookup' or `morphology' to have the hits displayed
wherever those go; nil for none of Diogenes' arrangements at all, which means
plain `pop-to-buffer' and whatever the reader's own `display-buffer-alist'
says."
  :type '(choice (const :tag "Its own category" diorisis)
                 (const :tag "As a browser" browser)
                 (const :tag "As a lookup" lookup)
                 (const :tag "As an analysis" morphology)
                 (const :tag "None of them" nil)
                 symbol)
  :group 'diorisis)

(defcustom diorisis-display-action nil
  "Where the hits appear, as a `display-buffer' action, or nil.

Nil leaves it to `diorisis-display-kind' and whatever the reader has told
Diogenes about that kind.  An action here is the reader's own answer and
outranks all of it:

    (setq diorisis-display-action
          \='((display-buffer-in-side-window)
            (side . right)
            (window-width . 0.4)))"
  :type '(choice (const :tag "Follow the kind" nil)
                 (sexp :tag "A display-buffer action"))
  :group 'diorisis)

(defcustom diorisis-aside-display-kind 'morphology
  "Which kind the sentence and the distribution count as.

`morphology' because that is the same thing: Diogenes displays an analysis as
a morphology buffer precisely so it does not replace the entry it was asked
about, and a sentence shown from the hit list must not replace the hit list."
  :type '(choice (const :tag "As an analysis" morphology)
                 (const :tag "As a lookup" lookup)
                 (const :tag "Its own category" diorisis)
                 (const :tag "None of them" nil)
                 symbol)
  :group 'diorisis)

(defcustom diorisis-aside-display-action nil
  "Where the sentence and the distribution appear, or nil for the kind."
  :type '(choice (const :tag "Follow the kind" nil)
                 (sexp :tag "A display-buffer action"))
  :group 'diorisis)

(defun diorisis--display (buffer &optional aside)
  "Show BUFFER, ASIDE for the sentence and the distribution.

The hits are displayed AND SELECTED -- a reader who has searched is going to
read the hits.  An aside is displayed and not selected: point belongs in the
list, and a sentence shown beside it is something to glance at.

A BUFFER ALREADY ON SCREEN IS LEFT WHERE IT IS.  Every command that rewrites
one of these buffers ends by displaying it again -- emptying the workbook
redraws the workbook, `x\=' redraws the explanation -- and `pop-to-buffer\='
asked a second time opens a SECOND window onto a buffer already visible.  So
a window showing it is selected, or, for an aside, left alone."
  (let ((kind (if aside diorisis-aside-display-kind
                diorisis-display-kind))
        (action (if aside diorisis-aside-display-action
                  diorisis-display-action)))
    (cond
     ;; ALREADY ON SCREEN: select that window, or leave it be for an aside.
     ((get-buffer-window buffer t)
      (unless aside (select-window (get-buffer-window buffer t))))
     ((and kind (fboundp 'classicist-display-buffer))
      (apply #'classicist-display-buffer buffer
             (append (list :kind kind)
                     (and action (list :action action))
                     (and aside (list :no-select t)))))
     (aside (display-buffer buffer action))
     (t (pop-to-buffer buffer action)))))

(defvar-local diorisis--spec nil
  "The search this buffer is showing, so that it can be run again.")

(defvar-local diorisis--total nil
  "How many hits there were, as against how many are shown.")

(defun diorisis--snippet (hit)
  "HIT\='s sentence in Greek, a window of it, every word the query matched marked.

THE WINDOW RATHER THAN THE HEAD.  Sentences in this corpus run to three
hundred characters and the word searched for may be at the end of one, so a
snippet taken from the beginning would often not hold the word the reader
asked about.

EVERY MATCHED WORD AND NOT ONLY THE FIRST, and the window drawn to hold them
all.  A query of three elements finds three words: this marked one of them and
placed the window around it, so the other two were often outside the snippet
and the sentence looked as though it had been found for no reason.  The other
elements\=' forms come back with the hit -- see `diorisis-hits\=' -- and
the window now runs from the first of them to the last, widening as far as
`diorisis-snippet-width\=' allows and preferring to cut the tail over
losing a match.

Each form is looked for in the CONVERTED sentence, that being where the
highlight goes; one not found -- a crasis, a form the sentence spells
otherwise -- is passed over, a hit being worth listing without one of its
marks."
  (let ((words (plist-get hit :words)))
    (if (or (null words) (string-empty-p words))
        (propertize "[the corpus keeps no sentence here]" 'face 'shadow)
      (let* ((text (diorisis--greek words))
             (forms (delete-dups
                     (delq nil
                           (mapcar
                            (lambda (one)
                              (and one (not (string-empty-p one))
                                   (diorisis--greek one)))
                            (cons (plist-get hit :form)
                                  (plist-get hit :others))))))
             (places (delq nil
                           (mapcar (lambda (form)
                                     (let ((at (string-search form text)))
                                       (and at (cons at (length form)))))
                                   forms)))
             (width diorisis-snippet-width)
             (first (if places (apply #'min (mapcar #'car places)) 0))
             (last (if places
                       (apply #'max (mapcar (lambda (place)
                                               (+ (car place) (cdr place)))
                                             places))
                     0))
             ;; FROM THE FIRST MATCH, back a little for context, and forward
             ;; as far as the width allows.  Where the matches are further
             ;; apart than the window is wide there is nothing to be done but
             ;; show the first of them and cut: a sentence of three hundred
             ;; characters with a match at each end does not fit in eighty.
             ;; THE WIDTH IS A WIDTH.  This let `end' run out to the last
             ;; match however far off it was, so a sentence with matches
             ;; four hundred characters apart printed four hundred
             ;; characters and a page of Plutarch arrived where a line was
             ;; asked for.  The window is `width' wide; where the matches
             ;; will not all fit in it, it is placed on the FIRST of them and
             ;; the others are outside -- a snippet being a snippet, and `v'
             ;; showing the whole sentence for the cases that matter.
             (start (max 0 (- first (/ width 6))))
             (start (if (<= (- last start) width)
                        (max 0 (min start (- last width)))
                      start))
             (end (min (length text) (+ start width)))
             (piece (concat (if (> start 0) "\u2026 " "")
                            (substring text start end)
                            (if (< end (length text)) " \u2026" ""))))
        ;; MARKED IN THE PIECE AND NOT IN THE SENTENCE, the offsets being
        ;; different once the window and its ellipsis are in front.
        (dolist (form forms)
          (let ((from 0))
            (while (let ((here (string-search form piece from)))
                     (when here
                       (put-text-property here (+ here (length form))
                                          'face 'match piece)
                       (setq from (+ here (length form)))
                       t)))))
        piece))))

(defun diorisis--describe (spec)
  "SPEC as a line saying what was searched for."
  (let ((parts nil))
    (dolist (pair (list (cons :lemma "lemma")
                        (cons :form "form")
                        (cons :pos nil)
                        (cons :morph "morphology")
                        (cons :genre nil)
                        (cons :subgenre nil)))
      (let ((value (plist-get spec (car pair))))
        (when (and value (stringp value) (not (string-empty-p value)))
          (push (if (cdr pair)
                    (format "%s %s" (cdr pair)
                            (if (memq (car pair) '(:lemma :form))
                                (diorisis--greek
                                 (diorisis--beta value))
                              value))
                  value)
                parts))))
    (let ((from (plist-get spec :from))
          (to (plist-get spec :to)))
      (when (or from to)
        (push (cond ((and from to)
                     (format "%s to %s"
                             (diorisis--year (number-to-string from))
                             (diorisis--year (number-to-string to))))
                    (from (format "not before %s"
                                  (diorisis--year
                                   (number-to-string from))))
                    (t (format "not after %s"
                               (diorisis--year
                                (number-to-string to)))))
              parts)))
    (when (plist-get spec :author)
      (push (format "author %s%s" (plist-get spec :author)
                    (if (plist-get spec :work)
                        (format ", work %s" (plist-get spec :work))
                      ""))
            parts))
    (when (plist-get spec :confidence)
      (push (format "confidence at least %s" (plist-get spec :confidence))
            parts))
    (when (plist-get spec :unambiguous)
      (push "unambiguous forms only" parts))
    (mapconcat #'identity (nreverse parts) " · ")))

(defun diorisis--insert-hit (hit)
  "Print HIT: where it is, as a button, and what it says."
  (let* ((citation (diorisis--citation-string hit))
         (start (point))
         (date (diorisis--year (plist-get hit :date)))
         (aside (string-join
                 (delq nil (list (plist-get hit :genre) date))
                 ", ")))
    ;; THE CITATION AS A BUTTON, which is the whole point of a results buffer
    ;; in Emacs rather than a list of places to go and look: the hit is the
    ;; way into the text.  The author and the work are inside the button too,
    ;; a button of five characters being hard to hit and the whole line being
    ;; what a reader means when they click on a hit.
    (insert-text-button
     (format "%s, %s %s"
             (or (plist-get hit :author) "?")
             (or (plist-get hit :work) "?")
             citation)
     'face 'link
     'help-echo "Open this passage in Diogenes' browser, at its first line"
     'tei-diorisis-hit hit
     'action #'diorisis--button)
    (when (and aside (not (string-empty-p aside)))
      (insert (propertize (format "   (%s)" aside) 'face 'shadow)))
    ;; A HIT WHOSE SENTENCE HAS A TREE says so: the work is done and `A' will
    ;; open it rather than begin again.
    (when (ignore-errors (treebank-annotation-for hit))
      (insert (propertize "  [tree]" 'face 'diorisis-form-face)))
    (insert "\n    " (diorisis--snippet hit) "\n\n")
    ;; THE HIT ON EVERY CHARACTER OF ITS ENTRY, not only on its button.  `n'
    ;; and `p' move by this property and `RET' reads it, so a reader whose
    ;; point is in the middle of a snippet is still on a hit -- which is where
    ;; point lands after scrolling, and it would be strange for `RET' to do
    ;; nothing there.
    (put-text-property start (point) 'tei-diorisis-hit hit)))

(defun diorisis--render (spec hits total)
  "Print HITS, being TOTAL of them, as SPEC asked for."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize (format "%d %s" total
                                (if (= total 1) "hit" "hits"))
                        'face 'bold))
    (when (< (length hits) total)
      (insert (format ", showing %d" (length hits))))
    (insert "\n")
    (let ((said (diorisis--describe spec)))
      (unless (string-empty-p said)
        (insert (propertize said 'face 'font-lock-comment-face) "\n")))
    (insert (propertize
             (concat "RET opens the passage · v shows the sentence · "
                     "C-c C-c parses a word · l looks the lemma up\n"
                     "d counts by author · + for more · g searches again\n"
                     "c collects for the workbook · C all of them "
                     "· b opens it · A annotates\n\n")
             'face 'shadow))
    (if (null hits)
        (insert "Nothing.\n")
      (dolist (hit hits) (diorisis--insert-hit hit)))
    (setq diorisis--spec spec)
    (setq diorisis--total total)
    (goto-char (point-min))
    (set-buffer-modified-p nil)))

(defun diorisis--show (spec)
  "Search for SPEC and show the hits."
  ;; COUNTED FIRST.  A reader wants to know that there are four thousand
  ;; before reading the first two hundred, and the count is a cheaper query
  ;; than the hits -- no sentences joined.
  (let* ((total (diorisis-count spec))
         (hits (and (> total 0) (diorisis-hits spec)))
         (buffer (get-buffer-create "*Diorisis*")))
    (with-current-buffer buffer
      (diorisis-results-mode)
      (diorisis--render spec hits total))
    (diorisis--display buffer)
    (message "%d %s" total (if (= total 1) "occurrence" "occurrences"))))

(defun diorisis--hit-at (&optional position)
  "The hit at POSITION, or at point, or an error."
  (or (get-text-property (or position (point)) 'tei-diorisis-hit)
      (user-error "No hit here")))

(defun diorisis--button (button)
  "Open the passage BUTTON stands for."
  (let ((hit (get-text-property (button-start button) 'tei-diorisis-hit)))
    (diorisis-open-hit hit)))

(defun diorisis-open-hit (&optional hit)
  "Open HIT's passage in Diogenes' browser, or the one at point.

THE NUMBERS ARE DIOGENES' OWN -- `0059'/`018' is Plato's Charmides in both --
so there is nothing to convert: the author, the work and the citation go
straight to `classicist-open-passage', which is the public, non-interactive way
in and asks nothing.

Where the citation will not do -- a location that is not shaped like the
work's levels, a work Diogenes numbers otherwise -- the work is opened at its
beginning and the reader is told why.  A hit that cannot be opened exactly is
still a hit in a text one can read."
  (interactive)
  (let* ((hit (or hit (diorisis--hit-at)))
         (author (plist-get hit :author-id))
         (work (diorisis--work-number hit))
         (levels (diorisis--levels (plist-get hit :location))))
    (unless (diorisis--open hit author work levels)
      (user-error
       "Nothing could open %s %s at %s: see diorisis-open-with"
       author work (diorisis--citation hit)))))

(defun diorisis--open (hit author work levels)
  "Open HIT somewhere, and say whether anything did.

EACH IN TURN, and the order is the reader's.  A hit is worth opening in the
edition where there is one to open, and worth opening HERE where there is not:
the sentences are in the index, so a reader with no CD-ROM databases at all
still gets the passage rather than a link that leads nowhere."
  (let ((opened nil))
    (dolist (where diorisis-open-with)
      (unless opened
        (pcase where
          ('diogenes
           (when (and (or (featurep 'classicist-browser)
                          (and (locate-library "classicist-browser")
                               (require 'classicist-browser nil t)))
                      (fboundp 'classicist-open-passage))
             ;; A CITATION THAT WILL NOT DO is not a reason to give up on
             ;; Diogenes: the work opens at its head and the reader is told
             ;; why, which is what happened before and is still better than
             ;; nothing.  It is not marked -- a marking put on the first line
             ;; of a work would be a lie about where the hit is.
             (setq opened
                   (condition-case error
                       (progn
                         (diorisis--mark-when-ready
                          (classicist-open-passage diorisis-corpus
                                                 author work levels)
                          hit)
                         t)
                     (error
                      (message "%s would not open (%s); the work instead"
                               (diorisis--citation hit)
                               (error-message-string error))
                      (ignore-errors
                        (classicist-open-passage diorisis-corpus
                                               author work nil)
                        t))))))
          ('diorisis
           ;; OUR OWN NUMBERS HERE, not the TLG's: this is our index, and
           ;; `work' has been translated for Diogenes' sake by the caller.
           (setq opened
                 (condition-case error
                     (let ((buffer (diorisis-open-work
                                    (plist-get hit :author-id)
                                    (plist-get hit :work-id)
                                    (plist-get hit :sentence))))
                       (when buffer
                         (with-current-buffer buffer
                           (diorisis--mark hit))
                         t))
                   (error
                    (message "The Diorisis text would not open: %s"
                             (error-message-string error))
                    nil))))
          (_ nil))))
    opened))

(defface diorisis-passage-face
  '((t :weight bold))
  "Face for the sentence a hit was found in.

BOLD, AND NOTHING ELSE.  It began as `highlight', which is a background, and a
background is too much: the sentence is text to be read, not a region to be
acted on, and a block of colour under four lines of Greek makes the page
harder to read rather than easier.  Weight says the same thing quietly, and
leaves the theme's own colours alone underneath it.

No background also means nothing to fight the form's green, which sits inside
this and must stay legible."
  :group 'diorisis)

(defface diorisis-form-face
  '((((class color) (background dark))
     :foreground "#5fd75f" :weight bold)
    (((class color) (background light))
     :foreground "#006400" :weight bold)
    (t :inherit match :weight bold))
  "Face for the form that was searched for, inside the sentence.

GREEN, as DiorisisSearch marks it, and in the FOREGROUND: the word is part of
the sentence and reads as part of it, which a coloured box behind it would
undo.  A light green on a dark theme and a dark one on a light theme.

THE EXACT GREEN IS A GUESS.  The app bundles its lemma list and filters in
JavaScript and there was no stylesheet to read a value out of, so these two
are chosen to be legible over a plain background rather than copied.  Change
them with \\[customize-face] if you have the app open beside this.

`match' where there is no colour to be had, which is what the results buffer
marks the same word with."
  :group 'diorisis)

(defcustom diorisis-highlight 'both
  "What to mark in the browser when a hit is opened.

`both\=' marks the sentence and the form in it, `passage\=' the sentence only,
`form\=' the word only, and nil nothing -- for a reader who would rather have
the browser as the browser leaves it."
  :type '(choice (const :tag "The sentence and the form" both)
                 (const :tag "The sentence" passage)
                 (const :tag "The form" form)
                 (const :tag "Nothing" nil))
  :group 'diorisis)

(defcustom diorisis-highlight-lasts 'escape
  "How long the marking stays.

`escape' takes it off at escape or `C-g', or on leaving an evil state --
`diorisis-highlight-clear-commands' says which commands count.  The
default: a marking is a thing one dismisses once it has served, and escape is
what the hand reaches for.

`until-cleared' leaves it until `C-c C-u', or until the next hit is opened.
`next-command' takes it off at the first thing the reader does at all, which
is how the browser marks the lines `C-c C-n' has just added -- right for a
marking that says look here, wrong for one a reader wants to keep while
reading around it."
  :type '(choice (const :tag "Until escape or C-g" escape)
                 (const :tag "Until cleared" until-cleared)
                 (const :tag "Until the next command" next-command))
  :group 'diorisis)

(defcustom diorisis-highlight-clear-commands
  '(keyboard-quit minibuffer-keyboard-quit
    evil-force-normal-state evil-normal-state evil-escape
    evil-exit-visual-state evil-insert-state)
  "Which commands take the marking off, where it lasts until escape.

COMMANDS AND NOT KEYS, and for two reasons.  Under evil, binding escape in
our own map does nothing: its state maps are consulted through
`emulation-mode-map-alists', which comes before the minor mode maps, so
escape in normal state is evil's and ours is never reached.  And in vanilla
Emacs ESC is the meta prefix, so binding it would cost the reader every
`M-' command in the buffer.

Reading the command instead works for both, and for whatever else a reader
has bound escape to: the hook looks at what is about to run.  Add to this
list for a setup of your own.  Nothing here requires evil -- the evil
commands are named in case it is there."
  :type '(repeat symbol)
  :group 'diorisis)

(defcustom diorisis-highlight-wait 6.0
  "How long to wait for the browser to deliver the passage, in seconds.

THE PASSAGE ARRIVES LATE.  `classicist-open-passage\=' starts a Perl process and
returns its buffer at once; the text comes in through a process filter some
tenths of a second later.  So the marking cannot be painted where the call
returns -- there is nothing there yet -- and is tried again until the line it
wants exists.  Given up after this long, silently: a reader who has already
started reading does not want a message about a highlight."
  :type 'number
  :group 'diorisis)

(defvar-local diorisis--overlays nil
  "The overlays marking a hit in this buffer.")

(defvar-local diorisis--marked nil
  "The hit this buffer was opened for, so the marking can be put back.")

(defvar-local diorisis--timer nil
  "The timer waiting for the browser to deliver the passage.")

(defun diorisis-unhighlight ()
  "Take the marking off this buffer."
  (interactive)
  (remove-hook 'pre-command-hook #'diorisis-unhighlight t)
  (remove-hook 'pre-command-hook #'diorisis--clear-on-escape t)
  (mapc #'delete-overlay diorisis--overlays)
  (setq diorisis--overlays nil)
  (diorisis-highlight-mode -1))

(defun diorisis--clear-on-escape ()
  "Take the marking off if the command about to run is an escape.

On `pre-command-hook', reading `this-command' -- so the marking goes at
escape, or `C-g', or on leaving an evil state, and survives everything else:
scrolling, paging, a word looked up in the LSJ."
  (when (memq this-command diorisis-highlight-clear-commands)
    (diorisis-unhighlight)))

(defun diorisis-highlight-again ()
  "Mark the hit again, having cleared it."
  (interactive)
  (if diorisis--marked
      (diorisis--mark diorisis--marked)
    (user-error "This buffer was not opened from a Diorisis hit")))

(defvar-keymap diorisis-highlight-mode-map
  :doc "Keys while a Diorisis hit is marked in a browser buffer."
  "C-c C-u" #'diorisis-unhighlight
  "C-c C-y" #'diorisis-highlight-again)

(define-minor-mode diorisis-highlight-mode
  "Minor mode active while a Diorisis hit is marked in this buffer.

ITS OWN MAP, AND ONLY WHILE THERE IS A MARKING.  The alternative was binding
a key in `classicist-browser-mode-map\=', which is another package\='s map and
would take the key from every browser buffer for the sake of the few opened
from a hit.  Here the keys exist exactly when they mean something."
  :lighter " Diorisis"
  :keymap diorisis-highlight-mode-map)

(defun diorisis--bare (string)
  "STRING without its diacritics, and with final sigma made plain.

FOR COMPARING FORMS AND NOTHING ELSE.  The Diorisis token and the TLG\='s own
text are two conversions of two sources: an acute may be a grave at a line\='s
end, a sigma final or not.  The letters agree, and the letters are enough to
find a word in a line."
  (let ((plain (seq-filter
                (lambda (character)
                  ;; LETTERS AND NOTHING ELSE.  The corpus stores a sentence
                  ;; with its stops attached to the words -- `mo/ron.' -- and
                  ;; an elision keeps its apostrophe, so what is compared must
                  ;; be the letters or nothing will match the browser's text.
                  (memq (get-char-code-property character 'general-category)
                        '(Ll Lu Lt Lo Lm)))
                (string-to-list (ucs-normalize-NFD-string string)))))
    (replace-regexp-in-string "ς" "σ" (apply #'string plain))))

(defun diorisis--citation-position (levels)
  "Where the line cited LEVELS begins in this buffer, or nil.

The browser puts the citation on every character of a line as the `cit\='
property -- a list of numbers and symbols, (3 806) -- so the line is found by
reading the property rather than by searching the text, which would find the
citation column of some other line."
  (let ((wanted (mapcar (lambda (level) (format "%s" level)) levels))
        (found nil)
        (position (point-min)))
    (while (and (not found) position (< position (point-max)))
      (let ((here (get-text-property position 'cit)))
        (when (and here
                   (equal (mapcar (lambda (level) (format "%s" level)) here)
                          wanted))
          (setq found position)))
      (setq position (next-single-property-change position 'cit)))
    found))

(defun diorisis--words-at (start end)
  "Every word between START and END, as (BEGINNING END BARE).

WITHOUT THE CITATION COLUMNS.  The browser prints the citation at the head of
each line and a search for words finds the numbers in it, which breaks a run
of words at every line -- and marking that column is the fault this was
written to correct.  `classicist--browser-format-citation\\=' puts
`diogenes-citation\\=' on it, so it can be told from the text rather than
guessed at by position."
  (let ((words nil))
    (save-excursion
      (goto-char start)
      (while (re-search-forward "[[:word:]]+" end t)
        (unless (get-text-property (match-beginning 0) 'diogenes-citation)
          (push (list (match-beginning 0) (match-end 0)
                      (diorisis--bare (match-string 0)))
                words))))
    (nreverse words)))

(defun diorisis--phrase (hit start end)
  "Where HIT\\='s sentence begins and ends in the text between START and END.

Returns (FROM . TO), or nil where the sentence could not be placed.

THE SENTENCE AND NOT THE LINES.  Marking whole lines was wrong twice over: it
took in the end of the sentence before -- one line holding the close of one
and the opening of the next -- and it took in the citation column, which is
the one thing in a line that is not the text.

So the sentence is found by its own WORDS: its first and its last, looked for
among the browser\\='s and compared bare.  The last is looked for from the end
backwards, a common word being able to fall twice in a sentence and the
longer reading being the sentence."
  (let* ((words (plist-get hit :words))
         (tokens (and words
                      (delq nil
                            (mapcar (lambda (token)
                                      (let ((bare (diorisis--bare token)))
                                        (and (not (string-empty-p bare))
                                             bare)))
                                    (split-string
                                     (diorisis--greek words)
                                     "[[:space:]]+" t)))))
         (here (diorisis--words-at start end)))
    (when (and tokens here)
      (let ((from (seq-find (lambda (word)
                              (equal (nth 2 word) (car tokens)))
                            here))
            (to (seq-find (lambda (word)
                            (equal (nth 2 word) (car (last tokens))))
                          (reverse here))))
        (when from
          (cons (nth 0 from)
                (max (nth 1 from) (if to (nth 1 to) 0))))))))

(defun diorisis--mark (hit)
  "Mark HIT's sentence and form in this buffer, and say whether it worked."
  (diorisis-unhighlight)
  (setq diorisis--marked hit)
  (let* ((interval (diorisis--interval hit))
         (from (or (car interval)
                   (diorisis--levels (plist-get hit :location))))
         (to (cdr interval))
         (start (and from (diorisis--citation-position from))))
    (when start
      (let* ((last (and to (diorisis--citation-position to)))
             ;; THE RANGE TO SEARCH, which is not the marking.  A line past
             ;; the last citation, a sentence ending inside the line the next
             ;; one begins on; and two lines from the first where the second
             ;; has not arrived, a page being able to end between them.
             (end (save-excursion
                    (goto-char (or last start))
                    (forward-line 1)
                    (line-end-position)))
             (phrase (diorisis--phrase hit start end)))
        (when (and phrase (memq diorisis-highlight '(both passage)))
          ;; WORD BY WORD, AND THE SPACES BETWEEN THEM ON A LINE.  One
          ;; overlay across the span would take in the citation column of
          ;; every line after the first, the span being contiguous and the
          ;; column sitting inside it.
          (dolist (word (diorisis--words-at (car phrase) (cdr phrase)))
            (let ((overlay (make-overlay (nth 0 word) (nth 1 word))))
              (overlay-put overlay 'face 'diorisis-passage-face)
              (overlay-put overlay 'evaporate t)
              (push overlay diorisis--overlays)))
          (save-excursion
            (goto-char (car phrase))
            (while (re-search-forward "[[:blank:]]+" (cdr phrase) t)
              (unless (get-text-property (match-beginning 0)
                                         'diogenes-citation)
                (let ((overlay (make-overlay (match-beginning 0)
                                             (match-end 0))))
                  (overlay-put overlay 'face 'diorisis-passage-face)
                  (overlay-put overlay 'evaporate t)
                  (push overlay diorisis--overlays))))))
        (when (memq diorisis-highlight '(both form))
          (let ((form (diorisis--bare
                       (diorisis--greek (plist-get hit :form)))))
            (unless (string-empty-p form)
              ;; INSIDE THE SENTENCE where the sentence was placed, and in the
              ;; range otherwise.  Every occurrence of it: a word can fall
              ;; twice in a sentence.  Compared bare, the form the corpus
              ;; records and the form the TLG prints differing in accent
              ;; oftener than one would think.
              (dolist (word (diorisis--words-at (or (car phrase) start)
                                                    (or (cdr phrase) end)))
                (when (equal (nth 2 word) form)
                  (let ((overlay (make-overlay (nth 0 word) (nth 1 word))))
                    (overlay-put overlay 'face 'diorisis-form-face)
                    ;; ABOVE THE SENTENCE'S OVERLAY.  Both cover this word,
                    ;; and the one made later does not win of itself: without
                    ;; a priority the green is lost under the sentence's face.
                    (overlay-put overlay 'priority 1)
                    (overlay-put overlay 'evaporate t)
                    (push overlay diorisis--overlays)))))))
        (when diorisis--overlays
          (diorisis-highlight-mode 1)
          (goto-char (or (car phrase) start))
          (pcase diorisis-highlight-lasts
            ('next-command
             (add-hook 'pre-command-hook #'diorisis-unhighlight nil t))
            ('escape
             (add-hook 'pre-command-hook #'diorisis--clear-on-escape
                       nil t))
            (_ nil)))
        t))))

(defun diorisis--mark-when-ready (buffer hit)
  "Mark HIT in BUFFER once the browser has put the passage there.

TRIED AGAIN RATHER THAN TIMED.  There is no hook to hang this on -- the text
arrives through a process filter -- and a fixed delay would be both too long
for a local database and too short for a cold one.  So the line is looked for,
and looked for again, until it is there or `diorisis-highlight-wait\=' is
spent."
  (when (and diorisis-highlight (buffer-live-p buffer))
    (let ((tries (max 1 (truncate (/ diorisis-highlight-wait 0.15)))))
      (with-current-buffer buffer
        (when (timerp diorisis--timer)
          (cancel-timer diorisis--timer))
        (setq diorisis--timer
              (run-with-timer
               0.15 0.15
               (lambda ()
                 (if (not (buffer-live-p buffer))
                     nil
                   (with-current-buffer buffer
                     (setq tries (1- tries))
                     (when (or (diorisis--mark hit) (<= tries 0))
                       (when (timerp diorisis--timer)
                         (cancel-timer diorisis--timer))
                       (setq diorisis--timer nil)))))))))))

(defvar-keymap diorisis-sentence-mode-map
  :doc "Keys in the buffer showing one sentence."
  "C-c C-c" #'diorisis-lookup-word
  "q"       #'quit-window)

(define-derived-mode diorisis-sentence-mode special-mode "Diorisis sentence"
  "One sentence of the Diorisis corpus, and what the tagger made of it.

ITS OWN MODE RATHER THAN `special-mode', for one key: this is the buffer with
the whole sentence in it, so it is where a reader will want to look a word up,
and `C-c C-c' means that everywhere else in this system."
  (setq-local truncate-lines nil)
  (visual-line-mode 1)
  (diorisis-install-mouse-keys)
  (diorisis--evil-keys diorisis-sentence-mode-map))

(defun diorisis-show-sentence (&optional hit)
  "Show HIT's whole sentence and what the tagger made of it.

FOCUSING WITHOUT LEAVING THE LIST.  A snippet is a window on a sentence and
the sentence is sometimes the answer -- one wants to see the whole of it, and
every analysis the form admits, before deciding whether the passage is worth
opening.  Opening it is `RET\\=' and is a different thing."
  (interactive)
  (let* ((hit (or hit (diorisis--hit-at)))
         (buffer (get-buffer-create "*Diorisis sentence*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "%s, %s %s\n"
                                    (or (plist-get hit :author) "?")
                                    (or (plist-get hit :work) "?")
                                    (diorisis--citation-string hit))
                            'face 'bold))
        (let ((aside (delq nil (list (plist-get hit :genre)
                                     (plist-get hit :subgenre)
                                     (diorisis--year
                                      (plist-get hit :date))))))
          (when aside
            (insert (propertize (concat (string-join aside ", ") "\n")
                                'face 'shadow))))
        (insert "\n")
        (let ((words (plist-get hit :words))
              (start (point)))
          (insert (if (and words (not (string-empty-p words)))
                      (diorisis--greek words)
                    "[the corpus keeps no sentence here]")
                  "\n")
          (let ((fill-column (min (or fill-column 80) 78)))
            (fill-region start (point))))
        (insert "\n")
        (insert (format "%-12s %s   (%s)\n" "form"
                        (diorisis--greek (plist-get hit :form))
                        (or (plist-get hit :form) "?")))
        (insert (format "%-12s %s   (%s)\n" "lemma"
                        (diorisis--greek (plist-get hit :lemma))
                        (or (plist-get hit :lemma) "?")))
        ;; EVERY ANALYSIS ON ITS OWN LINE.  They are stored joined by ` | '
        ;; because a form may admit several, and the several are the point:
        ;; a reader deciding whether this is the aorist participle they were
        ;; looking for needs to see that it might also be something else.
        (let ((morph (plist-get hit :morph)))
          (when morph
            (let ((analyses (split-string morph " *| *" t)))
              (insert (format "%-12s %s\n" "analysis" (car analyses)))
              (dolist (rest (cdr analyses))
                (insert (format "%-12s %s\n" "" rest))))))
        (insert (format "%-12s %s\n" "confidence"
                        (let ((confidence (plist-get hit :confidence)))
                          (cond ((null confidence)
                                 "the form admitted one lemma only")
                                (t (format "%.2f, the tagger's"
                                           confidence))))))
        ;; THE HIT ON THE WHOLE BUFFER, so that `C-c C-c' here can ask the
        ;; corpus what a word is: the lookup needs the author, the work and
        ;; the sentence, and this buffer is about exactly one of those.
        (put-text-property (point-min) (point-max) 'tei-diorisis-hit hit)
        (goto-char (point-min)))
      (diorisis-sentence-mode))
    (diorisis--display buffer t)))

(defun diorisis-lookup-lemma (&optional hit)
  "Look HIT's lemma up in the LSJ.

THE LEMMA GOES STRAIGHT IN.  Diorisis was lemmatised from Diogenes\\=' own word
list, so the string here is the string its parser returns and the dictionary
is reached without anything being translated.  A trailing digit distinguishing
homographs in the word list is dropped: the LSJ has one entry for both and
`mu/w1\\=' would find nothing."
  (interactive)
  (let* ((hit (or hit (diorisis--hit-at)))
         (lemma (diorisis--lemma-for-lookup (plist-get hit :lemma))))
    (when (string-empty-p lemma)
      (user-error "This hit has no lemma"))
    (unless (or (featurep 'diogenes)
                (and (locate-library "diogenes") (require 'diogenes nil t)))
      (user-error "Diogenes is not installed, so there is no LSJ to look %s up in"
                  (diorisis--greek lemma)))
    (classicist-lookup-greek lemma)))

(defun diorisis--token (hit word)
  "What the corpus records for WORD in HIT's sentence, or nil.

Returns (FORM LEMMA POS MORPH CONFIDENCE).

FOUND BY THE SENTENCE AND NOT BY THE WORD.  A form occurs all over the corpus
and the question is what THIS one is, so only the tokens of this sentence are
read -- a few dozen rows, by the key of the occurrences table.

Compared bare, as the marking is: the buffer's Greek and the corpus's
converted beta code differ in accent oftener than one would think, and a
lookup that failed over a grave would be worse than no lookup."
  (let ((author (plist-get hit :author-id))
        (work (plist-get hit :work-id))
        (sentence (plist-get hit :sentence))
        (bare (diorisis--bare word)))
    (when (and author work sentence (not (string-empty-p bare)))
      (seq-find
       (lambda (row)
         (equal (diorisis--bare (diorisis--greek (nth 0 row))) bare))
       (diorisis--select
        "SELECT form, lemma, pos, morph, confidence FROM occurrences\
 WHERE author_id = ? AND work_id = ? AND sentence = ?"
        (list author work sentence))))))

(defun diorisis--lemma-for-lookup (lemma)
  "LEMMA without the digit that distinguishes a homograph.
The LSJ has one entry for both, and `mu/w1' would find nothing."
  (replace-regexp-in-string "[0-9]+\\'" "" (or lemma "")))

(defun diorisis-lookup-word (&optional ask)
  "Parse the word at point and look it up, as `C-c C-c' does in the browser.

THE WORD AT POINT AND NOT THE LEMMA.  `l' looks up the hit's lemma, which is
the corpus's own answer and goes straight to the entry.  This is the other
question: what is THIS word, the one under point in the middle of a sentence,
and what does it come from.  Diogenes answers it: its
`diogenes-parse-and-lookup-greek' parses the form and then looks up what it
parsed to, and the snippets here are ordinary Greek text, so the same key can
do the same thing.

The word is taken as it is printed, letters only, and given as Greek:
Diogenes converts it.  With a prefix argument, or where point is on nothing,
the hit's own form is offered instead, a reader whose point is on a citation
having meant the hit."
  (interactive "P")
  (let* ((hit (ignore-errors (diorisis--hit-at)))
         (word (replace-regexp-in-string
                "[^[:alpha:]]" ""
                (or (thing-at-point 'word t)
                    (and hit (diorisis--greek (plist-get hit :form)))
                    "")))
         ;; The prefix argument takes the other route, whichever this is.
         (route (if ask
                    (if (eq diorisis-lookup-from 'lemma) 'form 'lemma)
                  diorisis-lookup-from))
         (token (and hit (eq route 'lemma) (diorisis--token hit word))))
    (when (string-empty-p word)
      (user-error "No word at point"))
    (unless (or (featurep 'diogenes)
                (and (locate-library "diogenes") (require 'diogenes nil t)))
      (user-error
       "Diogenes is not installed, so there is nothing to look %s up in"
       word))
    (cond
     (token
      ;; WHAT THE CORPUS SAYS, said out loud as well as looked up.  The
      ;; analysis and the confidence are the reason for preferring this route,
      ;; and a reader who sees `0.61' will want to check the entry against the
      ;; passage rather than take it.
      (message "%s: %s%s%s"
               (diorisis--greek (nth 0 token))
               (diorisis--greek (nth 1 token))
               (let ((morph (nth 3 token)))
                 (if morph (format ", %s" morph) ""))
               (let ((confidence (nth 4 token)))
                 (if confidence (format " (%.2f)" confidence)
                   " (one lemma only)")))
      (classicist-lookup-greek
       (diorisis--lemma-for-lookup (nth 1 token))))
     ;; NOTHING RECORDED FOR IT, so the parser after all: a word outside the
     ;; sentence -- the snippet's ellipsis, a neighbouring hit -- or one the
     ;; two conversions spell differently enough to miss.
     ((fboundp 'diogenes-parse-and-lookup-greek)
      (classicist-parse-and-lookup-greek word))
     (t (classicist-lookup-greek word)))))

(defun diorisis-next-hit (&optional n)
  "Move to the next hit, or the Nth after this one."
  (interactive "p")
  (dotimes (_ (max 1 (or n 1)))
    ;; NOT-CURRENT, the fourth argument.  The hit is a property over the whole
    ;; of its entry -- so that `RET' works from the middle of a snippet -- and
    ;; a plain forward search from inside one finds the one it is already in
    ;; and moves to its start, which looks like `n' going backwards.
    (let ((match (save-excursion
                   (text-property-search-forward
                    'tei-diorisis-hit nil nil t))))
      (if match
          (goto-char (prop-match-beginning match))
        (message "The last hit")))))

(defun diorisis-previous-hit (&optional n)
  "Move to the previous hit, or the Nth before this one."
  (interactive "p")
  (dotimes (_ (max 1 (or n 1)))
    (let ((match (save-excursion
                   (text-property-search-backward
                    'tei-diorisis-hit nil nil t))))
      (if match
          (goto-char (prop-match-beginning match))
        (message "The first hit")))))

(defun diorisis-widen-to-lemma ()
  ;; THE TREEBANK KEYS ARE NOT HERE.  Six of them belong to treebank.el and
  ;; are installed by treebank-install-results-keys, so that a reader who
  ;; has not asked for the treebank has no keys for it -- a defvar-keymap is
  ;; a literal and cannot be conditional.  This is the second of the five
  ;; seams: the treebank reaching into the corpus buffer.
  "Search again for the lemma alone, dropping the form and the morphology.

THE LEMMA IS WHAT THE CORPUS IS FOR.  A reader who came in by a form -- or who
narrowed to the aorist participle -- is one keystroke from every occurrence of
the word, which is the question Diogenes cannot answer at all and this can."
  (interactive)
  (unless diorisis--spec (user-error "No search to widen"))
  (let ((lemma (or (plist-get diorisis--spec :lemma)
                   (and (plist-get diorisis--spec :form)
                        (diorisis-lemma-of-form
                         (plist-get diorisis--spec :form)))
                   (let ((hit (ignore-errors (diorisis--hit-at))))
                     (and hit (plist-get hit :lemma))))))
    (unless lemma
      (user-error "Nothing here says which lemma to widen to"))
    (diorisis--show (list :lemma lemma))))

(defun diorisis-revert ()
  "Run this buffer's search again."
  (interactive)
  (unless diorisis--spec (user-error "No search to run again"))
  (diorisis--show diorisis--spec))

(defun diorisis-more ()
  "Fetch twice as many hits as this buffer is showing."
  (interactive)
  (unless diorisis--spec (user-error "No search to extend"))
  (let* ((spec (copy-sequence diorisis--spec))
         (limit (* 2 (or (plist-get spec :limit) diorisis-limit))))
    (if (and diorisis--total
             (>= (or (plist-get spec :limit) diorisis-limit)
                 diorisis--total))
        (message "All %d are already here" diorisis--total)
      (diorisis--show (plist-put spec :limit limit)))))

(defun diorisis-by-text (&optional spec)
  "Count SPEC's hits by text, commonest first, or this buffer's search.

SPEC as an argument as well as from the buffer, so that the transient can ask
for a distribution without first listing the hits: counting is the cheaper
question and is sometimes the whole of what one wants."
  (interactive)
  (let* ((spec (or spec diorisis--spec))
         (rows (progn (unless spec (user-error "No search to count"))
                      (diorisis-distribution spec)))
         (buffer (get-buffer-create "*Diorisis by text*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "%s\n" (diorisis--describe spec))
                            'face 'bold))
        (insert (propertize
                 "hits   per 10,000   text\n" 'face 'shadow))
        (dolist (row rows)
          (let* ((author (nth 0 row))
                 (work (nth 1 row))
                 (date (diorisis--year (nth 2 row)))
                 (hits (nth 3 row))
                 (words (nth 4 row)))
            (insert (format "%5d   %9s   %s, %s%s\n"
                            hits
                            ;; PER TEN THOUSAND WORDS, because raw counts say
                            ;; more about the length of a text than about the
                            ;; word: Galen is twenty times Aeschylus and will
                            ;; head every list otherwise.
                            (if (and words (> words 0))
                                (format "%.1f" (/ (* 10000.0 hits) words))
                              "?")
                            (or author "?") (or work "?")
                            (if date (format " (%s)" date) "")))))
        (goto-char (point-min)))
      (special-mode))
    (diorisis--display buffer t)))

(defvar-keymap diorisis-results-mode-map
  :doc "Keys in a buffer of Diorisis hits."
  "RET" #'diorisis-open-hit
  "o"   #'diorisis-open-hit
  ;; SPC IS LEFT TO `special-mode', which scrolls.  Two hundred hits is
  ;; several screens and paging through them is what the key is for; the
  ;; sentence is `v', beside the other one-letter commands.
  "v"   #'diorisis-show-sentence
  "l"   #'diorisis-lookup-lemma
  ;; `C-c C-c' IS WHAT IT IS EVERYWHERE ELSE in this system -- the browser
  ;; binds it to a lookup of the word at point, and so does a TEI text -- so
  ;; it is that here too, on the words of a snippet.
  "C-c C-c" #'diorisis-lookup-word
  "d"   #'diorisis-by-text
  "L"   #'diorisis-widen-to-lemma
  "S"   #'diorisis-save-search
  "O"   #'diorisis-open-search
  "w"   #'diorisis-open-work
  "n"   #'diorisis-next-hit
  "p"   #'diorisis-previous-hit
  "+"   #'diorisis-more
  "g"   #'diorisis-revert
  "s"   #'diorisis-search
  "q"   #'quit-window)

(defcustom diorisis-mouse-keys 'browser
  "Mouse gestures that look a word up in the hits, as (GESTURE . COMMAND).

`browser' FOLLOWS DIOGENES.  A reader who has set
`diorisisrowser-mouse-keys' has said that clicking a word looks it up, and
they meant that about reading Greek rather than about one buffer: the snippets
here are Greek, so the same gesture does the same thing.  Whatever command was
named is the one used, so a reader who bound a click to a lookup of their own
gets theirs.

An alist of its own overrides that, for gestures here and not in the browser.
Nil is none -- clicking a word and getting a dictionary entry is not what a
reader expects of an Emacs buffer, which is why Diogenes ships it off, and
following a setting is a different thing from making one.

Call `diorisis-install-mouse-keys' after changing this, or restart."
  :type '(choice (const :tag "Follow diorisisrowser-mouse-keys" browser)
                 (const :tag "None" nil)
                 (alist :key-type (string :tag "Gesture")
                        :value-type (function :tag "Command")))
  :group 'diorisis)

(defun diorisis--at-click (command)
  "COMMAND wrapped so that it acts on the word clicked.

POINT DOES NOT FOLLOW A CLICK OF ITS OWN ACCORD: `mouse-1' ordinarily runs
`mouse-drag-region', and that is what moves point -- so taking the gesture
takes that too, and the command would act where point already was.  One clicks
on a word and gets an entry for whatever one was reading before.

The same wrapper as `classicist-browser--at-click', and written out rather than
called: that one is private to its file, and a rename there should not break a
click here."
  (lambda (event)
    (interactive "e")
    (mouse-set-point event)
    (call-interactively command)))

(defun diorisis--mouse-keys ()
  "The gestures to bind, as (GESTURE . COMMAND)."
  (pcase diorisis-mouse-keys
    ('browser (and (boundp 'diorisisrowser-mouse-keys)
                   diorisisrowser-mouse-keys))
    ('nil nil)
    ((and (pred listp) keys) keys)))

(defun diorisis-install-mouse-keys ()
  "Bind the gestures `diorisis-mouse-keys' names, in the hits.

TRIED AGAIN AT EVERY MODE START, and once more when `classicist-browser' loads.
The option this follows is defined by that file, and a reader who searches
before ever opening a browser has not loaded it -- so the first attempt found
the variable unbound and the gestures were simply absent, with nothing to say
why.  The same fault `tei--lend-browser-keys' was written for."
  (interactive)
  (dolist (map (list diorisis-results-mode-map
                     diorisis-sentence-mode-map))
    (dolist (cell (diorisis--mouse-keys))
      (when (and (car cell) (cdr cell))
        (ignore-errors
          (keymap-set map (car cell)
                      (diorisis--at-click (cdr cell))))))))

(define-derived-mode diorisis-results-mode special-mode "Diorisis"
  "A list of occurrences in the Diorisis corpus.

NOT CLAIMED AS A DIOGENES BROWSER, unlike `tei-mode\\='.  That mode shows a text
and lends the browser's commands, which read the citation off the buffer and
work unchanged.  This buffer is a list of hits in twenty different works, and
`classicist-browser-reference\\=' asked here would answer with whichever citation
happened to be nearest point -- a note stored against the wrong passage, which
is worse than no note at all.  `RET\\=' opens the passage in a real browser and
everything of Diogenes' works there.

\\{diorisis-results-mode-map}"
  (setq-local truncate-lines nil)
  (visual-line-mode 1)
  (diorisis-install-mouse-keys)
  (diorisis--evil-keys diorisis-results-mode-map))

(defun diorisis--cit-levels (location)
  "LOCATION as the levels Diogenes puts on a line: `153c' as (153 c).

WHAT THE `cit' PROPERTY HOLDS.  Diogenes writes a list of numbers and symbols,
and `classicist-browser-citation-at' hands it on to everything that asks where a
line is; a string would not do, the callers comparing level by level.  The
same conversion as `tei--citation-levels', and here for the same reason."
  (let ((out nil))
    (dolist (part (diorisis--levels location))
      (if (string-match "\\`\\([0-9]+\\)\\([a-z]\\)\\'" part)
          (setq out (append out (list (string-to-number (match-string 1 part))
                                      (intern (match-string 2 part)))))
        (setq out (append out
                          (list (if (string-match-p "\\`[0-9]+\\'" part)
                                    (string-to-number part)
                                  (intern part)))))))
    out))

(defface diorisis-citation-face
  '((t :inherit font-lock-comment-face))
  "Face for the citation beside a passage in a Diorisis text.

`font-lock-comment-face', which is what Diogenes' own browser marks its
citation column with -- `classicist--browser-format-citation' -- so a Diorisis
text and a TLG text look alike down the left-hand side.  It began as `shadow',
which several themes render as grey text on grey and which is also the face
used for asides in the hit list: two different things in one appearance."
  :group 'diorisis)

(defcustom diorisis-citation-style 'column
  "How a passage's citation is set off from the text.

`column' keeps it in a column down the left, the text indented past it -- the
browser's arrangement, and the one to scan for a number in.

`line' puts it on a line of its own above the passage, in bold, with the text
at the margin.  Right for verse, where the text is short and a ten-character
indent wastes half the line, and for anyone who finds a column of numbers hard
to tell from the words beside it."
  :type '(choice (const :tag "In a column at the left" column)
                 (const :tag "On a line of its own" line))
  :group 'diorisis)

(defcustom diorisis-citation-width 12
  "How wide the citation column is, in characters.

Twelve, because `1.11.12.1' is nine and Kuehn's pages are longer still; a
citation that overran its column pushed the text of that one passage out of
line with every other, which is exactly the confusion the column exists to
prevent."
  :type 'integer
  :group 'diorisis)

(defvar-local diorisis--text nil
  "What this buffer is showing, as (AUTHOR-ID WORK-ID AUTHOR WORK).")

(defvar-local diorisis--places nil
  "An alist of (CITATION . POSITION), where each passage begins.")

(defvar-local diorisis--sentence-places nil
  "An alist of (SENTENCE . POSITION), for arriving from a hit.")

(defun diorisis--render-text (rows)
  "Print ROWS -- each (SENTENCE LOCATION WORDS) -- as a readable text."
  (let ((inhibit-read-only t)
        (places nil)
        (sentences nil)
        (last nil))
    (erase-buffer)
    (dolist (row rows)
      (let* ((sentence (nth 0 row))
             (location (nth 1 row))
             (citation (let ((levels (diorisis--levels location)))
                         (and levels (mapconcat #'identity levels "."))))
             (levels (diorisis--cit-levels location))
             (start (point)))
        (push (cons sentence start) sentences)
        ;; THE CITATION ONLY WHERE IT CHANGES.  Several sentences share a
        ;; Stephanus page or a line, and printing it against each would say
        ;; the same thing five times over.
        ;;
        ;; MARKED AS A CITATION AND NOT AS TEXT, in three ways at once,
        ;; because one was not enough: its own face, a column the text never
        ;; enters -- or a line of its own, where that is the style -- and the
        ;; `diogenes-citation' property, which is what the marking and the
        ;; word-at-point read to know that this is not a word of the text.
        (let ((new (and citation (not (equal citation last)))))
          (pcase diorisis-citation-style
            ('line
             (when new
               (push (cons citation start) places)
               (insert (propertize (format "%s\n" citation)
                                   'face 'diorisis-citation-face
                                   'font-lock-face
                                   'diorisis-citation-face
                                   'diogenes-citation t
                                   'cit levels))))
            (_
             (if new
                 (progn
                   (push (cons citation start) places)
                   (insert (propertize
                            ;; PADDED BY HAND.  Elisp's `format' has no `*'
                            ;; width -- that is C's -- so `%-*s' is not a
                            ;; narrower column but a bad format string, and
                            ;; the reader would have signalled on its first
                            ;; line.  Byte-compilation said so; the paren
                            ;; checkers could not.
                            (let ((pad (- diorisis-citation-width
                                          (length citation))))
                              (concat citation
                                      (make-string (max 1 pad) ?\s)))
                            'face 'diorisis-citation-face
                            'font-lock-face 'diorisis-citation-face
                            'diogenes-citation t
                            'cit levels)))
               ;; THE COLUMN KEPT EMPTY rather than closed up, so that the
               ;; text of every passage begins at the same place: a page whose
               ;; sentences started in two different columns was the other
               ;; half of what made the markers hard to tell from the words.
               (insert (propertize
                        (make-string diorisis-citation-width ?\s)
                        'cit levels))))))
        (setq last citation)
        ;; THE CITATION ON EVERY CHARACTER of the sentence and not only on
        ;; its marker: a note stored from the middle of a long sentence should
        ;; say which sentence rather than hunt backwards for one.
        ;;
        ;; AND `wrap-prefix' RATHER THAN A FILL.  The passage is inserted as
        ;; one long line and wrapped by the display, with the indent carried
        ;; on to each wrapped line by the property -- not by hard newlines put
        ;; in at some width of our choosing.
        ;;
        ;; Which matters for more than tidiness: a reader with olivetti-mode,
        ;; or any of the other ways of narrowing a body of text, sets the
        ;; width they want, and text already broken at 88 columns would be
        ;; broken again at theirs -- two wraps to a line, ragged, and immune
        ;; to their setting.  Soft-wrapped text reflows when the window or the
        ;; margin changes, which is what such a mode is for.
        (insert (propertize (diorisis--greek (nth 2 row))
                            'cit levels
                            'wrap-prefix
                            (if (eq diorisis-citation-style 'line) ""
                              (make-string diorisis-citation-width ?\s)))
                "\n")))
    (setq diorisis--places (nreverse places))
    (setq diorisis--sentence-places (nreverse sentences))
    (goto-char (point-min))
    (set-buffer-modified-p nil)))

(defun diorisis--text-locals (author work)
  "Tell Diogenes' own commands what this buffer is showing.

`classicist-browser-reference' reads these, and everything that asks where a
reader is asks IT -- so setting them is what makes a lookup, an org link and a
printed edition work here.  WORK is the number the TLG uses, not ours, because
a reference made here must answer for the same passage in the browser."
  (dolist (pair (list (cons 'classicist--browser-corpus diorisis-corpus)
                      (cons 'classicist--browser-author author)
                      (cons 'classicist--browser-work work)
                      (cons 'classicist--browser-language "greek")
                      (cons 'classicist--browser-labels nil)))
    ;; SET WHETHER OR NOT DIOGENES HAS DECLARED IT: a buffer-local binding for
    ;; a symbol nobody else uses costs nothing, and where Diogenes is loaded
    ;; it is the same symbol its own commands read.
    (set (make-local-variable (car pair)) (cdr pair))))

(defun diorisis-text-next (&optional n)
  "Move to the next passage, or the Nth after this one."
  (interactive "p")
  (dotimes (_ (max 1 (or n 1)))
    (let ((next (seq-find (lambda (place) (> (cdr place) (point)))
                          diorisis--places)))
      (if next (progn (goto-char (cdr next)) (recenter 0))
        (message "The last passage")))))

(defun diorisis-text-previous (&optional n)
  "Move to the previous passage, or the Nth before this one."
  (interactive "p")
  (dotimes (_ (max 1 (or n 1)))
    (let ((before (seq-filter (lambda (place) (< (cdr place) (point)))
                              diorisis--places)))
      (if before
          (progn (goto-char (cdr (car (last before)))) (recenter 0))
        (message "The first passage")))))

(defun diorisis-text-goto (citation)
  "Move to CITATION in this text."
  (interactive
   (list (completing-read "Citation: "
                          (mapcar #'car diorisis--places) nil t)))
  (let ((where (cdr (assoc citation diorisis--places))))
    (unless where (user-error "No %s in this text" citation))
    (goto-char where)
    (recenter 0)))

(defvar-keymap diorisis-text-mode-map
  :doc "Keys in a Diorisis text."
  "n" #'diorisis-text-next
  "p" #'diorisis-text-previous
  "g" #'diorisis-text-goto
  "w" #'diorisis-open-work
  "s" #'diorisis-search
  ;; PAGING TAKEN OVER, not let through.  This buffer claims to be a Diogenes
  ;; browser -- which is what makes the lookups and the links work -- so
  ;; `C-c C-n' would otherwise reach `classicist-browser-forward' and talk to a
  ;; Perl process that is not reading this text.  The whole work is here, so
  ;; what those keys mean is moving about it.
  "C-c C-n" #'diorisis-text-next
  "C-c C-p" #'diorisis-text-previous
  "C-c C-q" #'quit-window
  "q" #'quit-window)

(defun diorisis--lend-browser-keys ()
  "Make Diogenes' browser map the parent of ours, and count as a browser.

TRIED AGAIN AT EVERY MODE START.  A reader who opens a Diorisis text before
ever opening a browser has not loaded the file that defines the map, so a
single attempt at load would bind nothing and say nothing about why.  The
kinship is claimed with `derived-mode-add-parents' rather than by deriving,
the parent of a `define-derived-mode' being fixed when the form is compiled
and Diogenes not known to be installed until it is loaded."
  (when (or (featurep 'classicist-browser)
            (and (locate-library "classicist-browser")
                 (require 'classicist-browser nil t)))
    (when (and (boundp 'classicist-browser-mode-map)
               (keymapp classicist-browser-mode-map)
               (not (eq (keymap-parent diorisis-text-mode-map)
                        classicist-browser-mode-map)))
      (set-keymap-parent diorisis-text-mode-map
                         classicist-browser-mode-map))
    (cond
     ((fboundp 'derived-mode-add-parents)
      (derived-mode-add-parents 'diorisis-text-mode
                                '(classicist-browser-mode)))
     (t (put 'diorisis-text-mode 'derived-mode-extra-parents
             '(classicist-browser-mode))))))

(define-derived-mode diorisis-text-mode special-mode "Diorisis text"
  "A text of the Diorisis corpus, read out of the index.

The tokens joined again rather than an edition -- no line breaks, no
apparatus, no verse layout -- and counted as a Diogenes browser all the same,
so that `C-c C-c' looks a word up, `C-c l' stores an org link and `C-c C-r'
finds the printed page.  None of the three knows where the text came from.

\\{diorisis-text-mode-map}"
  (setq-local truncate-lines nil)
  ;; WRAPPED AT A WORD and not in the middle of one, the buffer being text to
  ;; read.  `visual-line-mode' sets this; said here too because a reader may
  ;; turn that off in favour of their own arrangement and should not thereby
  ;; get Greek broken mid-word.
  (setq-local word-wrap t)
  (visual-line-mode 1)
  (diorisis--lend-browser-keys)
  (diorisis-install-mouse-keys))

(defun diorisis-open-work (&optional author work sentence)
  "Read a text of the Diorisis corpus.

AUTHOR and WORK are the numbers as this index holds them, and are asked for
interactively.  SENTENCE, where given, is where to arrive -- which is how a
hit opens its own passage when there is no Diogenes to open it in."
  (interactive)
  (let* ((chosen (unless (and author work) (diorisis-read-text)))
         (author (or author (car chosen)))
         (work (or work (cdr chosen))))
    (unless (and author work)
      (user-error "A work is wanted here, not a whole author"))
    (let* ((named (car (diorisis--select
                        "SELECT author, work, tlg_work_id FROM texts\
 WHERE author_id = ? AND work_id = ?"
                        (list author work))))
           (rows (diorisis--select
                  "SELECT sentence, location, words FROM sentences\
 WHERE author_id = ? AND work_id = ? ORDER BY sentence"
                  (list author work)))
           (buffer (get-buffer-create
                    (format "*Diorisis: %s, %s*"
                            (or (nth 0 named) author)
                            (or (nth 1 named) work)))))
      ;; THE OLDER RELEASE STORED NO SENTENCES.  `diorisis-index.py' fills
      ;; that table only from the JSON release, the XML one keeping no running
      ;; text to put back together -- so a reader with the 2018 corpus can
      ;; search and cannot read, and is told which it is.
      (unless rows
        (user-error
         "The index keeps no sentences for %s %s (the XML release stores none)"
         author work))
      (with-current-buffer buffer
        (diorisis-text-mode)
        (setq diorisis--text (list author work (nth 0 named)
                                      (nth 1 named)))
        (diorisis--text-locals author (or (nth 2 named) work))
        (diorisis--render-text rows))
      (diorisis--display buffer)
      (when sentence
        (with-current-buffer buffer
          (let ((where (cdr (assq sentence diorisis--sentence-places))))
            (when where (goto-char where) (recenter 0)))))
      buffer)))

(defun diorisis-search-lemma (lemma)
  "Find every occurrence of LEMMA in the Diorisis corpus.

The plain way in, and the one worth binding: a lemma, completed from the
corpus's own 63,718, and every occurrence of it whatever form it takes.
`diorisis-search\\=' is the same search with the narrowings."
  (interactive (list (diorisis-read-lemma "Lemma: ")))
  (diorisis--show (list :lemma lemma)))

(defun diorisis-search-form (form)
  "Find every occurrence of FORM, as printed, in the Diorisis corpus.

A FORM AND NOT A LEMMA, for the question `where does this exact word occur'.
Slower than a lemma search and it cannot be helped: the index is on the lemma,
which is what this corpus is for, so a form is found by reading the column.
`diorisis-index-forms\\=' makes an index for it where that matters."
  (interactive (list (read-string "Form (beta code or Greek): ")))
  ;; THE LEMMA ANSWERS IT, where the corpus knows one.  The hits are the same
  ;; -- the form clause still stands -- but they come off the lemma index
  ;; rather than out of a read of ten million rows, and the reader is told
  ;; which lemma it was, `L' in the results widening to it.
  (let ((lemma (ignore-errors (diorisis-lemma-of-form form))))
    (diorisis--show (if lemma
                            (list :lemma lemma :form form)
                          (list :form form)))))

(defun diorisis-index-forms ()
  "Index the corpus by form, for searching by form.

WHY THIS IS NOT DONE BY THE INDEXER.  `diorisis-index.py\\=' indexes the lemma,
because a lemma is what the corpus is for; a form search reads ten million
rows and takes a few seconds.  A reader who searches by form often can pay
once for an index instead -- some minutes, and a few tens of megabytes on the
database -- and this is that.  It is not undone: drop the index in sqlite3 if
the space is wanted back."
  (interactive)
  (when (y-or-n-p "Index the Diorisis corpus by form?  Some minutes: ")
    (message "Indexing by form ...")
    (sqlite-execute
     (diorisis--db)
     "CREATE INDEX IF NOT EXISTS occurrences_form ON occurrences (form)")
    (message "Indexed by form")))

(defun diorisis--args-spec (args)
  "The transient's ARGS as a search.

A number where a number is meant: the transient hands everything back as a
string, and `:from\\=' compared as a string would put the fourth century B.C.
after the second A.D."
  (let ((text (transient-arg-value "--text=" args))
        (from (transient-arg-value "--from=" args))
        (to (transient-arg-value "--to=" args))
        (confidence (transient-arg-value "--confidence=" args))
        (limit (transient-arg-value "--limit=" args)))
    (list :lemma (transient-arg-value "--lemma=" args)
          :form (transient-arg-value "--form=" args)
          :pos (transient-arg-value "--pos=" args)
          :morph (transient-arg-value "--morph=" args)
          ;; `0059.018' -- the author and the work as one, because the work
          ;; number means nothing without the author.  See
          ;; `diorisis-read-text'.
          :author (and text (car (split-string text "[.]" t)))
          :work (and text (cadr (split-string text "[.]" t)))
          :genre (transient-arg-value "--genre=" args)
          :subgenre (transient-arg-value "--subgenre=" args)
          :from (and from (string-to-number from))
          :to (and to (string-to-number to))
          :confidence (and confidence (string-to-number confidence))
          :unambiguous (and (member "--unambiguous" args) t)
          :by-date (and (member "--by-date" args) t)
          :limit (and limit (string-to-number limit)))))

(defun diorisis--narrow-p (spec)
  "Whether SPEC asks for anything an index can answer.

TEN MILLION ROWS, AND TWO INDEXES.  `diorisis-index.py\=' indexes the lemma and
the (author, work) pair, those being the questions the corpus is for; so a
search by either is a lookup.  A search by morphology, or by genre, or by
century alone is a scan of the whole table -- which is a real answer to a real
question, every aorist participle in tragedy, and takes its time.  The reader
is asked rather than either refused or left wondering what became of Emacs.

A form is counted as narrow.  It is not indexed unless
`diorisis-index-forms\=' has been run, but a single column read with a
string to compare is seconds rather than the minute a joined scan takes, and
`where does this exact word occur\=' is too ordinary a question to put behind a
prompt."
  (let ((lemma (plist-get spec :lemma))
        (form (plist-get spec :form))
        (author (plist-get spec :author)))
    (or (and lemma (not (string-empty-p lemma)))
        (and form (not (string-empty-p form)))
        (and author (not (string-empty-p author))))))

(defun diorisis--run (spec)
  "Search for SPEC, asking first where it means reading the whole corpus.

A FORM WITHOUT A LEMMA IS SETTLED FIRST.  The corpus is lemmatised, so a form
has a lemma recorded against it, and adding that to the search changes nothing
about the answer and everything about how it is reached: the lemma is indexed
and the form is not."
  (when (and (plist-get spec :form)
             (not (string-empty-p (plist-get spec :form)))
             (not (plist-get spec :lemma)))
    (let ((lemma (ignore-errors
                   (diorisis-lemma-of-form (plist-get spec :form)))))
      (when lemma
        (setq spec (plist-put (copy-sequence spec) :lemma lemma)))))
  (let ((asked (diorisis--describe spec)))
    (when (string-empty-p asked)
      (user-error "Nothing to search for"))
    (when (or (diorisis--narrow-p spec)
              (y-or-n-p
               (format "%s is not indexed and means reading ten million \
rows.  Go on? " asked)))
      (diorisis--show spec))))

(transient-define-argument diorisis--arg-lemma ()
  :description "Lemma"
  :class 'transient-option
  :key "-l"
  :argument "--lemma="
  :prompt "Lemma (completing on the corpus): "
  :reader (lambda (prompt _initial _history)
            (diorisis-read-lemma prompt)))

(transient-define-argument diorisis--arg-form ()
  :description "Form, as printed"
  :class 'transient-option
  :key "-f"
  :argument "--form="
  :prompt "Form (beta code or Greek, % as wildcard): ")

(transient-define-argument diorisis--arg-pos ()
  :description "Part of speech"
  :class 'transient-option
  :key "-p"
  :argument "--pos="
  :prompt "Part of speech: "
  :reader (lambda (prompt _initial _history)
            (completing-read prompt (diorisis-parts-of-speech)
                             nil t)))

(transient-define-argument diorisis--arg-morph ()
  :description "Morphology"
  :class 'transient-option
  :key "-m"
  :argument "--morph="
  ;; FEATURES, IN ANY ORDER.  Each is asked for separately -- see
  ;; `diorisis--morph-clauses' -- so `part,gen' and `gen,part' are one
  ;; question, and neither depends on the order the corpus writes its
  ;; analyses in.  That order mattered once, and silently.
  :prompt "Features (comma-separated, any order, e.g. part,gen): "
  :reader (lambda (prompt _initial _history)
            (diorisis-read-morphology prompt)))

(transient-define-argument diorisis--arg-text ()
  :description "Author, or one work"
  :class 'transient-option
  :key "-t"
  :argument "--text="
  :prompt "Author: "
  :reader (lambda (_prompt _initial _history)
            (let ((chosen (diorisis-read-text)))
              (if (cdr chosen)
                  (format "%s.%s" (car chosen) (cdr chosen))
                (car chosen)))))

(transient-define-argument diorisis--arg-genre ()
  :description "Genre"
  :class 'transient-option
  :key "-g"
  :argument "--genre="
  :prompt "Genre: "
  :reader (lambda (prompt _initial _history)
            (completing-read prompt (diorisis--column "genre") nil t)))

(transient-define-argument diorisis--arg-subgenre ()
  :description "Subgenre"
  :class 'transient-option
  :key "-G"
  :argument "--subgenre="
  :prompt "Subgenre: "
  :reader (lambda (prompt _initial _history)
            (completing-read prompt (diorisis--column "subgenre")
                             nil t)))

(transient-define-argument diorisis--arg-from ()
  :description "Not before (year, negative for B.C.)"
  :class 'transient-option
  :key "-a"
  :argument "--from="
  :prompt "Not before the year (negative for B.C.): "
  :reader (lambda (prompt _initial _history)
            (number-to-string (read-number prompt))))

(transient-define-argument diorisis--arg-to ()
  :description "Not after (year, negative for B.C.)"
  :class 'transient-option
  :key "-b"
  :argument "--to="
  :prompt "Not after the year (negative for B.C.): "
  :reader (lambda (prompt _initial _history)
            (number-to-string (read-number prompt))))

(transient-define-argument diorisis--arg-confidence ()
  :description "Confidence at least"
  :class 'transient-option
  :key "-c"
  :argument "--confidence="
  :prompt "Confidence at least: "
  :reader (lambda (prompt _initial _history)
            (number-to-string (read-number prompt 0.9))))

(transient-define-argument diorisis--arg-limit ()
  :description "At most this many hits"
  :class 'transient-option
  :key "-n"
  :argument "--limit="
  :prompt "At most how many hits: "
  :reader (lambda (prompt _initial _history)
            (number-to-string (read-number prompt diorisis-limit))))

(defun diorisis-run-search (&optional args)
  "Search the Diorisis corpus as ARGS narrow it."
  (interactive (list (transient-args 'diorisis-search)))
  (diorisis--run (diorisis--args-spec args)))

(defun diorisis-run-count (&optional args)
  "Say how many occurrences ARGS has, without listing them."
  (interactive (list (transient-args 'diorisis-search)))
  (let ((spec (diorisis--args-spec args)))
    (message "%d occurrences: %s"
             (diorisis-count spec)
             (diorisis--describe spec))))

(defun diorisis-run-by-text (&optional args)
  "Count ARGS' occurrences by text, commonest first."
  (interactive (list (transient-args 'diorisis-search)))
  (diorisis-by-text (diorisis--args-spec args)))

(transient-define-prefix diorisis-search ()
  "Search the Diorisis corpus of lemmatised Greek.

EVERY DIMENSION THE DATA HOLDS, which is the answer to `search in all the ways
the app allows': Diorisis' own app bundles a lemma list and filters it in
JavaScript, so there are no queries to copy and nothing to match mode for
mode.  What there is instead is the schema -- lemma, form, part of speech,
morphology, author, work, genre, subgenre, date, confidence -- and each of
those is here.

A search by lemma or by form is answered by an index.  One by morphology or
genre alone reads the whole corpus and says so before doing it."
  ["Narrow by the word"
   (diorisis--arg-lemma)
   (diorisis--arg-form)
   (diorisis--arg-pos)
   (diorisis--arg-morph)
   ("-u" "Unambiguous forms only" "--unambiguous")
   (diorisis--arg-confidence)]
  ["Narrow by the text"
   (diorisis--arg-text)
   (diorisis--arg-genre)
   (diorisis--arg-subgenre)
   (diorisis--arg-from)
   (diorisis--arg-to)]
  ["And then"
   (diorisis--arg-limit)
   ("-D" "Oldest first" "--by-date")
   ("s" "Search" diorisis-run-search)
   ("q" "Build a query of several elements" diorisis-query)
   ("o" "Open a search saved before" diorisis-open-search)
   ("D" "Switch between the plain and merged databases"
    diorisis-switch-database)
   ("L" "Annotated trees" treebank-annotations-menu :if (lambda () (or (not (fboundp 'classicist-feature-p))
                                 (classicist-feature-p 'treebank))))
   ("b" "The workbook of collected sentences" treebank-workbook :if (lambda () (or (not (fboundp 'classicist-feature-p))
                                 (classicist-feature-p 'treebank))))
   ("c" "Count only" diorisis-run-count)
   ("d" "Count by author and work" diorisis-run-by-text)])

(defcustom diorisis-query-file nil
  "Obsolete: queries are kept in `diorisis-saved-directory\=' now.

ONE PLACE FOR BOTH.  A query of elements and a plain search are both searches
and were kept apart for no better reason than that they were written at
different times; a reader who saved one and looked for it among the other was
right to be annoyed.  Set this to a file and the old file is still read, so
nothing saved is lost."
  :type '(choice (const :tag "Use the directory" nil) file)
  :group 'diorisis)

(defvar-local diorisis--query nil
  "The elements this buffer is composing.")

(defvar-local diorisis--query-spec nil
  "The narrowings the query will be run with.")

(defun diorisis--describe-element (element first)
  "ELEMENT as a line of English.  FIRST says it opens the query."
  (let* ((kind (plist-get element :kind))
         (value (or (plist-get element :value) ""))
         (shown (if (memq kind '(form lemma))
                    (diorisis--greek (diorisis--beta value))
                  value))
         (what (pcase kind
                 ('form (if (eq (plist-get element :match) 'contains)
                            (format "a form containing %s" shown)
                          (format "the form %s" shown)))
                 ('lemma (if (eq (plist-get element :match) 'contains)
                             (format "a form of a lemma containing %s" shown)
                           (format "a form of %s" shown)))
                 ('morph (format "a word analysed %s" shown))
                 ('punct (format "the punctuation mark %s" shown))
                 (_ "anything")))
         (morph (plist-get element :morph))
         (scope (or (plist-get element :scope) '(sentence)))
         (relation (if (eq (plist-get element :relation) 'either)
                       "followed or preceded by" "followed by"))
         (counting (if (eq (plist-get element :count) 'nodes)
                       "" " (ignore punctuation)"))
         (how (pcase (car scope)
                ('within (format "within %d" (nth 1 scope)))
                ('between (format "between %d and %d"
                                  (nth 1 scope) (nth 2 scope)))
                ('exactly (format "exactly %d" (nth 1 scope)))
                (_ "anywhere in the same sentence"))))
    (concat (if first "" (format "%s%s, %s, " relation counting how))
            (if (plist-get element :negate) "anything but " "")
            what
            (if (and morph (not (string-empty-p morph)))
                (format ", analysed %s" morph) "")
            (if (plist-get element :bare) " (ignoring diacritics)" ""))))

(defun diorisis--render-query ()
  "Print the query this buffer is composing."
  (let ((inhibit-read-only t)
        (query diorisis--query)
        (spec diorisis--query-spec))
    (erase-buffer)
    (insert (propertize "A Diorisis query\n\n" 'face 'bold))
    (if (null query)
        (insert "  (nothing yet)\n")
      (let ((index 0))
        (dolist (element query)
          (setq index (1+ index))
          (let ((start (point)))
            (insert (format "  %d. %s\n" index
                            (diorisis--describe-element
                             element (= index 1))))
            (put-text-property start (point) 'tei-diorisis-element index)))))
    (insert "\n")
    (let ((said (and spec (diorisis--describe spec))))
      (when (and said (not (string-empty-p said)))
        (insert (propertize (format "  narrowed to %s\n\n" said)
                            'face 'font-lock-comment-face))))
    (insert (propertize
             (concat "a adds an element \u00b7 d deletes the one at point \u00b7 "
                     "n narrows\n"
                     "RET searches \u00b7 c counts \u00b7 x explains \u00b7 "
                     "S saves \u00b7 l loads \u00b7 k clears \u00b7 q quits\n"
                     "each is also under C-c: C-c a, C-c C-d, C-c RET ...\n")
             'face 'shadow))
    (goto-char (point-min))
    (diorisis--evil-enter-state)))

(defun diorisis--read-element (first)
  "Ask for an element.  FIRST says it opens the query, and so has no relation."
  (let* ((kinds '(("the exact form" . form)
                  ("a form containing the sequence" . form-contains)
                  ("a form of the lemma" . lemma)
                  ("a form of a lemma containing the sequence"
                   . lemma-contains)
                  ("a word with the following morphological features"
                   . morph)
                  ("the punctuation mark" . punct)))
         (chosen (cdr (assoc (completing-read "Element: " kinds nil t)
                             kinds)))
         (kind (pcase chosen
                 ((or 'form 'form-contains) 'form)
                 ((or 'lemma 'lemma-contains) 'lemma)
                 (other other)))
         (match (if (memq chosen '(form-contains lemma-contains))
                    'contains 'exact))
         (value (pcase kind
                  ('lemma (if (eq match 'contains)
                              (read-string "Lemma contains: ")
                            ;; THE LEMMA PROMPT, which completes on the
                            ;; corpus's own and settles a form into its lemma.
                            (diorisis-read-lemma "A form of: ")))
                  ('form (read-string (if (eq match 'contains)
                                          "Form contains: "
                                        "The form: ")))
                  ;; THE MORPHOLOGY PROMPT AND NOT `read-string\='.  A plain
                  ;; string prompt here is what made the whole tagset
                  ;; invisible: `diorisis-read-morphology\=' completes on
                  ;; the corpus\=' own values and says which category each
                  ;; belongs to, and this asked the reader to type from
                  ;; memory instead.
                  ('morph (diorisis-read-morphology "Analysed: "))
                  ('punct (read-string "The mark: " "."))))
         (morph (and (memq kind '(form lemma))
                     (let ((said (diorisis-read-morphology
                                  "And analysed (empty for any): ")))
                       (and (not (string-empty-p said)) said))))
         (negate (y-or-n-p "Anything BUT this? "))
         (bare (and (memq kind '(form lemma))
                    (y-or-n-p "Ignore diacritics? ")))
         (element (list :kind kind :value value :match match
                        :morph morph :negate negate :bare bare)))
    (if first
        element
      (let* ((relations '(("followed by" . (follows . nodes))
                          ("followed or preceded by" . (either . nodes))
                          ("followed by (ignore punctuation)"
                           . (follows . words))
                          ("followed or preceded by (ignore punctuation)"
                           . (either . words))))
             (relation (cdr (assoc (completing-read "Relation: "
                                                    relations nil t)
                                   relations)))
             (scopes '(("within" . within) ("between" . between)
                       ("exactly" . exactly)
                       ("in the same sentence" . sentence)))
             (scope (cdr (assoc (completing-read "Scope: " scopes nil t)
                                scopes)))
             (scope (pcase scope
                      ('within (list 'within (read-number "Within: " 3)))
                      ('between (list 'between
                                      (read-number "From: " 2)
                                      (read-number "To: " 3)))
                      ('exactly (list 'exactly (read-number "Exactly: " 2)))
                      (_ (list 'sentence)))))
        (append element (list :relation (car relation)
                              :count (cdr relation)
                              :scope scope))))))

(defun diorisis-query-add ()
  "Add an element to the query."
  (interactive)
  (setq diorisis--query
        (append diorisis--query
                (list (diorisis--read-element
                       (null diorisis--query)))))
  (diorisis--render-query))

(defun diorisis-query-delete ()
  "Delete the element at point."
  (interactive)
  (let ((index (get-text-property (point) 'tei-diorisis-element)))
    (unless index (user-error "No element here"))
    (setq diorisis--query
          (append (seq-take diorisis--query (1- index))
                  (seq-drop diorisis--query index)))
    ;; THE FIRST ELEMENT CARRIES NO RELATION, so one promoted into that place
    ;; must lose the one it had -- a query beginning `followed by' says
    ;; nothing, and the join it would build has nothing to join to.
    (when diorisis--query
      (setcar diorisis--query
              (let ((first (copy-sequence (car diorisis--query))))
                (dolist (key '(:relation :count :scope))
                  (setq first (plist-put first key nil)))
                first)))
    (diorisis--render-query)))

(defun diorisis-query-clear ()
  "Take every element off the query."
  (interactive)
  (setq diorisis--query nil)
  (diorisis--render-query))

(defun diorisis-query-narrow ()
  "Set the narrowings the query will be run with."
  (interactive)
  (setq diorisis--query-spec
        (diorisis--args-spec (transient-args 'diorisis-search)))
  (diorisis--render-query)
  (message "Narrowed.  Set these in the search menu, then narrow again"))

(defun diorisis--query-as-spec ()
  "The query as a search."
  (unless diorisis--query (user-error "The query is empty"))
  (append (list :elements diorisis--query)
          (copy-sequence (or diorisis--query-spec nil))))

(defun diorisis-query-run ()
  "Search for the query."
  (interactive)
  (diorisis--show (diorisis--query-as-spec)))

(defun diorisis-query-count ()
  "Say how many the query finds, without listing them."
  (interactive)
  (let ((spec (diorisis--query-as-spec)))
    (message "%d occurrences" (diorisis-count spec))))

(defun diorisis-what-is-there (like)
  "Show what the corpus actually holds for lemmata matching LIKE.

FOR THE OTHER HALF OF A QUERY THAT FINDS NOTHING.  An element asking for the
lemma `le/gw\=' finds nothing where the corpus spells it `le/gw1\=' -- Diorisis
keeps the homograph digit on some lemmata and not others -- and no amount of
reading the SQL will show that, the SQL being right about a lemma nobody has.

    M-x diorisis-what-is-there RET le/gw RET

says which spellings are there and how many times each occurs.  Beta code or
Greek; `%\=' is a wildcard and one is put at the end where there is none."
  (interactive "sLemmata like (beta code or Greek): ")
  (let* ((beta (diorisis--beta like))
         (pattern (if (string-search "%" beta) beta (concat beta "%")))
         (rows (diorisis--select
                "SELECT lemma, COUNT(*) FROM occurrences WHERE lemma LIKE ?\
 GROUP BY lemma ORDER BY 2 DESC LIMIT 40"
                (list pattern))))
    (if (null rows)
        (message "The corpus holds no lemma like %s" pattern)
      (with-current-buffer (get-buffer-create "*Diorisis lemmata*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "lemmata like %s\n\n" pattern))
          (dolist (row rows)
            (insert (format "   %-18s %-14s %8s\n"
                            (nth 0 row)
                            (diorisis--greek (nth 0 row))
                            (nth 1 row))))
          (goto-char (point-min)))
        (special-mode)
        (diorisis--display (current-buffer))))))

(defun diorisis-query-explain ()
  "Show the SQL this query becomes, and what each element finds alone.

FOR WHEN A QUERY FINDS NOTHING AND THE READER CANNOT SEE WHY.  A query of
three elements is a self-join with arithmetic on the word positions, and
`nothing\=' has half a dozen causes that look alike from the outside: a feature
the corpus never writes, two features nothing can satisfy at once -- `particle
part\=', a particle that is also a participle -- an element in the wrong order,
or a distance too short.

SO EACH ELEMENT IS COUNTED ON ITS OWN, which separates those at once: an
element finding nothing by itself is the fault, and elements that each find
thousands while the whole finds nothing is a question about the order or the
distance between them.

And the SQL is printed, because it is the only way to see what was actually
asked -- and because a reader who knows SQL can then say what is wrong with it
faster than I can guess."
  (interactive)
  (let* ((spec (diorisis--query-as-spec))
         (elements (plist-get spec :elements))
         (buffer (get-buffer-create "*Diorisis query explained*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Each element on its own\n\n" 'face 'bold))
        (let ((number 0))
          (dolist (element elements)
            (setq number (1+ number))
            ;; THE ONE ELEMENT FIRST IN THE PLIST, and this is the whole of
            ;; why the counts were wrong.  `plist-get' takes the FIRST
            ;; occurrence of a key, so appending `:elements' to a spec that
            ;; already has one left the original in force: every `alone'
            ;; count ran the whole query and reported it as the element's,
            ;; which said that each element found nothing when two of them
            ;; found thousands.
            (let* ((alone (append (list :elements (list element)
                                        :limit 1)
                                  (copy-sequence spec)))
                   (found (ignore-errors (diorisis-count alone))))
              (insert (format "%2d. %-58s %s\n"
                              number
                              ;; DESCRIBED AS A FIRST ELEMENT, which is what
                              ;; it is when counted alone: its relation and
                              ;; its distance are to the element before it,
                              ;; and there is none.
                              (diorisis--describe-element element t)
                              (cond ((null found) "could not be counted")
                                    ((zerop found)
                                     "NOTHING -- this element is the fault")
                                    (t (format "%d occurrences" found))))))))
        (insert (propertize "\nAll of them together\n\n" 'face 'bold))
        (insert (format "    %s\n"
                        (let ((all (ignore-errors
                                     (diorisis-count spec))))
                          (if all (format "%d occurrences" all)
                            "could not be counted"))))
        (insert (propertize "\nThe SQL\n\n" 'face 'bold))
        (let* ((where (diorisis--where spec))
               (joins (car (diorisis--elements elements))))
          (insert (diorisis--select-clause))
          (unless (string-empty-p joins) (insert "\n" joins))
          (insert "\nWHERE " (car where) "\n")
          (insert (propertize "\nand its values\n\n" 'face 'bold))
          ;; THE VALUES AS THE QUERY BINDS THEM, which is `--where\='s list and
          ;; that alone: it already carries the elements\=' values, since it
          ;; built their clauses, and printing `--elements\=' as well listed
          ;; every one of them twice.
          (dolist (value (cdr where))
            (insert (format "    %S\n" value))))
        (goto-char (point-min)))
      (special-mode)
      (setq-local truncate-lines nil))
    (diorisis--display buffer)))

(defun diorisis--saved-queries ()
  "The queries in the old single file, as (NAME . ELEMENTS).

KEPT FOR WHAT IS ALREADY SAVED.  Queries go to
`diorisis-saved-directory\=' now, with the searches; this reads the file
they used to go to, so that nothing saved before is lost."
  (let ((file diorisis-query-file))
    (and file (file-readable-p file)
         (ignore-errors
           (with-temp-buffer
             (insert-file-contents file)
             (goto-char (point-min))
             (read (current-buffer)))))))

(defun diorisis-query-save (name)
  "Save the query as NAME, among the searches."
  (interactive (list (read-string "Save the query as: ")))
  (unless diorisis--query (user-error "The query is empty"))
  (diorisis-save-search name (diorisis--query-as-spec)))

(defun diorisis-query-load (name)
  "Load a saved query or search called NAME into the builder."
  (interactive
   (list (let ((names (append
                       (mapcar (lambda (one) (plist-get one :name))
                               (diorisis--saved-searches))
                       (mapcar #'car (diorisis--saved-queries)))))
           (unless names (user-error "Nothing saved yet"))
           (completing-read "Load: " names nil t))))
  (let* ((new (seq-find (lambda (one) (equal (plist-get one :name) name))
                        (diorisis--saved-searches)))
         (old (assoc name (diorisis--saved-queries)))
         (spec (and new (plist-get new :spec))))
    (cond
     ((and spec (plist-get spec :elements))
      (setq diorisis--query (plist-get spec :elements))
      (setq diorisis--query-spec spec))
     (spec
      ;; A PLAIN SEARCH LOADED INTO THE BUILDER is its narrowings and no
      ;; elements: which is a reasonable thing to want -- the same texts, a
      ;; new question -- and better than refusing it.
      (setq diorisis--query-spec spec))
     (old (setq diorisis--query (cdr old)))
     (t (user-error "Nothing called %s" name)))
    (diorisis--render-query)))

(defvar-keymap diorisis-query-mode-map
  :doc "Keys while composing a Diorisis query.

EVERY ONE OF THEM TWICE, once as a letter and once under `C-c'.  The letters
are what a reader wants and what evil takes: `a' appends, `d' is an operator,
`k' and `l' are motions, `c' changes and `q' records a macro, so in normal
state the builder has no interface at all.  Emacs state is arranged for
elsewhere -- see `diorisis-evil-emacs-state-modes' -- and this is the belt
to that braces: a `C-c' key is nobody else's, and works in any state, under
any framework, and in a buffer that was made before any of it was set up."
  "C-c a"   #'diorisis-query-add
  "C-c C-d" #'diorisis-query-delete
  "C-c k"   #'diorisis-query-clear
  "C-c n"   #'diorisis-query-narrow
  "C-c RET" #'diorisis-query-run
  "C-c c"   #'diorisis-query-count
  "C-c x"   #'diorisis-query-explain
  "C-c s"   #'diorisis-query-save
  "C-c l"   #'diorisis-query-load
  "a"   #'diorisis-query-add
  "d"   #'diorisis-query-delete
  "k"   #'diorisis-query-clear
  "n"   #'diorisis-query-narrow
  "RET" #'diorisis-query-run
  "c"   #'diorisis-query-count
  "x"   #'diorisis-query-explain
  "S"   #'diorisis-query-save
  "l"   #'diorisis-query-load
  "q"   #'quit-window)

(define-derived-mode diorisis-query-mode special-mode "Diorisis query"
  "Composing a query of several elements.

\\{diorisis-query-mode-map}"
  (setq-local truncate-lines nil)
  (visual-line-mode 1)
  (diorisis--evil-enter-state)
  (diorisis--evil-keys diorisis-query-mode-map))

(defun diorisis-query ()
  "Build a query of several elements and run it.

    the form o( followed by (ignore punctuation), within 3,
      a form of a)nh/r

Every element the corpus can be asked about, and the relations between them:
see `diorisis--elements' for what becomes of them, which is one join per
element and one pass over the database."
  (interactive)
  (let ((buffer (get-buffer-create "*Diorisis query*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'diorisis-query-mode)
        (diorisis-query-mode))
      (diorisis--render-query))
    (diorisis--display buffer)))

(defconst diorisis--upos
  '(("noun" . "NOUN") ("verb" . "VERB") ("adjective" . "ADJ")
    ("adverb" . "ADV") ("article" . "DET") ("conjunction" . "CCONJ")
    ("particle" . "PART") ("preposition" . "ADP") ("pronoun" . "PRON")
    ("numeral" . "NUM") ("interjection" . "INTJ") ("proper" . "PROPN")
    ("exclamation" . "INTJ") ("adverbial" . "ADV")
    ("expletive" . "PART") ("geog_name" . "PROPN")
    ("interrog" . "PRON") ("punctuation" . "PUNCT"))
  "Diorisis' parts of speech, as Universal Dependencies names them.

THE CORPUS'S OWN TAGSET IS THE DIOGENES WORD LIST'S, which distinguishes
things UD does not -- `geog_name' from `proper', `interrog' from `pronoun' --
so the mapping loses something.  Both are written out: UPOS for a tool that
expects UD, and XPOS keeping the corpus's own word, which is the one that can
be got back.")

(defconst diorisis--features
  '(("nom" "Case=Nom") ("gen" "Case=Gen") ("dat" "Case=Dat")
    ("acc" "Case=Acc") ("voc" "Case=Voc")
    ("sg" "Number=Sing") ("pl" "Number=Plur") ("dual" "Number=Dual")
    ("masc" "Gender=Masc") ("fem" "Gender=Fem") ("neut" "Gender=Neut")
    ("1st" "Person=1") ("2nd" "Person=2") ("3rd" "Person=3")
    ("pres" "Tense=Pres") ("imperf" "Tense=Imp") ("fut" "Tense=Fut")
    ("aor" "Tense=Past|Aspect=Perf") ("perf" "Tense=Past|Aspect=Perf")
    ("plup" "Tense=Pqp") ("futperf" "Tense=Fut|Aspect=Perf")
    ("ind" "Mood=Ind") ("subj" "Mood=Sub") ("opt" "Mood=Opt")
    ("imperat" "Mood=Imp") ("inf" "VerbForm=Inf")
    ("part" "VerbForm=Part")
    ("act" "Voice=Act") ("mid" "Voice=Mid") ("pass" "Voice=Pass")
    ("mp" "Voice=MidPass")
    ("comp" "Degree=Cmp") ("superl" "Degree=Sup")
    ("irreg_comp" "Degree=Cmp") ("irreg_superl" "Degree=Sup"))
  "The corpus's morphological values, as UD features.

READ OFF THE CORPUS'S OWN DOCUMENTATION -- Vatri and McGillivray 2018, table
4 -- and not guessed from what turns up in the data, so a value that is rare
is here too.  The list also serves the query builder, which offers these to
complete on rather than making a reader remember them.

Two roughnesses, both in UD and not in the corpus: the aorist and the perfect
are one tense and two aspects in UD and are written the same way here, and the
dialect and register values -- attic, doric, epic -- have no UD feature at
all, so they are left to XPOS and to a morphology search.")

(defconst diorisis--feature-groups
  '(("case" "nom" "gen" "dat" "acc" "voc")
    ("number" "sg" "pl" "dual")
    ("gender" "masc" "fem" "neut")
    ("person" "1st" "2nd" "3rd")
    ("tense" "pres" "imperf" "fut" "aor" "perf" "plup" "futperf")
    ("mood" "ind" "subj" "opt" "imperat" "inf" "part")
    ("voice" "act" "mid" "pass" "mp")
    ("degree" "comp" "superl" "irreg_comp" "irreg_superl")
    ("dialect" "attic" "doric" "ionic" "aeolic" "epic" "homeric"
     "poetic" "prose" "alphabetic")
    ("word class" "adverb" "adverbial" "conj" "exclam" "expletive"
     "geog_name" "interrog" "numeral" "particle" "prep")
    ("other" "a_priv" "contr" "enclitic" "indec" "indeclform"
     "iota_intens" "nu_movable" "parad_form" "proclitic"))
  "The morphological values a reader may ask for, by category.

The app puts these in a form of drop-down menus, which is the right shape for
a tagset nobody remembers: `mp' for medio-passive and `plup' for pluperfect
are not guessable.  Offered for completion by
`diorisis-read-morphology'.")

(defconst diorisis--feature-glosses
  '(("part" . "participle")
    ("particle" . "a particle: \u03bc\u03ad\u03bd, \u03b4\u03ad, \u03b3\u03ac\u03c1 -- indeclinable")
    ("inf" . "infinitive")
    ("imperat" . "imperative")
    ("ind" . "indicative")
    ("subj" . "subjunctive")
    ("opt" . "optative")
    ("mp" . "middle or passive")
    ("plup" . "pluperfect")
    ("futperf" . "future perfect")
    ("imperf" . "imperfect")
    ("adverbial" . "used adverbially")
    ("interrog" . "interrogative")
    ("indeclform" . "an indeclinable form")
    ("indec" . "indeclinable")
    ("expletive" . "expletive")
    ("prep" . "a preposition -- indeclinable")
    ("conj" . "a conjunction -- indeclinable")
    ("exclam" . "an exclamation")
    ("irreg_comp" . "irregular comparative")
    ("irreg_superl" . "irregular superlative")
    ("a_priv" . "with alpha privative")
    ("nu_movable" . "with movable nu")
    ("iota_intens" . "with intensive iota"))
  "What some of the values mean, where the name does not say.

WRITTEN FOR THE PAIR THAT COST AN EVENING.  `part\=' is the participle and
`particle\=' is the class of \u03bc\u03ad\u03bd and \u03b4\u03ad -- one letter apart in a list of a
hundred, and a reader who picks the second while meaning the first asks for a
word that is a particle and a genitive, which no word is.  The list said only
`particle   word class\=', which is true and does not warn anybody.")

(defconst diorisis--uninflected-features
  '("particle" "prep" "conj" "adverb" "adverbial" "exclam" "expletive"
    "interrog" "indec" "indeclform" "proclitic" "enclitic" "geog_name")
  "Values that describe a word admitting no case, number, tense or mood.

A PARTICLE HAS NO CASE, and a preposition none, and a conjunction none: they
are indeclinable, and asking for one of these together with a case or a tense
is asking for a word that does not exist.  The prompt takes the inflectional
categories off the list once one of these is chosen, and takes these off once
an inflection is.")

(defun diorisis--inflectional-group-p (category)
  "Whether CATEGORY is one an indeclinable word cannot have."
  (member category '("case" "number" "gender" "person" "tense" "mood"
                     "voice" "degree")))

(defun diorisis--features-left (chosen groups said)
  "The values still worth offering, CHOSEN being what has been picked.

THREE RULES, AND THE THIRD IS THE ONE THAT WAS MISSING.

A CATEGORY IS ASKED ONCE: choosing `gen\=' takes the other cases away, a word
not being genitive and nominative at once.

AN INDECLINABLE WORD HAS NO INFLECTIONS: choosing `particle\=', `prep\=' or
`conj\=' takes away case, number, gender, person, tense, mood, voice and
degree.  A particle has no case -- so `particle gen\=' asks for a word that
cannot exist, and the search rightly found none, which read as a fault in the
corpus.

AND THE CONVERSE: choosing an inflection takes the indeclinable classes away,
so `gen\=' can no longer be joined to `particle\='.  The prompt used to allow
both because they sit in different categories and only a category was being
ruled out -- which is why one could build a question with no possible answer
and get no warning at all."
  (let* ((used (delete-dups
                (delq nil (mapcar (lambda (one) (gethash one said)) chosen))))
         (indeclinable
          (seq-some (lambda (one)
                      (member one diorisis--uninflected-features))
                    chosen))
         (inflected
          (seq-some (lambda (one)
                      (diorisis--inflectional-group-p (gethash one said)))
                    chosen)))
    (apply #'append
           (mapcar
            (lambda (group)
              (let ((category (car group)))
                (cond
                 ((member category used) nil)
                 ((and indeclinable
                       (diorisis--inflectional-group-p category))
                  nil)
                 (t (seq-remove
                     (lambda (value)
                       (and inflected
                            (member value
                                    diorisis--uninflected-features)))
                     (copy-sequence (cdr group)))))))
            groups))))

(defun diorisis-read-morphology (&optional prompt)
  "Read morphological features, one at a time, until the reader stops.

ONE AT A TIME AND NOT COMMA-SEPARATED.  `completing-read-multiple\=' wants the
reader to type the separator, and under most completion frameworks the first
`RET\=' closes the prompt -- so a combination meant knowing to write
`part,gen\=' rather than choosing `part\=' and then `gen\='.  This asks again
after each answer, and an empty answer ends it.

WHAT HAS BEEN CHOSEN IS IN THE PROMPT, and WHAT CANNOT GO WITH IT IS GONE
FROM THE LIST: see `diorisis--features-left\='.  A question with no
possible answer is not offered.

EACH VALUE SAYS WHAT IT IS.  Its category, and for the ones whose name
misleads, what it means -- `part   mood -- participle\=' against `particle
word class -- a particle: \u03bc\u03ad\u03bd, \u03b4\u03ad, \u03b3\u03ac\u03c1 -- indeclinable\='.  Those two are
one letter apart and mean nothing like each other.

Anything may be typed: a reader who knows the tagset can write a value the
corpus has and this list does not."
  (let* ((groups diorisis--feature-groups)
         (said (make-hash-table :test #'equal))
         (chosen nil)
         (done nil))
    (dolist (group groups)
      (dolist (value (cdr group))
        (puthash value (car group) said)))
    (while (not done)
      (let* ((left (diorisis--features-left chosen groups said))
             (completion-extra-properties
              (list :annotation-function
                    (lambda (candidate)
                      (let ((category (gethash candidate said))
                            (gloss (cdr (assoc
                                         candidate
                                         diorisis--feature-glosses))))
                        (concat (and category (format "   %s" category))
                                (and gloss (format " -- %s" gloss)))))))
             (answer
              (if (null left)
                  ""
                (string-trim
                 (completing-read
                  (if chosen
                      (format "%s [%s] and (empty to search): "
                              (or prompt "Features")
                              (string-join (reverse chosen) " "))
                    (or prompt "Features (empty for any): "))
                  left nil nil)))))
        (if (string-empty-p answer)
            (setq done t)
          (push answer chosen))))
    (string-join (reverse chosen) " ")))

(defun diorisis--morph-clauses (alias morph)
  "MORPH as (SQL . VALUES) against ALIAS\='s analyses, one clause per feature.

ONE `LIKE\=' FOR EACH WORD AND NOT ONE FOR THE PHRASE, which is the whole of
this function and a fault worth recording.  An analysis is written in the
corpus\=' own order -- `aor part act masc gen sg\=' -- and a reader asking for a
genitive participle types `gen part\=', which as a phrase occurs nowhere: the
search matched the words in the order they were typed and found nothing, and
said so, which looked like the corpus lacking what it has thousands of.

Each feature is asked for separately and the answers ANDed, so the order a
reader types them in no longer matters.

WHAT IS STILL WRONG WITH IT, and cannot be right without the merged columns:
a form admitting several analyses has them joined by ` | \=', and these clauses
may be satisfied ACROSS the bar -- a word that is a genitive noun in one
reading and a participle in another matches `gen part\='.  The merged database
has a column per category and asks the question exactly; this is the best a
string can do.

A WILDCARD IS LEFT ALONE: a feature holding `%\=' is passed through as the
reader wrote it, `aor%sg\=' being a phrase they meant."
  (let ((clauses nil)
        (values nil))
    (dolist (feature (split-string (or morph "") "[ ,]+" t))
      (push (format "COALESCE(%s.morph, \'\') LIKE ?" alias) clauses)
      (push (if (string-match-p "%" feature)
                feature
              (format "%%%s%%" feature))
            values))
    (cons (nreverse clauses) (nreverse values))))

(defcustom diorisis-language 'greek
  "Which scheme a tree is annotated by.

`greek\=' is the Ancient Greek Dependency Treebank\='s, and is the default
because the corpus this package is built on is Greek.  `latin\=' is the Latin
Dependency Treebank\='s, for a reader annotating a Latin text from Diogenes
with `treebank-annotate-region\='.

WHAT IT CHANGES is the postag: the nine places, the letters in them, and the
words the editor prints for them.  The relations are one set for both
treebanks, which share the Prague scheme.

SET PER BUFFER BY THE EDITOR.  A tree opened from a file takes its language
from the file\='s own `xml:lang\=', so this option is the default for a tree
being made and not a thing to change when reading one: a Latin tree opened in
a session of Greek reads its postags by the Latin table without being told."
  :type '(choice (const :tag "Greek, the AGDT's scheme" greek)
                 (const :tag "Latin, the LDT's scheme" latin))
  :group 'diorisis)

(defcustom diorisis-postag-style 'words
  "How a postag is shown in the editor: as words, as its code, or both.

`n-s---mg-\=' is what the file holds and what other tools read, and it is not
something to ask a reader to decode at every line: the nine places are a
part of speech, a person, a number, a tense, a mood, a voice, a gender, a
case and a degree, in that order, and a dash for each that does not apply.

`words\=' prints what it means -- `noun sg masc gen\=' -- which is longer and
legible.  `code\=' prints the nine places.  `both\=' prints the words with the
code after them, for a reader learning to read the code."
  :type '(choice (const :tag "As words" words)
                 (const :tag "As the nine-place code" code)
                 (const :tag "Both" both))
  :group 'diorisis)

(defconst diorisis-relations
  '(("PRED" . "the predicate: the verb the sentence hangs from")
    ("SBJ" . "subject: who or what does it")
    ("OBJ" . "object: what it is done to, direct or indirect")
    ("ATR" . "attribute: modifies a noun -- adjective, genitive, article")
    ("ADV" . "adverbial: how, when, where, why")
    ("PNOM" . "predicate noun: the complement of `to be'")
    ("OCOMP" . "object complement: what the object is called or made")
    ("ATV" . "a participle or adjective agreeing with another word")
    ("ATVV" . "the same, where it stands alone as a complement")
    ("AuxP" . "a preposition")
    ("AuxC" . "a subordinating conjunction")
    ("AuxV" . "an auxiliary verb: a form of `to be' with a participle")
    ("AuxR" . "a reflexive that marks a passive")
    ("AuxX" . "a comma")
    ("AuxG" . "other punctuation inside the sentence")
    ("AuxK" . "the full stop, or whatever ends the sentence")
    ("AuxY" . "a particle or adverb belonging to the whole sentence")
    ("AuxZ" . "a particle emphasising one word")
    ("COORD" . "a coordinating conjunction: what joins the members")
    ("APOS" . "what joins an apposition to what it stands for")
    ("ExD" . "its head is not in the sentence: ellipsis")
    ("UNDEFINED" . "not decided yet"))
  "The relations of the Ancient Greek Dependency Treebank, and what each is.

WITH A GLOSS EACH, because the names are opaque and a reader choosing between
twenty-two of them cannot be expected to have the guidelines open: `PNOM\\=' and
`OCOMP\\=' and `ATV\\=' are not guessable, and picking the wrong one is worse than
leaving a word unattached.  The glosses are short on purpose -- they are to
recognise a relation by, not to define it -- and the guidelines remain the
authority.

THE SUFFIXES ARE NOT LISTED.  A member of a coordination takes `_CO\\=' after
its relation and a member of an apposition `_AP\\=' -- `ATR_CO\\=' -- which the
guidelines allow on any of these and would multiply the list by three.  They
are offered as completions of what has been typed, and anything at all may be
typed: a project with its own conventions is not this file\\='s business to
refuse.")

(defcustom diorisis-complete-diogenes-lemmata t
  "Whether Diogenes\\=' lemma commands should read with completion.

Non-nil advises `diogenes-show-all-forms-greek' and
`diogenes-show-all-lemmata-greek' to read their argument with the prompt
described above -- beta code or Greek, diacritics optional, candidates as you
type -- instead of a plain string.

ANOTHER PACKAGE\\='S COMMANDS, so this is worth a word.  Nothing of Diogenes is
edited and nothing of its behaviour changes: the advice replaces the
INTERACTIVE FORM only, and the command receives the same kind of string it
always did.  Nil, or `diorisis-complete-off\\=', restores the plain
prompts."
  :type 'boolean
  :group 'diorisis)

(defcustom diorisis-lemma-source 'diogenes
  "Which lemmata Diogenes\\=' commands complete on.

`diogenes' is its own word list, which is what its dictionaries are keyed on
and includes every lemma whether or not it occurs anywhere in Diorisis.

`diorisis' is the 63,718 the corpus attests -- a smaller list, and the better
one for a corpus search, where offering a word that occurs nowhere is offering
an empty result.

`both' is the union, which is the union of two answers to different questions
and is here for completeness rather than because it is wise."
  :type '(choice (const :tag "Diogenes' whole word list" diogenes)
                 (const :tag "The lemmata Diorisis attests" diorisis)
                 (const :tag "Both" both))
  :group 'diorisis)

(defun diorisis--diogenes-lemmata ()
  "Every lemma in Diogenes\\=' Greek word list, as beta code.

Nil where Diogenes is not installed or its Perseus data is not where it
expects, in which case the caller falls back on ours -- a shorter list being
better than a prompt with nothing in it."
  (when (or (featurep 'diogenes-perseus)
            (and (locate-library "diogenes-perseus")
                 (require 'diogenes-perseus nil t)))
    (when (fboundp 'diogenes--get-all-lemmata)
      (let ((table (ignore-errors (diogenes--get-all-lemmata "greek"))))
        (and (hash-table-p table) (hash-table-keys table))))))

(defun diorisis--source-pairs (source)
  "The candidates and their bare forms for SOURCE, with a beta hash.

Returns (PAIRS . BETA), PAIRS being (CANDIDATE . BARE)."
  (let ((known (assq source diorisis--source-cache)))
    (unless known
      (let* ((beta (make-hash-table :test #'equal))
             (raws (pcase source
                     ('diorisis (mapcar #'car (diorisis-lemmata)))
                     ('diogenes (or (diorisis--diogenes-lemmata)
                                    (mapcar #'car (diorisis-lemmata))))
                     (_ (delete-dups
                         (append (diorisis--diogenes-lemmata)
                                 (mapcar #'car (diorisis-lemmata)))))))
             (pairs nil))
        (message "Reading %d lemmata as Greek ..." (length raws))
        (dolist (raw raws)
          (let ((shown (diorisis--greek raw)))
            ;; THE FIRST SPELLING WINS where two beta lemmata convert alike:
            ;; the candidate is what a reader sees and two identical lines
            ;; would be a choice between indistinguishables.
            (unless (gethash shown beta)
              (puthash shown raw beta)
              (push (cons shown (diorisis--bare shown)) pairs))))
        ;; ALPHABETICAL, BY THE BARE FORM.  Diogenes' word list carries no
        ;; frequencies -- the corpus prompt has those and sorts by them -- and
        ;; a hash table's own order is no order at all: a reader given a
        ;; hundred thousand candidates in the order they happened to hash
        ;; would rightly call it broken.  Bare, so that the accents do not
        ;; scatter words that belong together.
        (setq known (cons source
                          (sort (nreverse pairs)
                                (lambda (a b)
                                  (string-lessp (cdr a) (cdr b))))))
        (push known diorisis--source-cache)
        (push (cons source beta) diorisis--source-beta)))
    (cons (cdr known) (cdr (assq source diorisis--source-beta)))))

(defun diorisis-read-greek-lemma (&optional prompt source)
  "Read a Greek lemma with candidates, and return it as beta code.

SOURCE defaults to `diorisis-lemma-source'.  The matching is the same as
the corpus prompt's -- see `diorisis--filter' -- so beta code and Greek
both work and the diacritics typed are the ones required."
  (let* ((source (or source diorisis-lemma-source))
         (found (diorisis--source-pairs source))
         (pairs (car found))
         (beta (cdr found))
         (diorisis--completion-pairs pairs)
         (table (lambda (string predicate action)
                  (pcase action
                    ('metadata
                     '(metadata (category . diorisis-lemma)
                                (display-sort-function . identity)
                                (cycle-sort-function . identity)))
                    (_ (complete-with-action action (mapcar #'car pairs)
                                             string predicate)))))
         (answer (string-trim
                  (completing-read (or prompt "Lemma: ") table nil nil))))
    (or (gethash answer beta)
        (diorisis--beta answer))))

(defconst diorisis--advised-commands
  '((diogenes-show-all-forms-greek . "Show all forms of: ")
    (diogenes-show-all-lemmata-greek . "Show all lemmata matching: "))
  "Diogenes\\=' Greek lemma commands, and the prompt each should ask.")

(defun diorisis-complete-on ()
  "Have Diogenes' Greek lemma commands read with completion.

NOTHING TO DO WHERE DIOGENES DOES IT ITSELF.  `diogenes-complete.el' provides
`diogenes-read-lemma', and its own commands read with it -- which is where the
feature belongs: it completes Diogenes' word list for Diogenes' searches and
has nothing to do with this corpus.  This advice is what to do until that file
is in the branch one is running, and stands down once it is there."
  (interactive)
  (if (fboundp 'diogenes-read-lemma)
      (progn
        (diorisis-complete-off)
        (setq diorisis-complete-diogenes-lemmata nil))
    (dolist (pair diorisis--advised-commands)
      (let ((command (car pair))
            (prompt (cdr pair)))
        (when (fboundp command)
        (advice-add
         command :around
         ;; THE ADVICE CARRIES THE INTERACTIVE FORM, which is the whole
         ;; mechanism: where an advice has one it is used instead of the
         ;; command's, so the reading changes and the command does not.
         (lambda (original &rest args)
           (interactive (list (diorisis-read-greek-lemma prompt)))
           (apply original args))
         `((name . ,(intern (format "tei-diorisis-complete-%s"
                                    command))))))))))

(defun diorisis-complete-off ()
  "Give Diogenes\\=' lemma commands their plain prompts back."
  (interactive)
  (dolist (pair diorisis--advised-commands)
    (let ((command (car pair)))
      (when (fboundp command)
        (advice-remove command
                       (intern (format "tei-diorisis-complete-%s" command))))))
  (message "Diogenes' lemma prompts are plain again"))

(with-eval-after-load 'diogenes
  (when diorisis-complete-diogenes-lemmata
    (diorisis-complete-on)))

(defcustom diorisis-saved-directory
  (expand-file-name "diorisis-searches/" user-emacs-directory)
  "Where saved searches are kept, one file to a search.

A DIRECTORY AND NOT A FILE, so that a search can be moved, copied into a
project, or kept under version control with the notes it belongs to.  Each is
an `.eld\\=': a plist with the search in it, readable and editable by hand."
  :type 'directory
  :group 'diorisis)

(defun diorisis--saved-file (name)
  "The file a search called NAME is kept in."
  (expand-file-name
   (concat (replace-regexp-in-string "[^[:alnum:]._-]+" "-" name) ".eld")
   diorisis-saved-directory))

(defun diorisis-save-search (name &optional spec)
  "Save SPEC, or this buffer's search, under NAME.

WHAT IS SAVED IS THE QUESTION AND NOT THE ANSWER: the spec, not the hits.  So
a search opened after the index has been rebuilt finds what the corpus says
now, which is the point of keeping it -- and a set of hits kept as hits would
be a list of citations going quietly out of date."
  (interactive (list (read-string "Save this search as: ")))
  (let ((spec (or spec diorisis--spec
                  (and diorisis--query (diorisis--query-as-spec))
                  (user-error "No search to save"))))
    (make-directory diorisis-saved-directory t)
    (with-temp-file (diorisis--saved-file name)
      (let ((print-length nil) (print-level nil))
        (prin1 (list :name name
                     :saved (format-time-string "%F %R")
                     :said (diorisis--describe spec)
                     :spec spec)
               (current-buffer))))
    (message "Saved as %s" name)))

(defun diorisis--saved-searches ()
  "Every saved search, as a plist each, newest first."
  (let ((files (and (file-directory-p diorisis-saved-directory)
                    (directory-files diorisis-saved-directory t
                                     "\\.eld\\'"))))
    (sort
     (delq nil
           (mapcar (lambda (file)
                     (let ((datum (ignore-errors
                                    (with-temp-buffer
                                      (insert-file-contents file)
                                      (goto-char (point-min))
                                      (read (current-buffer))))))
                       (and (plist-get datum :spec)
                            (append datum (list :file file)))))
                   files))
     (lambda (a b) (string> (or (plist-get a :saved) "")
                            (or (plist-get b :saved) ""))))))

(defun diorisis-open-search ()
  "Run a search that was saved before.

Shows what each was, and when it was saved -- a name six weeks old says less
than `lemma \u03bc\u03cd\u03c9 \u00b7 morphology perf part\\=' does."
  (interactive)
  (let* ((saved (diorisis--saved-searches))
         (labels (mapcar (lambda (one)
                           (cons (format "%-24s %s   %s"
                                         (or (plist-get one :name) "?")
                                         (or (plist-get one :saved) "")
                                         (or (plist-get one :said) ""))
                                 one))
                         saved)))
    (unless labels (user-error "No searches saved in %s"
                               diorisis-saved-directory))
    (let* ((chosen (cdr (assoc (completing-read "Open which search? "
                                                labels nil t)
                               labels)))
           (spec (plist-get chosen :spec)))
      ;; A QUERY OF ELEMENTS OPENS IN THE BUILDER, a plain search in the
      ;; results: what one wants to do with a query is add to it, and what one
      ;; wants to do with a search is read it.
      (if (plist-get spec :elements)
          (let ((buffer (get-buffer-create "*Diorisis query*")))
            (with-current-buffer buffer
              (unless (derived-mode-p 'diorisis-query-mode)
                (diorisis-query-mode))
              (setq diorisis--query (plist-get spec :elements))
              (setq diorisis--query-spec spec)
              (diorisis--render-query))
            (diorisis--display buffer))
        (diorisis--show spec)))))

(defun diorisis-delete-search ()
  "Forget a saved search."
  (interactive)
  (let* ((saved (diorisis--saved-searches))
         (labels (mapcar (lambda (one)
                           (cons (or (plist-get one :name) "?") one))
                         saved)))
    (unless labels (user-error "Nothing saved"))
    (let ((chosen (cdr (assoc (completing-read "Forget which? " labels nil t)
                              labels))))
      (when (y-or-n-p (format "Forget %s? " (plist-get chosen :name)))
        (delete-file (plist-get chosen :file))
        (message "Forgotten")))))

(defcustom diorisis-evil-emacs-state-modes
  '(diorisis-results-mode
    diorisis-sentence-mode
    diorisis-query-mode
    treebank-tree-mode)
  "Diorisis modes to start in evil's Emacs state.

Each is a read-only view whose commands are single letters -- and the query
builder is nothing but single letters, so in normal state it has no interface
at all.

`diorisis-text-mode' is deliberately not here: see the commentary above.
Add it if you would rather have its `n', `p', `g' and `w' than evil's
motions."
  :type '(repeat symbol)
  :group 'diorisis)

(defcustom diorisis-evil-manage-initial-states t
  "Whether to put `diorisis-evil-emacs-state-modes' into Emacs state.

Nil leaves evil's defaults alone, for a reader who would rather bind the keys
into normal state themselves -- which in the results buffer costs `d', `l',
`n', `p', `s', `v' and `w', and in the builder costs everything."
  :type 'boolean
  :group 'diorisis)

(defun diorisis--evil-enter-state ()
  "Put THIS buffer into Emacs state, where that is what its mode wants.

TWICE, AND THE SECOND TIME IS THE ONE THAT WORKS.  Called from a mode body,
this used to do nothing at all: it asks whether evil is on in the buffer, and
`evil-local-mode' is not on yet -- evil initialises a buffer from
`after-change-major-mode-hook', which runs AFTER the mode body that called
this.  So the test failed, nothing was done, and evil then put the buffer into
normal state, where every letter the editor binds is evil's.

So it asks now, for a buffer that is already initialised -- one whose mode is
being run again -- and asks again from a zero-second timer, which the command
loop runs after everything the mode start does, evil included.

`evil-set-initial-state' says the same thing to evil and is kept: it is the
right way to say it, and it is not enough on its own for a buffer that
existed before it was said."
  (when (and diorisis-evil-manage-initial-states
             (memq major-mode diorisis-evil-emacs-state-modes)
             (fboundp 'evil-emacs-state))
    (if (and (bound-and-true-p evil-local-mode)
             (not (eq (bound-and-true-p evil-state) 'emacs)))
        (evil-emacs-state)
      (run-at-time
       0 nil
       (lambda (buffer)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (when (and (bound-and-true-p evil-local-mode)
                        (memq major-mode
                              diorisis-evil-emacs-state-modes)
                        (not (eq (bound-and-true-p evil-state) 'emacs)))
               (evil-emacs-state)))))
       (current-buffer)))))

(defun diorisis-evil-report ()
  "Say what evil is doing to this buffer, and what we asked it to do.

FOR TELLING WHOSE FAULT IT IS.  A key that does nothing looks the same from
the outside whether the buffer is in normal state, whether our request was
registered, or whether the binding was never made -- and from inside the
buffer none of it is visible."
  (interactive)
  (message
   "%s: state %s, evil %s, asked for %s, `?' runs %s"
   major-mode
   (or (bound-and-true-p evil-state) "none")
   (if (bound-and-true-p evil-local-mode) "on" "off")
   (or (and (boundp 'evil-initial-state-alist)
            (cdr (assq major-mode evil-initial-state-alist)))
       "nothing")
   (or (ignore-errors (key-binding (kbd "?"))) "nothing")))

(defun diorisis--evil-keys (map)
  "Bind MAP's own keys in evil's normal state as well.

WHY BOTH THIS AND EMACS STATE.  Asking for Emacs state is the tidy answer and
has now failed twice in practice -- a buffer made before the state was
registered, a configuration that sets the state for `special-mode' and so for
everything derived from it, an `evil-collection' that has opinions.  Rather
than work out which, the keys are ALSO defined in normal state, where they
cannot be shadowed because they are the ones being looked up.

Only single keys, and only commands: a prefix key -- `C-c' -- is not
shadowed by evil and needs nothing done to it."
  (when (and (fboundp 'evil-define-key*) (keymapp map))
    (map-keymap
     (lambda (event definition)
       (when (and (commandp definition)
                  (not (keymapp definition))
                  (integerp event))
         (ignore-errors
           (evil-define-key* 'normal map (vector event) definition)
           (evil-define-key* 'motion map (vector event) definition))))
     map)))

(defun diorisis-evil-setup ()
  "Put our read-only modes into evil's Emacs state.

A MODE THE READER HAS ANSWERED FOR IS LEFT ALONE: an explicit
`evil-set-initial-state' in an init file is an answer, and this is only for
the modes nobody has answered for.  Brackets are lent back by
`diogenes-evil-lend-keys' where Diogenes' own evil file is loaded, that being
the one thing Emacs state costs which a reader misses."
  (interactive)
  (when (and diorisis-evil-manage-initial-states
             (fboundp 'evil-set-initial-state)
             (boundp 'evil-initial-state-alist))
    (dolist (mode diorisis-evil-emacs-state-modes)
      (unless (assq mode evil-initial-state-alist)
        (evil-set-initial-state mode 'emacs))
      (when (fboundp 'diogenes-evil-lend-keys)
        (ignore-errors (diogenes-evil-lend-keys mode))))))

(with-eval-after-load 'evil
  (diorisis-evil-setup))

(defcustom diorisis-add-to-diogenes-menu t
  "Whether to put an entry in Diogenes\\=' own transient menu.

Non-nil appends `Search the Diorisis corpus\\=' beside its SEARCH entries.  Nil
leaves the menu alone, for a reader who would rather bind
`diorisis-search\\=' themselves.

The entry appears only where both packages are present."
  :type 'boolean
  :group 'diorisis)

;;;###autoload
;; AUTOLOADED BECAUSE THE MENU HOOK NAMES IT, and add-hook runs from
;; the autoloads where this file has not loaded: run-hooks then found
;; a void function.  A cookie makes the name reachable, which is what
;; the fboundp guards above were doing by hand.
(defun diorisis--add-browse-to-diogenes-menu ()
  "Put our other entries in Diogenes\=' menu: the texts and the trees.

`bD\=' under BROWSE opens a Diorisis text, browsing being going to a place one
can name; `sa\=' under SEARCH finds an annotated tree, by work and then by
passage, which is a search and not a place.  Idempotent, each being added only
where it is not there already."
  (when (and (or (not (fboundp 'classicist-feature-p))
                 (classicist-feature-p 'diorisis))
             diorisis-add-to-diogenes-menu
             (fboundp 'transient-append-suffix))
    (ignore-errors
      (unless (ignore-errors (transient-get-suffix 'diogenes "bD"))
        (transient-append-suffix 'diogenes "bm"
          '("bD" "Browse the Diorisis corpus" diorisis-open-work))))
    ;; AND THE ANNOTATIONS UNDER SEARCH, as `sa\='.  They were under BROWSE,
    ;; on the reasoning that a tree already made is read rather than
    ;; searched -- which is the wrong way round: one does not know where a
    ;; tree is, and what the menu does is FIND it, by work and then passage.
    ;; Browsing is going to a place one can name.
    (ignore-errors
      (unless (ignore-errors (transient-get-suffix 'diogenes "sa"))
        ;; FROM `sm\=' AND NOT FROM `sD\='.  The two copies of this appending --
        ;; here and in the autoloads -- must agree, and `sD\=' is ours and may
        ;; be absent; `sm\=' is Diogenes\=' own.
        (transient-append-suffix 'diogenes "sm"
          '("sa" "Search the annotated trees"
            treebank-annotations-menu))))))

;;;###autoload
;; AUTOLOADED BECAUSE THE MENU HOOK NAMES IT, and add-hook runs from
;; the autoloads where this file has not loaded: run-hooks then found
;; a void function.  A cookie makes the name reachable, which is what
;; the fboundp guards above were doing by hand.
(defun diorisis--add-to-diogenes-menu ()
  "Put our entry in Diogenes' menu.  Idempotent.

IDEMPOTENT IN EARNEST, by asking whether the entry is there.  It can now be
appended from two places -- the autoloads, and here once this file is loaded
-- and `transient-append-suffix\=' asked twice appends twice, which showed as
two identical lines under SEARCH."
  (when (and (or (not (fboundp 'classicist-feature-p))
                 (classicist-feature-p 'diorisis))
             diorisis-add-to-diogenes-menu
             (fboundp 'transient-append-suffix))
    (ignore-errors
      (unless (ignore-errors (transient-get-suffix 'diogenes "sD"))
        (transient-append-suffix 'diogenes "sm"
          '("sD" "Search the Diorisis corpus by lemma"
            diorisis-search))))
    ;; THE BROWSE ENTRY AND THE ANNOTATIONS BOTH, and in this order: the
    ;; annotations are appended after `sD\=', which the form above has just
    ;; made, so they cannot be added before the entry they sit under exists.
    (diorisis--add-browse-to-diogenes-menu)))

;;;###autoload
;; ON classicist AND NOT ON diogenes.  This appends to the diogenes
;; transient, and that prefix is defined in classicist.el now -- its
;; autoload used to name the base file, which is why the base loaded and
;; this fired.  With the autoload corrected, waiting on the base means
;; waiting for a file that may never load, while the file defining the
;; thing being modified loads under another name.
(with-eval-after-load 'classicist
  (if (fboundp 'diorisis--add-to-diogenes-menu)
      (diorisis--add-to-diogenes-menu)
    (when (and (or (not (fboundp 'classicist-feature-p))
                   (classicist-feature-p 'diorisis))
               (if (boundp 'diorisis-add-to-diogenes-menu)
                   diorisis-add-to-diogenes-menu
                 t)
               (fboundp 'transient-append-suffix))
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "sD"))
          (transient-append-suffix 'diogenes "sm"
            '("sD" "Search the Diorisis corpus by lemma"
              diorisis-search))))
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "bD"))
          (transient-append-suffix 'diogenes "bm"
            '("bD" "Browse the Diorisis corpus"
              diorisis-open-work))))
      ;; AND THE ANNOTATIONS.  This form is the one that runs on a FRESH
      ;; Emacs -- before this file is loaded -- so an entry left out of it is
      ;; an entry that appears only once something has pulled the file in,
      ;; and vanishes again at the next restart.  `sa\=' was in the function
      ;; above and not here, which is exactly how it behaved.
      ;;
      ;; APPENDED AFTER `sa\='S OWN PREDECESSOR and not after `sD\=', because
      ;; `sD\=' may not be there: a reader with
      ;; `diorisis-add-to-diogenes-menu\=' nil, or a Diogenes whose SEARCH
      ;; section is named otherwise, would leave this with nothing to hang
      ;; from.  `sm\=' is Diogenes\=' own and is what the others hang from too.
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "sa"))
          (transient-append-suffix 'diogenes "sm"
            '("sa" "Search the annotated trees"
              treebank-annotations-menu)))))))

;; AND AGAIN WHEN THE BASE LOADS, because its own
;; transient-define-prefix REPLACES the diogenes prefix wholesale and
;; takes the appended suffixes with it: the first press showed them and
;; the second did not, the base having loaded in between.
;;
;; IDEMPOTENT, so twice is safe: each append asks transient-get-suffix
;; first, which is what that guard was put there for.
(with-eval-after-load 'diogenes
  (if (fboundp 'diorisis--add-to-diogenes-menu)
      (diorisis--add-to-diogenes-menu)
    (when (and (or (not (fboundp 'classicist-feature-p))
                   (classicist-feature-p 'diorisis))
               (if (boundp 'diorisis-add-to-diogenes-menu)
                   diorisis-add-to-diogenes-menu
                 t)
               (fboundp 'transient-append-suffix))
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "sD"))
          (transient-append-suffix 'diogenes "sm"
            '("sD" "Search the Diorisis corpus by lemma"
              diorisis-search))))
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "bD"))
          (transient-append-suffix 'diogenes "bm"
            '("bD" "Browse the Diorisis corpus"
              diorisis-open-work))))
      ;; AND THE ANNOTATIONS.  This form is the one that runs on a FRESH
      ;; Emacs -- before this file is loaded -- so an entry left out of it is
      ;; an entry that appears only once something has pulled the file in,
      ;; and vanishes again at the next restart.  `sa\=' was in the function
      ;; above and not here, which is exactly how it behaved.
      ;;
      ;; APPENDED AFTER `sa\='S OWN PREDECESSOR and not after `sD\=', because
      ;; `sD\=' may not be there: a reader with
      ;; `diorisis-add-to-diogenes-menu\=' nil, or a Diogenes whose SEARCH
      ;; section is named otherwise, would leave this with nothing to hang
      ;; from.  `sm\=' is Diogenes\=' own and is what the others hang from too.
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "sa"))
          (transient-append-suffix 'diogenes "sm"
            '("sa" "Search the annotated trees"
              treebank-annotations-menu)))))))

(with-eval-after-load 'classicist-browser
  (when (boundp 'diorisis-results-mode-map)
    (diorisis-install-mouse-keys)))

(declare-function treebank-annotate "treebank" (&optional hit))
(declare-function treebank-annotation-for "treebank" (hit))

;; NO DECLARATION FOR `treebank-annotations-menu'.  It is a
;; `transient-define-prefix', which check-declare does not recognise as a
;; definition -- it looks for defun and its relatives.  And it needs none: a
;; transient prefix is a command, and the three sites here name it in a
;; keymap or a transient row, which resolve at a keypress.
(declare-function treebank-collect "treebank" (&optional hit))
(declare-function treebank-collect-all "treebank" ())
(declare-function treebank-export-hits "treebank" ())
(declare-function treebank-export-sentence "treebank" (&optional hit))
(declare-function treebank-tree-mode "treebank" t)
(declare-function treebank-workbook "treebank" ())

(defun diorisis--work-present-p (author work)
  "Whether the corpus holds AUTHOR's WORK.
By the TLG's own numbers, which is what Diorisis files under -- so the two
numbers a citation gives go across as they come, with no mapping.

FOR THE LEXICA, which ask before offering a citation as a link: an entry full
of references that cannot lead anywhere is worse than an entry with fewer
links."
  (and (boundp 'diorisis-database) diorisis-database
       (file-exists-p diorisis-database)
       (ignore-errors
         (car (sqlite-select
               (diorisis--db)
               "SELECT 1 FROM texts WHERE author_id = ? AND work_id = ? LIMIT 1"
               (list author work))))
       t))


;; AND WHEN THE MENU IS DEFINED, which replaces the prefix whole and takes
;; every appended suffix with it.  The forms above stay: a reader may have
;; the base and not this suite's menu, and the entries belong there too.
;; Each append asks transient-get-suffix first, so twice is free.
;;;###autoload
(with-eval-after-load 'classicist
  (add-hook 'classicist-menu-defined-hook #'diorisis--add-to-diogenes-menu)
  (add-hook 'classicist-menu-defined-hook #'diorisis--add-browse-to-diogenes-menu))

(provide 'diorisis)

;;; diorisis.el ends here
