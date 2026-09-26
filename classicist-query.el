;;; classicist-query.el --- a query of elements -*- lexical-binding: t -*-

;; Copyright (C) 2026 Victor Gonçalves de Sousa

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; WHAT THE TLG CALLS AN ADVANCED PROXIMITY SEARCH, without the limit of
;; three elements: a word, a lemma, a lemma narrowed by its morphology, or a
;; word that must NOT appear, as many of them as a reader wants, within a
;; sentence or a paragraph or so many lines.
;;
;; AND IT NEEDS NOTHING LEMMATISED.  A lemma is expanded into its attested
;; forms on the LEMMA's side, out of the Perseus word lists that Diogenes
;; ships and Morpheus built -- `diogenes--get-all-forms' returns every form
;; with its parse -- and the corpus is then searched for those forms.  So the
;; TLG's hundred million words are searchable by lemma although not a word of
;; them is tagged.
;;
;; WHICH IS ALSO THE BOUNDARY.  A lemma narrowed by morphology works, because
;; the narrowing happens over a list already in hand.  A morphology with NO
;; lemma -- `any aorist participle' -- does not: that wants every token in
;; the corpus parsed, which is what the Diorisis corpus IS and the TLG is
;; not.  `diorisis-query' answers those, over ten million words, and can
;; measure distance in syntactic nodes besides.  The two are complements: the
;; TLG has the scale, Diorisis has the parse.
;;
;; THIS FILE IS THE FIRST HALF: reading an element, and filtering a lemma's
;; forms by morphology.  It answers with a list of forms, which is what
;; `diogenes--do-wordlist-search' already takes for a single element -- so it
;; is useful and testable before the proximity assembly exists.  See
;; `design-tlg-query.md' for the rest.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; THE BASE'S.  The word lists are its, and so is the expansion: this file
;; asks and filters and builds nothing of its own.
(declare-function diogenes--get-all-forms "diogenes-lemmata" (lemma lang))
(declare-function diogenes--get-all-lemmata "diogenes-lemmata" (lang))
;; THE SUITE'S OWN LEMMA READER, and the reason this file has none: a whole
;; file answers this question already.  `diogenes-complete.el' registers a
;; completion style of its own -- diacritic-insensitive, so `elpis' finds
;; `e)lpi/s' -- shows the candidates in Greek, affixes them with what they
;; mean, caches the table, and returns the lemma SPELLED AS THE WORD LIST
;; SPELLS IT, which is what an expansion wants and not what a reader typed.
;;
;; It also falls back on a plain prompt where the list cannot be read, so it
;; may be called unconditionally.  Which is why the version this file had --
;; `completing-read' over the raw beta keys, no Greek, no diacritic rule --
;; is gone: it was a worse answer to a solved question.
(declare-function diogenes-read-lemma "diogenes-complete"
                  (lang &optional prompt))
;; THE FORMS BUFFER, which is the base's and is the third way of naming what
;; to look for: a lemma's forms listed with their analyses and a box beside
;; each.  The same shape as the corpus picker in an advanced search, so it is
;; a buffer a reader of this suite has met before.
;;
;; IT ANSWERS WHAT A FILTER CANNOT.  The analyses carry more than the nine
;; postag places -- `(epic)' on a dialect form, an elision mark on
;; `e)/lec'' -- and a reader who wants exactly those forms and not their
;; fellows can only say so by pointing at them.
(declare-function diogenes--select-forms "diogenes-forms"
                  (query lang callback &optional header))
(declare-function diogenes--utf8-to-beta "diogenes-utils" (str))
(declare-function diogenes--beta-to-utf8 "diogenes-utils" (str))
(declare-function diogenes--strip-diacritics "diogenes-utils" (str))
(declare-function diogenes--probable-corpus-language "diogenes-search"
                  (type))
;; AND THE SUITE'S: the feature vocabulary the Diorisis prompt reads, which
;; asks one feature at a time and drops what cannot go with what has been
;; chosen already.  Reused rather than written again -- the morphological
;; vocabulary of Greek is the same whichever corpus is being asked.
;; AND THE SAVING, which is Diorisis' and is REUSED rather than repeated: one
;; directory, one format, one list a reader looks in.  See
;; `classicist-query-save'.
(declare-function diorisis--saved-file "diorisis" (name))
(declare-function diorisis--saved-searches "diorisis" ())
(defvar diorisis-saved-directory)
(declare-function classicist-feature-p "classicist-groups" (feature))
;; TRANSIENT'S, WITH AN UNSPECIFIED ARGLIST -- t t.  `transient-append-suffix'
;; takes an optional fourth argument, and writing three declared three
;; REQUIRED and the compiler then objected to the call.  A third party's
;; signature is not ours to track: `t t' says the function exists and where,
;; which is all `check-declare' verifies and all this needs.
(declare-function transient-append-suffix "transient" t t)
(declare-function transient-get-suffix "transient" t t)
;; AND `diogenes--tr--type' IS IN lisp-utils AND NOT IN search.  Guessed from
;; where the menus are, which is not where a one-line reader of the transient
;; scope lives -- the same mistake as naming `diogenes-lisp-utils' for
;; `diogenes--probable-corpus-language', which is in search.  The lesson is
;; to look, not to reason about which file a function belongs in.
(declare-function diogenes--tr--type "diogenes-lisp-utils" ())
;; THE ONE PLACE THAT DECIDES WHERE A BUFFER GOES, and the reason this file
;; does not call `pop-to-buffer': that made a window or a frame of its own
;; even from a startup screen, which is the one buffer that should always
;; yield its window -- `classicist-startup-screen-buffers' names them and
;; `classicist-display-buffer' takes the window rather than splitting away
;; from a page holding nothing.
(declare-function classicist-display-buffer "classicist-windows" t t)
;; AND THE SEARCH ITSELF, which is the base's: this file composes a plist and
;; hands it over, and writes no Perl and no search of its own.
(declare-function diogenes--do-search "diogenes-search"
                  (options-or-pattern &optional authors-plist))
(declare-function diogenes--do-wordlist-search "diogenes-search"
                  (options word-list &optional authors-plist))
(declare-function diogenes--search-select-authors "diogenes-search"
                  (type &optional simple callback))


;;;; Options

(defgroup classicist-query ()
  "A query of several elements over the Diogenes corpora."
  :group 'classicist)

(defcustom classicist-query-form-warning 500
  "How many forms an element may expand to before a reader is warned.

A COMMON VERB HAS THOUSANDS.  A lemma becomes a pattern by joining its forms
into one alternation, and an alternation of four thousand branches may cost
more than the corpus read it was meant to save.  So a reader is told the
count and asked, rather than finding out by waiting.

Nil asks nothing, for a reader who would rather wait than be asked."
  :type '(choice (const :tag "Never ask" nil) integer)
  :group 'classicist-query)

(defcustom classicist-query-context "sent"
  "How near the elements must be to one another.

`sent\\=' or `para\\=', or a NUMBER OF LINES.  These are what the search
engine counts -- `Diogenes::Search\\=' takes `context\\=' as one of the three --
and words are not among them.

THE TLG'S OWN INTERFACE SAYS `within 5 words\\=', and this cannot: a reader
who wants words wants `diorisis-query\\=', which measures them, and measures
distance in syntactic nodes besides."
  :type '(choice (const :tag "The same sentence" "sent")
                 (const :tag "The same paragraph" "para")
                 (integer :tag "Lines"))
  :group 'classicist-query)


;;;; An element

;; AN ELEMENT IS A PLIST, as a Diorisis query element is, and deliberately
;; the same keys where they mean the same thing -- `:kind', `:value',
;; `:negate' -- so that a query built for one corpus can be read by the code
;; that sends it to the other.  What is not shared is `:morph', which here
;; narrows a lemma's forms and there is a column in a database.
;;
;;   :kind    `word', `lemma' or `lemma-morph'
;;   :value   the word, or the lemma
;;   :morph   the features chosen, for `lemma-morph'
;;   :negate  non-nil for an element that must NOT appear
;;   :forms   what the lemma expanded to, kept so that it is expanded once
;;   :lang    "greek" or "latin", the corpus's

(defun classicist-query--read-element (&optional lang)
  "Ask for one element of a query.  LANG is the corpus's language.

FOUR KINDS, AND THE FOURTH IS MORE THAN THE TLG OFFERS: a word that must not
appear is `reject_pattern\\=' to the engine, and no web interface for the TLG
has it."
  (let* ((lang (or lang "greek"))
         ;; A LEMMA WANTS A WORD LIST, and only Greek and Latin have one.
         ;; Offering the kind for a corpus that cannot answer it would be a
         ;; question whose answer is an error.
         (lemmata (member lang '("greek" "latin")))
         (kinds (append
                 '(("a word, or a pattern" . word))
                 (when lemmata
                   '(("every form of a lemma" . lemma)
                     ("a lemma, narrowed by morphology" . lemma-morph)
                     ;; AND BY HAND, which is the third way and the one that
                     ;; can say what the other two cannot: a dialect form, an
                     ;; elision, this aorist and not that one.
                     ("a lemma, picking the forms by hand" . lemma-pick)))
                 '(("a word that must NOT appear" . reject))))
         (kind (cdr (assoc (completing-read "Element: " kinds nil t) kinds))))
    (pcase kind
      ((or 'word 'reject)
       (list :kind 'word
             :value (read-string (if (eq kind 'reject)
                                     "A word that must not appear: "
                                   "The word, or a pattern: "))
             :negate (eq kind 'reject)
             :lang lang))
      ('lemma
       (classicist-query--lemma-element lang nil))
      ('lemma-morph
       (classicist-query--lemma-element lang t))
      ;; NIL, AND THE ELEMENT ARRIVES LATER.  The forms buffer is
      ;; callback-driven -- a reader ticks boxes and presses a key, which may
      ;; be a minute later -- so this kind cannot answer here.  It opens the
      ;; buffer and `classicist-query-add' adds nothing; the callback adds
      ;; the element and redraws when the forms come back.
      ('lemma-pick
       (classicist-query--pick-forms lang)
       nil))))

(defun classicist-query--lemma-element (lang narrow)
  "An element for a lemma in LANG, its forms NARROWed by morphology when set."
  (let* ((lemma (if (fboundp 'diogenes-read-lemma)
                    (diogenes-read-lemma lang)
                  (read-string (format "%s lemma: " (capitalize lang)))))
         (entries (classicist-query--entries lemma lang))
         (morph (and narrow (classicist-query-read-morphology)))
         (forms (classicist-query--forms entries morph)))
    (unless forms
      (user-error "No forms of %s%s" lemma
                  (if morph (format " with %s" morph) "")))
    (classicist-query--warn-if-many forms lemma)
    (list :kind (if narrow 'lemma-morph 'lemma)
          :value lemma
          :morph morph
          :forms forms
          :lang lang)))


;;;; Choosing the morphology

;; WHAT CAN GO WITH WHAT, and nothing more.  A participle has no person, an
;; infinitive has neither person nor case, a finite verb has no case, and a
;; noun has no tense, mood or voice.  Offering all nine categories always
;; would ask a reader to know that; offering only the ones that can apply
;; tells them.
;;
;; A CAGE WOULD BE WORSE THAN A LIST, though.  A reader may want the plurals
;; of a word whether participle or finite, and a hierarchy that made them
;; choose a mood first to reach `number' would be answering a question they
;; did not ask.  So nothing is required: every category is optional, the
;; choices narrow what remains, and `plural' alone is a perfectly good
;; morphology.
;;
;; AND `MOOD' IS WHERE THE BRANCH IS.  In this tagset the participle and the
;; infinitive ARE moods -- position 5 holds `ind subj opt imperat inf part' --
;; so `is it a participle, an infinitive or a finite form' is not a question
;; before the mood but the mood question itself.  Which is why choosing
;; `part' is what makes `case' available and takes `person' away.
;;
;; THE NAMES ARE MORPHEUS', not the Diorisis database's.  This filters the
;; analyses the word list carries, and those are Morpheus' strings -- `aor
;; part act masc nom sg'.  An earlier version of this read the features with
;; `diorisis-read-morphology', whose vocabulary is the database's columns and
;; whose values would have matched nothing here.

(defconst classicist-query--categories
  '((pos     "part of speech"
             ("noun" "verb" "adjective" "adverb" "article" "particle"
              "conjunction" "preposition" "pronoun" "numeral"
              "interjection" "punctuation"))
    (mood    "mood, or participle or infinitive"
             ("ind" "subj" "opt" "imperat" "inf" "part"))
    (tense   "tense"
             ("pres" "imperf" "fut" "aor" "perf" "plup" "futperf"))
    (voice   "voice" ("act" "mid" "pass" "mp"))
    (person  "person" ("1st" "2nd" "3rd"))
    (number  "number" ("sg" "pl" "dual"))
    (gender  "gender" ("masc" "fem" "neut"))
    (kase    "case" ("nom" "gen" "dat" "acc" "voc" "loc"))
    (degree  "degree" ("comp" "superl")))
  "The categories, what to call each, and its values.

`kase\=' AND NOT `case\=', which is a special form in Emacs Lisp and would
read oddly in a `pcase\=' beside it.  The name is internal; a reader sees
`case\='.")

(defun classicist-query--categories-open (chosen)
  "Which categories may still be chosen, given CHOSEN.

CHOSEN is an alist of category and value.  What comes back is the categories
that can APPLY -- and a category already answered is offered again, so that a
reader may change their mind without starting over."
  (let* ((pos (cdr (assq 'pos chosen)))
         (mood (cdr (assq 'mood chosen)))
         (nominal (member pos '("noun" "adjective" "pronoun" "article"
                                "numeral")))
         (verbal (equal pos "verb"))
         ;; A PARTICIPLE IS AN ADJECTIVE WITH A TENSE, and an infinitive a
         ;; noun with one: that is what having a case, or not, comes to.
         (participle (equal mood "part"))
         (infinitive (equal mood "inf"))
         (finite (member mood '("ind" "subj" "opt" "imperat")))
         (uninflected (member pos '("adverb" "particle" "conjunction"
                                    "preposition" "interjection"
                                    "punctuation"))))
    (seq-filter
     (lambda (entry)
       (pcase (car entry)
         ('pos t)
         ;; NOTHING ELSE APPLIES TO AN UNINFLECTED WORD, which is what makes
         ;; it uninflected.
         ((guard uninflected) nil)
         ('mood (or verbal (not pos)))
         ('tense (or verbal (not pos)))
         ('voice (or verbal (not pos)))
         ;; PERSON IS THE FINITE VERB\='S ALONE.  A participle and an
         ;; infinitive have none, which is the whole of why they are not
         ;; finite.
         ('person (and (or verbal (not pos))
                       (not participle) (not infinitive)))
         ;; NUMBER IS ALMOST EVERYWHERE: a finite verb, a participle, a noun.
         ;; An infinitive has none.
         ('number (not infinitive))
         ;; GENDER AND CASE GO TOGETHER and belong to what declines: a noun,
         ;; an adjective, a participle.  Not a finite verb and not an
         ;; infinitive.
         ('gender (and (not finite) (not infinitive)
                       (or nominal participle (not pos))))
         ('kase (and (not finite) (not infinitive)
                     (or nominal participle (not pos))))
         ;; DEGREE IS THE ADJECTIVE\='S, and the adverb\='s -- which is
         ;; uninflected above and so never reaches here, the word list
         ;; recording a comparative adverb under its adjective.
         ('degree (or (equal pos "adjective") (not pos)))
         (_ t)))
     classicist-query--categories)))

(defun classicist-query--ask-one (category)
  "Ask CATEGORY\='s value, or nil for `any\='."
  (let* ((entry (assq category classicist-query--categories))
         (value (completing-read (format "%s (any if it does not matter): "
                                        (nth 1 entry))
                                 (append (nth 2 entry) '("any"))
                                 nil t)))
    (unless (equal value "any") value)))

(defun classicist-query-read-morphology (&optional _prompt)
  "Read a morphology, and return it as a string.

THE BRANCHES ARE ASKED IN ORDER AND THE REST IS A MENU.  Part of speech
first, then -- for a verb -- whether it is finite, a participle or an
infinitive, those two being what decide what else can apply.  Only after
them does a list appear, and by then it holds the categories that CAN apply
and no others.

Which is the difference between a hierarchy and a heap: the first thing a
reader was shown used to be all nine categories at once, and choosing among
them is the very knowledge the hierarchy exists to spare them.

`any\=' AT EITHER BRANCH LEAVES IT OPEN, so a reader who wants the plurals
of a word and does not care whether participle or finite answers `any\='
twice and then `number: pl\='.  Nothing is ever required.

WHAT COMES BACK is the values joined by commas, in no particular order:
`classicist-query--forms\=' compares them as a set."
  (let* ((chosen nil)
         ;; THE FIRST BRANCH.  Everything else in the tagset hangs on it: a
         ;; noun has no tense, a verb no case unless it is a participle.
         (pos (classicist-query--ask-one 'pos)))
    (when pos (push (cons 'pos pos) chosen))
    ;; THE SECOND, AND ONLY WHERE IT MEANS ANYTHING.  `mood\=' is where the
    ;; participle and the infinitive live in this tagset, so for a verb --
    ;; or for a part of speech left open -- it is asked next and decides
    ;; whether `person\=' or `case\=' follows.
    (when (or (null pos) (equal pos "verb"))
      (let ((mood (classicist-query--ask-one 'mood)))
        (when mood (push (cons 'mood mood) chosen))))
    ;; AND THEN WHAT IS LEFT, as a menu rather than a march: a reader who
    ;; wants only the plural should not answer `any\=' to six questions to
    ;; reach `number\='.
    (let ((done nil))
      (while (not done)
        (let* ((open (seq-remove
                      (lambda (entry) (memq (car entry) '(pos mood)))
                      (classicist-query--categories-open chosen)))
               (labels
                (append
                 (mapcar
                  (lambda (entry)
                    (let ((already (cdr (assq (car entry) chosen))))
                      (cons (format "%-24s %s" (nth 1 entry)
                                    (if already (format "[%s]" already) ""))
                            (car entry))))
                  open)
                 '(("done" . done))
                 (when chosen '(("start again" . reset))))))
          (if (null open)
              (setq done t)
            (let ((said (cdr (assoc
                              (completing-read
                               (if chosen
                                   (format "%s.  Narrow further: "
                                           (classicist-query--morph-said
                                            chosen))
                                 "Narrow by: ")
                               labels nil t)
                              labels))))
              (pcase said
                ('done (setq done t))
                ('reset (setq chosen nil)
                        (setq done t))
                (category
                 (let ((value (classicist-query--ask-one category)))
                   (setq chosen (assq-delete-all category chosen))
                   (when value
                     (push (cons category value) chosen))))))))))
    (and chosen (classicist-query--morph-string chosen))))

(defun classicist-query--morph-string (chosen)
  "CHOSEN as the comma-separated string the filter reads."
  (string-join (mapcar #'cdr (reverse chosen)) ","))

(defun classicist-query--morph-said (chosen)
  "CHOSEN in words, for the prompt."
  (string-join
   (mapcar (lambda (pair)
             (format "%s %s"
                     (nth 1 (assq (car pair) classicist-query--categories))
                     (cdr pair)))
           (reverse chosen))
   ", "))

;;;; Expanding a lemma, and narrowing it

(defun classicist-query--entries (lemma lang)
  "The word-list entries for LEMMA in LANG, asking where there are several.

HOMOGRAPHS ARE SEVERAL ENTRIES.  `diogenes--get-all-forms\\=' answers a list
of them -- `(LEMMA RAW-LEMMA LEMMA-NR . ANALYSES)\\=' apiece -- because a
written lemma may be two words, and the forms of the two are not the same.

ALL OF THEM BY DEFAULT.  A reader searching for a lemma usually means the
word rather than one numbered sense, and the alternative -- being asked to
choose between `mu/w 1\\=' and `mu/w 2\\=' before seeing a hit -- asks them to
settle a question the search would have answered."
  (let* ((beta (if (fboundp 'diogenes--utf8-to-beta)
                   (diogenes--utf8-to-beta lemma)
                 lemma))
         ;; THE ERROR IS REPORTED AND NOT SWALLOWED.  This wrapped both
         ;; attempts in `ignore-errors' and said "No lemma X in the greek
         ;; word list" for every failure -- including the one that matters,
         ;; which is the word list not being FOUND: `diogenes--get-all-forms'
         ;; raises where `diogenes--perseus-path' has nothing under it, and a
         ;; reader was told their lemma was missing from a file that was not
         ;; there.  So the first attempt keeps its error, and only the
         ;; SECOND -- the same lookup with the lemma unconverted, a guess at
         ;; what the list may hold -- is allowed to fail quietly.
         (entries (condition-case first
                      (diogenes--get-all-forms beta lang)
                    (error
                     (or (ignore-errors
                           (diogenes--get-all-forms lemma lang))
                         (signal (car first) (cdr first)))))))
    (unless entries
      (user-error
       (concat "No lemma %s in the %s word list."
               "  The list is Perseus' and lives under"
               " diogenes--perseus-path")
       lemma lang))
    entries))

(defun classicist-query--analyses (entries)
  "Every (FORM . PARSES) in ENTRIES, the homographs run together."
  (apply #'append (mapcar #'cdddr entries)))

(defun classicist-query--forms (entries &optional morph)
  "The forms in ENTRIES, narrowed to those matching MORPH.

MORPH IS A COMMA-SEPARATED STRING of features, as
`diorisis-read-morphology\\=' returns: `part,aor\\=' and `aor,part\\=' are one
question, the features being asked for one at a time and joined afterwards.
A form matches when EVERY feature appears in ONE of its parses -- not spread
across two, which would let a present participle answer for an aorist
indicative because the word has both.

NO MORPH IS EVERY FORM, which is what `every form of a lemma' means."
  (let* ((wanted (and morph (not (string-empty-p morph))
                      (split-string morph "[, ]+" t)))
         (out nil))
    (dolist (analysis (classicist-query--analyses entries))
      (let ((form (car analysis))
            (parses (cdr analysis)))
        (when (or (null wanted)
                  (seq-some (lambda (parse)
                              (classicist-query--parse-matches parse wanted))
                            parses))
          (push form out))))
    (seq-uniq (nreverse out))))

(defun classicist-query--parse-matches (parse wanted)
  "Whether PARSE has every feature in WANTED.

A PARSE IS A STRING of features as Morpheus writes them -- `aor part act
masc nom sg\\=' -- so a feature is matched as a WHOLE WORD in it.  As a
substring it would not do: `part\\=' is in `particle\\=' and means nothing like
it, which is the trap the Diorisis prompt spells out for the same two
values."
  (let ((text (if (listp parse) (string-join parse " ") (format "%s" parse))))
    (seq-every-p (lambda (feature)
                   (string-match-p
                    (concat "\\_<" (regexp-quote feature) "\\_>") text))
                 wanted)))

(defun classicist-query--warn-if-many (forms lemma)
  "Say how many FORMS LEMMA expanded to, and ask where that is a great many."
  (let ((n (length forms)))
    (if (and classicist-query-form-warning
             (> n classicist-query-form-warning))
        (unless (y-or-n-p
                 (format "%s expands to %d forms, which may be slow.  Go on? "
                         lemma n))
          (user-error "Left at %d forms" n))
      (message "%s: %d form%s" lemma n (if (= n 1) "" "s")))))


;;;; What an element becomes

(defun classicist-query-element-pattern (element)
  "ELEMENT as one pattern for `Diogenes::Search\\='.

AN ALTERNATION, AND IT IS A REGEXP.  `Search.pm\\=' interpolates each entry
of `pattern_list\\=' straight into `$result =~ /$_/\\=' -- no `\\\\Q\\=' -- so
`(alpha|beta)\\=' is a legal pattern and a lemma's forms can be one element.
Checked in the module rather than assumed: the whole of this rests on it.

BETA CODE, because that is what the corpus holds.  A form read from the word
list is already beta; a word typed by a reader may be Greek and is
converted."
  (let ((forms (plist-get element :forms)))
    (if forms
        (concat "\\("
                (mapconcat #'regexp-quote
                           (mapcar #'classicist-query--as-beta forms)
                           "\\|")
                "\\)")
      (classicist-query--as-beta (plist-get element :value)))))

(defun classicist-query--as-beta (word)
  "WORD in beta code, converted from Greek if it is not already."
  (if (and (fboundp 'diogenes--utf8-to-beta)
           (string-match-p "[^[:ascii:]]" (or word "")))
      (diogenes--utf8-to-beta word)
    (or word "")))

(defun classicist-query-element-describe (element)
  "ELEMENT in a line, for the query buffer."
  (let ((kind (plist-get element :kind))
        (value (plist-get element :value))
        (forms (plist-get element :forms))
        (morph (plist-get element :morph)))
    (concat (if (plist-get element :negate) "NOT " "")
            (pcase kind
              ('word (format "the word %s" value))
              ('lemma (format "any form of %s" value))
              ('lemma-morph (format "%s as %s" value (or morph "?")))
              ('lemma-pick (format "%s, forms picked by hand" value))
              (_ (format "%s" value)))
            (when forms
              (format "  (%d form%s)" (length forms)
                      (if (= (length forms) 1) "" "s"))))))

;;;; The query buffer

;; THE DIORISIS BUFFER'S SHAPE, deliberately.  `diorisis--render-query' lists
;; the elements numbered, puts the index on each line as a text property so
;; that `d' knows which one point is on, and prints the keys at the foot.
;; This does the same with the same keys, because a reader who has built one
;; query should not have to learn a second set for the other corpus.

(defvar-local classicist-query--elements nil
  "The elements of the query this buffer is composing.")

(defvar-local classicist-query--corpus "tlg"
  "The corpus being asked: a Diogenes type, `tlg\=' or `phi\='.")

(defvar-keymap classicist-query-mode-map
  :doc "Keys in the query buffer."
  "a"       #'classicist-query-add
  "d"       #'classicist-query-delete
  "k"       #'classicist-query-clear
  "n"       #'classicist-query-set-context
  "RET"     #'classicist-query-run
  "D"       #'classicist-query-to-diorisis
  "S"       #'classicist-query-save
  "l"       #'classicist-query-open
  "q"       #'quit-window
  "C-c a"   #'classicist-query-add
  "C-c C-d" #'classicist-query-delete
  "C-c C-k" #'classicist-query-clear
  "C-c C-n" #'classicist-query-set-context
  "C-c RET" #'classicist-query-run
  ;; AND A WAY OUT THAT EVERY STATE LEAVES ALONE.  `q' is `quit-window' and
  ;; is right, and in evil's NORMAL state `q' records a macro instead -- which
  ;; is why `classicist-query-mode' is in `diogenes-evil-emacs-state-modes'.
  ;; A reader whose configuration does not use that list should still be able
  ;; to leave: evil binds no `C-c' of its own.
  "C-c C-q" #'quit-window
  "C-c C-s" #'classicist-query-save
  "C-c C-l" #'classicist-query-open
  "f"       #'classicist-query-show-forms
  "C-c C-f" #'classicist-query-show-forms)

(define-derived-mode classicist-query-mode special-mode "Classicist Query"
  "A query of several elements, composed a line at a time.")

(defcustom classicist-query-corpora
  '(("the TLG -- Greek literature" . "tlg")
    ("the PHI -- Latin literature" . "phi")
    ("the documentary papyri" . "ddp")
    ("the classical inscriptions" . "ins")
    ("the Christian inscriptions" . "chr")
    ("the Coptic texts" . "cop")
    ("the miscellaneous PHI texts" . "misc"))
  "The corpora a query may be asked of, as (WHAT IT IS . DIOGENES TYPE).

EVERY CORPUS DIOGENES HAS, and not the TLG alone: the word-index search and
the pattern search are the same for all of them, and `\='tlg\=' was a
DEFAULT that this asked nobody about.

A LEMMA WANTS A WORD LIST, though, and only Greek and Latin have one -- so a
lemma element is offered for the TLG and the PHI, and the others take words
and patterns.  See `classicist-query--language\='."
  :type '(alist :key-type string :value-type string)
  :group 'classicist-query)

;;;###autoload
(defun classicist-query (&optional corpus)
  "Compose a query of several elements over CORPUS.

ASKED AND NOT ASSUMED.  This took the TLG unless called with an argument,
which is right for a reader of Greek and wrong for everyone else -- and the
machinery is the same for every corpus Diogenes has."
  (interactive
   (list (cdr (assoc (completing-read "Search which corpus? "
                                      classicist-query-corpora nil t)
                     classicist-query-corpora))))
  (let ((buffer (get-buffer-create "*A query*")))
    (with-current-buffer buffer
      (classicist-query-mode)
      (setq classicist-query--corpus (or corpus "tlg"))
      (unless classicist-query--elements
        (setq classicist-query--elements nil))
      (classicist-query--render))
    (classicist-query--show buffer)))

(defun classicist-query--show (buffer)
  "Show BUFFER where the suite says a buffer of ours should go.

NOT `pop-to-buffer\=', which made a window or a frame of its own even from a
startup screen -- and a startup page is the one buffer that should always
give up its window, there being nothing in it to keep.
`classicist-display-buffer\=' knows that, and answers to
`classicist-window-behaviour\=' and to a preset besides.

Falls back where the windows feature is asleep, in which case Emacs decides
as it would for any other buffer."
  (if (fboundp 'classicist-display-buffer)
      (classicist-display-buffer buffer :kind 'search)
    (pop-to-buffer buffer)))

(defun classicist-query--language ()
  "The language of the corpus this buffer is asking."
  (if (fboundp 'diogenes--probable-corpus-language)
      (diogenes--probable-corpus-language classicist-query--corpus)
    "greek"))

(defun classicist-query--render ()
  "Print the query this buffer is composing."
  (let ((inhibit-read-only t)
        (elements classicist-query--elements))
    (erase-buffer)
    (insert (propertize (format "A query over the %s\n\n"
                                (upcase classicist-query--corpus))
                        'face 'bold))
    (if (null elements)
        (insert "  (nothing yet)\n")
      (let ((index 0))
        (dolist (element elements)
          (setq index (1+ index))
          (let ((start (point)))
            (insert (format "  %d. %s\n" index
                            (classicist-query-element-describe element)))
            (put-text-property start (point)
                              'classicist-query-element index)))))
    (insert "\n")
    (insert (propertize
             (format "  all of them within %s\n\n"
                     (classicist-query--context-said))
             'face 'font-lock-comment-face))
    ;; DIORISIS IS GREEK, so the hand-over is offered for a Greek corpus and
    ;; for no other.  It was offered always, and offering it under the PHI
    ;; invited a reader to take a Latin query to a corpus that holds no
    ;; Latin.
    ;;
    ;; AND IT IS WORTH OFFERING FOR GREEK whatever the query: the Diorisis
    ;; corpus answers what this one cannot -- a morphology needing no lemma
    ;; to hang on, and distance counted in syntactic nodes -- at the price of
    ;; ten million words against a hundred.
    (let ((greek (equal (classicist-query--language) "greek")))
      (insert (propertize
               (concat "a adds an element, d deletes the one at point, "
                       "f shows its forms\n"
                       "n says how near they must be\n"
                       "RET searches"
                       (if greek
                           ", D takes it to the Diorisis corpus\n"
                         "\n")
                       "S saves, l loads a saved one, q quits\n"
                       "each is also under C-c, which evil leaves alone:\n"
                       "C-c a, C-c C-d, C-c C-n, C-c RET, C-c C-q\n")
               'face 'shadow)))
    (goto-char (point-min))))

(defun classicist-query--context-said ()
  "How near the elements must be, in words."
  (pcase classicist-query-context
    ("sent" "one sentence")
    ("para" "one paragraph")
    ((and (pred numberp) n) (format "%d line%s" n (if (= n 1) "" "s")))
    (other (format "%s" other))))


;;;; Building it

(defun classicist-query--pick-forms (lang)
  "Open the forms buffer for a lemma of LANG, and add what comes back.

THE BUFFER IS THE BASE\='S and so is the picking; what this adds is where the
answer goes.  A reader may also narrow by morphology FIRST and pick from
what is left, which is the two routes used together and the shortest way to
a precise element: choose `aor part\=', then untick the epic forms."
  (let* ((lemma (if (fboundp 'diogenes-read-lemma)
                    (diogenes-read-lemma lang)
                  (read-string (format "%s lemma: " (capitalize lang)))))
         (buffer (current-buffer)))
    (unless (fboundp 'diogenes--select-forms)
      (user-error "The base\='s forms buffer is not loaded"))
    (diogenes--select-forms
     lemma lang
     (lambda (forms)
       (if (not forms)
           (message "No forms picked, so nothing was added")
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (setq classicist-query--elements
                   (append classicist-query--elements
                           (list (list :kind 'lemma-pick
                                       :value lemma
                                       :forms forms
                                       :lang lang))))
             (classicist-query--render))
           ;; SHOWN AGAIN, the forms buffer having taken the window: a
           ;; reader who has finished picking wants the query back.
           (classicist-query--show buffer))))
     (format "Pick the forms of %s to search for:" lemma))))

(defun classicist-query-add ()
  "Add an element to the query.

SOME ELEMENTS ARRIVE LATER.  The forms buffer answers by callback, so
`classicist-query--read-element\=' gives nil for that kind and the element is
appended when the reader has finished ticking.  Hence the `when\=': appending
nil would put an empty line in the query."
  (interactive)
  ;; THE QUERY BUFFER IS HELD, and every change made inside it.  This drew
  ;; into `current-buffer' -- and picking forms by hand leaves
  ;; `*diogenes-select-forms*' current, so the render ERASED THE FORMS BUFFER
  ;; and drew the query where the forms had been.  A reader asked to pick
  ;; forms was shown the query instead, in a buffer named for the forms.
  ;;
  ;; AND NOTHING IS DRAWN FOR AN ELEMENT THAT HAS NOT ARRIVED: the forms
  ;; buffer answers by callback and redraws for itself when it does.
  (let* ((buffer (current-buffer))
         (element (classicist-query--read-element
                   (classicist-query--language))))
    (when (and element (buffer-live-p buffer))
      (with-current-buffer buffer
        (setq classicist-query--elements
              (append classicist-query--elements (list element)))
        (classicist-query--render)))))

(defun classicist-query-delete ()
  "Delete the element at point."
  (interactive)
  (let ((index (get-text-property (point) 'classicist-query-element)))
    (unless index (user-error "No element here"))
    (setq classicist-query--elements
          (append (seq-take classicist-query--elements (1- index))
                  (seq-drop classicist-query--elements index)))
    (classicist-query--render)))

(defun classicist-query-show-forms ()
  "List the forms the element at point expanded to.

BECAUSE A COUNT IS NOT AN ANSWER.  An element says `447 forms\=' and a reader
building a query of four has no way to see what the second of them will
actually look for -- and a lemma picked wrongly, or a feature that narrowed
to something unintended, is invisible until the search comes back strange.

THE PATTERN IS SHOWN TOO, which is what the engine is given: a reader who
knows a regexp can see precisely what will be matched, and a reader who does
not can ignore the last line."
  (interactive)
  (let* ((index (get-text-property (point) 'classicist-query-element))
         (element (and index (nth (1- index) classicist-query--elements))))
    (unless element (user-error "No element here"))
    (let ((forms (plist-get element :forms))
          (buffer (get-buffer-create "*This element*")))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (propertize
                   (format "%s\n\n"
                           (classicist-query-element-describe element))
                   'face 'bold))
          (if (not forms)
              (insert "  A word or a pattern, expanded from nothing.\n")
            (insert (format "  %d form%s:\n\n" (length forms)
                            (if (= (length forms) 1) "" "s")))
            (dolist (form forms)
              (insert (format "    %s%s\n" form
                              ;; THE GREEK BESIDE THE BETA, where the
                              ;; converter is to hand: the list is beta and a
                              ;; reader reads Greek.
                              (if (fboundp 'diogenes--beta-to-utf8)
                                  (format "    %s"
                                          (ignore-errors
                                            (diogenes--beta-to-utf8 form)))
                                "")))))
          (insert (propertize
                   (format "\n  as one pattern:\n    %s\n"
                           (classicist-query-element-pattern element))
                   'face 'font-lock-comment-face))
          (goto-char (point-min))
          (special-mode)))
      (classicist-query--show buffer))))

(defun classicist-query-clear ()
  "Take every element off the query."
  (interactive)
  (setq classicist-query--elements nil)
  (classicist-query--render))

(defun classicist-query-set-context ()
  "Say how near the elements must be to one another.
Drawn in the query buffer and not in whatever is current, for the reason
`classicist-query-add\=' records."
  (interactive)
  (let* ((choices (append '(("the same sentence" . "sent")
                            ("the same paragraph" . "para"))
                          (cl-loop for i from 1 upto 20
                                   collect (cons (format "%d lines" i) i))))
         (said (completing-read "Within: " choices nil t)))
    (setq classicist-query-context (cdr (assoc said choices))))
  (classicist-query--render))


;;;; Running it

(defun classicist-query--options ()
  "The query as a plist for `Diogenes::Search\='.

`pattern_list\=' AND `reject_pattern\=', which is what the engine has:
every positive element is one pattern and all of them must appear, within
`context\='; a negative element is the rejection, of which the engine takes
ONE -- so several are joined into one alternation, `\(a\|b\)\=', which
rejects a passage containing either.

`min_matches\=' IS LEFT ALONE.  `Base.pm\=' sets it to the length of the
list where it is unset, which is every pattern -- the `and\=' a reader
means.  Setting it lower would give `at least n of these\=', which is more
than the TLG\='s own interface offers and is worth its own key rather than a
silent default."
  (let* ((positive (seq-remove (lambda (e) (plist-get e :negate))
                               classicist-query--elements))
         (negative (seq-filter (lambda (e) (plist-get e :negate))
                               classicist-query--elements))
         (patterns (mapcar #'classicist-query-element-pattern positive))
         (rejects (mapcar #'classicist-query-element-pattern negative)))
    (append (list :type classicist-query--corpus)
            (when patterns (list :pattern-list patterns))
            (when rejects
              (list :reject-pattern
                    (if (cdr rejects)
                        (concat "\\(" (string-join rejects "\\|") "\\)")
                      (car rejects))))
            (list :context classicist-query-context))))

(defun classicist-query-run ()
  "Search for this query.

ONE ELEMENT GOES BY THE WORD INDEX, which is the fast path: the TLG is
indexed by form, and `diogenes--do-wordlist-search\=' reads the index rather
than the corpus.  It takes the forms themselves and no regexp.

SEVERAL ELEMENTS GO BY THE PATTERN LIST, which reads the corpus.  There is
no help for it: the index answers `where does this form occur\=', not `where
do these two occur near one another\='."
  (interactive)
  (unless classicist-query--elements
    (user-error "Nothing in the query yet: press a"))
  (let* ((elements classicist-query--elements)
         (single (and (null (cdr elements))
                      (not (plist-get (car elements) :negate))
                      (plist-get (car elements) :forms)))
         (corpus classicist-query--corpus))
    (cond
     ;; THE INDEX, for one element that is a list of forms.
     ((and single (equal corpus "tlg")
           (fboundp 'diogenes--do-wordlist-search))
      (classicist-query--with-authors
       corpus
       (lambda (authors)
         (diogenes--do-wordlist-search (list :type corpus) single authors))))
     ((fboundp 'diogenes--do-search)
      (let ((options (classicist-query--options)))
        (classicist-query--with-authors
         corpus
         (lambda (authors) (diogenes--do-search options authors)))))
     (t (user-error "The base\='s search is not loaded")))))

(defun classicist-query--with-authors (corpus then)
  "Call THEN with a sub-corpus of CORPUS, or nil for the whole of it.

THE WHOLE CORPUS IS A QUESTION AND NOT A DEFAULT.  A query of several
elements reads the corpus rather than an index, and the whole TLG is a
hundred million words: a reader who meant three authors should not wait for
all of them because nothing asked."
  (if (y-or-n-p (format "Search the whole %s? " (upcase corpus)))
      (funcall then nil)
    (if (fboundp 'diogenes--search-select-authors)
        (diogenes--search-select-authors
         corpus nil
         (lambda (chosen)
           (funcall then (list :author-nums (plist-get chosen :authors)))))
      (funcall then nil))))

(defun classicist-query-to-diorisis ()
  "Take this query to the Diorisis corpus.

WHICH ANSWERS WHAT THIS CORPUS CANNOT: every token there carries its lemma
and its parse, so a morphology needs no lemma to hang on -- and distance can
be counted in syntactic nodes and not only in lines.

TEN MILLION WORDS AGAINST A HUNDRED, which is the trade and is worth saying
before a reader wonders why the hits are fewer."
  (interactive)
  (unless (fboundp 'diorisis-query)
    (user-error "The Diorisis feature is not loaded"))
  ;; GREEK ONLY, AND SAID RATHER THAN HIDDEN.  The footer offers this for a
  ;; Greek corpus alone, but a reader may press `D' anyway -- from muscle
  ;; memory, or under the PHI where the line is absent -- and an answer is
  ;; better than nothing happening.
  (unless (equal (classicist-query--language) "greek")
    (user-error
     (concat "The Diorisis corpus is Greek: there is nothing there"
             " for a %s query")
     (upcase classicist-query--corpus)))
  (message "%s" (concat "Diorisis: ten million words, every one parsed"
                        " -- against the TLG\='s hundred million"))
  (call-interactively 'diorisis-query))

;;;; Saving one

;; THE SAME DIRECTORY AND THE SAME FORMAT AS DIORISIS', deliberately.  Its
;; own `diorisis-query-file' docstring says why: a query of elements and a
;; plain search "are both searches and were kept apart for no better reason
;; than that they were written at different times; a reader who saved one and
;; looked for it among the other was right to be annoyed."  A THIRD place
;; would be the same mistake again.
;;
;; SO THE SPEC CARRIES `:corpus', and each opener declines what is not its
;; own: `diorisis-open-search' hands a TLG query here, and this hands a
;; Diorisis query there.  Without that key a TLG query would open in the
;; Diorisis builder, whose describer would render its elements as something
;; they are not.
;;
;; WHAT IS SAVED IS THE QUESTION AND NOT THE ANSWER, as there: the elements,
;; not the hits.  A query opened next year asks the corpus again, and a set
;; of hits kept as hits would be citations going quietly out of date.  Here
;; there is a second reason: a lemma's forms come from the word list, which a
;; reader may rebuild, so the forms are saved as a convenience and re-expanded
;; where the lemma is still known.

(defun classicist-query--spec ()
  "This buffer\='s query, as a spec to save."
  (unless classicist-query--elements
    (user-error "Nothing in the query to save"))
  (list :corpus classicist-query--corpus
        :context classicist-query-context
        :elements classicist-query--elements))

(defun classicist-query--said (spec)
  "SPEC in a line, for the list of saved searches."
  (let ((elements (plist-get spec :elements)))
    (string-join (mapcar #'classicist-query-element-describe elements)
                 ", ")))

(defun classicist-query-save (name)
  "Save this query under NAME, among the saved searches."
  (interactive (list (read-string "Save this query as: ")))
  (unless (fboundp 'diorisis--saved-file)
    (user-error "The Diorisis feature holds the saved searches"))
  (let ((spec (classicist-query--spec)))
    (make-directory diorisis-saved-directory t)
    (with-temp-file (diorisis--saved-file name)
      (let ((print-length nil) (print-level nil))
        (prin1 (list :name name
                     :saved (format-time-string "%F %R")
                     :said (classicist-query--said spec)
                     :spec spec)
               (current-buffer))))
    (message "Saved as %s" name)))

;;;###autoload
(defun classicist-query-open (&optional spec)
  "Open a query saved before, or SPEC where one is given.

ONLY THE ONES THAT ARE THIS CORPUS\='S are offered: a spec with no `:corpus\='
is Diorisis\=' and belongs to `diorisis-open-search\='."
  (interactive)
  (if spec
      (classicist-query--from-spec spec)
    (unless (fboundp 'diorisis--saved-searches)
      (user-error "The Diorisis feature holds the saved searches"))
    (let* ((mine (seq-filter
                  (lambda (one)
                    (plist-get (plist-get one :spec) :corpus))
                  (diorisis--saved-searches)))
           (labels (mapcar (lambda (one)
                             (cons (format "%-24s %s   %s"
                                           (or (plist-get one :name) "?")
                                           (or (plist-get one :saved) "")
                                           (or (plist-get one :said) ""))
                                   one))
                           mine)))
      (unless labels
        (user-error "No queries saved in %s" diorisis-saved-directory))
      (classicist-query--from-spec
       (plist-get (cdr (assoc (completing-read "Open which query? "
                                               labels nil t)
                              labels))
                  :spec)))))

(defun classicist-query--from-spec (spec)
  "Put SPEC into a query buffer."
  (let ((buffer (get-buffer-create "*A query*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'classicist-query-mode)
        (classicist-query-mode))
      (setq classicist-query--corpus (or (plist-get spec :corpus) "tlg"))
      (setq classicist-query--elements (plist-get spec :elements))
      (when (plist-get spec :context)
        (setq classicist-query-context (plist-get spec :context)))
      (classicist-query--render))
    (classicist-query--show buffer)))

;;;; In Diogenes\' menu

(defcustom classicist-query-add-to-diogenes-menu t
  "Whether to put the query builder in Diogenes\=' menu.

INSIDE `sg\=' AND `sl\=', and not beside them.  Those two do not run a
search: they open `diogenes--search--select-mode\=', a menu of the WAYS of
searching the corpus they carry in their scope -- Simple, Lemma, Advanced,
Wordlist.  A query of several elements is another way of searching the same
corpus, so it belongs there as `q\=', under whichever corpus a reader has
already chosen.

WHICH ALSO MEANS NO PROMPT.  The corpus is `(diogenes--tr--type)\=', the
scope of the menu the reader is standing in.  Being asked again which corpus
to search, having just pressed `sg\=', would be the builder not listening.

Nil leaves the menu alone."
  :type 'boolean
  :group 'classicist-query)

;;;###autoload
(defun classicist-query-here ()
  "Build a query over the corpus of the menu this was called from.

FOR `diogenes--search--select-mode\=', whose scope holds the corpus: `sg\='
sets it to the TLG and `sl\=' to the PHI, so this asks nothing."
  (interactive)
  (classicist-query
   (or (ignore-errors (diogenes--tr--type)) "tlg")))

(defun classicist-query--add-to-diogenes-menu ()
  "Put `q\=' in Diogenes\=' search-mode menu.

AFTER `a\=', which is Advanced: a query of elements is what a reader reaches
for when Advanced is not enough, so it reads as the next step along.

IDEMPOTENT: `run-hooks\=' may call this twice and two appends give two
identical lines."
  (when (and classicist-query-add-to-diogenes-menu
             (fboundp 'transient-append-suffix))
    (ignore-errors
      (unless (ignore-errors
                (transient-get-suffix 'diogenes--search--select-mode "q"))
        (transient-append-suffix 'diogenes--search--select-mode "a"
          '("q" "Query of several elements" classicist-query-here))))))

;; AFTER THE BASE\='S SEARCH FILE, whose menu is being added to -- and not
;; after `diogenes\=', which defines the outer menu and not this one.
;;
;; THE FORM ASKS NOTHING OF THIS FILE: it names `classicist-query-here\=',
;; which is autoloaded and so nameable before the file is in memory, and the
;; appending is written out rather than called.  Which is what `make check\='
;; requires of a cookie on a form rather than a definition, and what this
;; suite has now learnt three times.
;;;###autoload
(with-eval-after-load 'diogenes-search
  (when (fboundp 'transient-append-suffix)
    (ignore-errors
      (unless (ignore-errors
                (transient-get-suffix 'diogenes--search--select-mode "q"))
        (transient-append-suffix 'diogenes--search--select-mode "a"
          '("q" "Query of several elements" classicist-query-here))))))

(provide 'classicist-query)

;;; classicist-query.el ends here
