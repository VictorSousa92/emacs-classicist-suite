;;; classicist-groups.el --- the suite's customize groups -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor2971@gmail.com>
;; Keywords: classics, philology

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

;; TWELVE LINES AND A FILE OF ITS OWN, because the suite's modules do not
;; require one another.  Nothing ties `classicist-windows.el\\=' to
;; `classicist-citation.el\\='; so whichever held the root group, the other
;; would name a parent it had not loaded.  Customize copes with that by
;; inventing a placeholder, and a reader loading one module alone finds its
;; options orphaned from the tree.
;;
;; A shared declaration with no other home is what a small file is for.

;;; Code:

(require 'cl-lib)   ; cl-loop, cl-some

(defgroup classicist nil
  "A suite of tools for classicists.
Diogenes\\=' corpora and lexica, the Diorisis corpus, treebank annotation, and
editions as TEI -- see `classicist\\=' for the modules and their options.

BESIDE `diogenes\\=' AND NOT UNDER IT.  The suite loads Diogenes\\=' Perl bridge
and its corpus plumbing, and replaces the rest; an option of the suite\\='s is
not an option of Diogenes\\=', and a reader browsing one should not have to
read the other."
  :group 'tools)

(defcustom classicist-features '(texts lexica)
  "Which of the suite's features are awake.
Everything is loaded; a feature not named here installs no keys, adds no menu
entry and offers nothing.  So a reader who wants the corrections this package
makes and nothing else leaves this alone, and the suite behaves as Diogenes
does.

  `texts\='         browsing and searching Diogenes\=' own corpora
  `lexica\='        the LSJ and Lewis & Short, the parse, every attested form
  `dictionaries\='  the printed ones.  WHICH of them is
                  `classicist-declared-dictionaries\='; without this that list
                  is not consulted at all
  `diorisis\='      searching the Diorisis corpus of lemmatised Greek
  `treebank\='      annotating one of its sentences as a dependency tree
  `tei-corpora\='   CSEL, the Patrologia Latina, Corpus Corporum, and anything
                  else published as TEI XML
  `books\='         a work opened at one of its books, by the letter a
                  classicist uses -- `Theta\=' and not `1045b27'.  The corpora
                  do not know books; the text carries their titles, and this
                  reads them
  `notes\='         the org commands: a note on a passage, and what has been
                  said about the lines in front of you
  `windows\='       the suite placing buffers, rather than leaving that to
                  whatever you have arranged

TEXTS AND LEXICA BY DEFAULT, because that is what Diogenes itself does: a
reader who installs this and reads no further gets a browser and a dictionary,
and nothing they did not ask for.  The four that are new to this suite are
opted into.

AND THE CORPORA ARE NOT ALL DIOGENES\='.  `tei-corpora\=' reads editions from
disk and wants nothing of the CD-ROMs; `diorisis\=' reads its own index, and
will open a hit in its own reader where the browser cannot.  So
`(diorisis tei-corpora)\=', with no Diogenes data at all, is a working
answer.
WHICH WANTS WHICH.  Three of the eight are not free-standing:

  `treebank\='      wants `diorisis\=': it annotates that corpus\='s sentences,
                  requires its file, and puts its keys in its results buffer.
  `dictionaries\='  wants `lexica\=': the printed ones are reached from the
                  banner at the head of an LSJ or Lewis & Short entry.
  `notes\='         wants `texts\=' or `tei-corpora\=': a note is about a
                  passage, and either browser will do.

The other five stand alone.  `diorisis\=' and `tei-corpora\=' in particular
want nothing of Diogenes\=' own data: both read their own, and a hit in the
Diorisis corpus opens in its own reader where the browser cannot.  So
`(diorisis tei-corpora)\=', with no `diogenes-path\=' at all, is a working
answer.
"
  :type '(set (const :tag "Diogenes' corpora" texts)
              (const :tag "The LSJ and Lewis & Short" lexica)
              (const :tag "The printed dictionaries" dictionaries)
              (const :tag "The Diorisis corpus" diorisis)
              (const :tag "Treebank annotation" treebank)
              (const :tag "Editions as TEI" tei-corpora)
              (const :tag "A work at one of its books" books)
              (const :tag "Notes in org" notes)
              (const :tag "Frame, window and buffer managing" windows))
  :group 'classicist)

(defun classicist-feature-p (feature)
  "Whether FEATURE is awake, by `classicist-features\='.
A function rather than a `memq\=' at every site, so that a transient\='s `:if\='
reads as a question and the answer can change without editing eleven places."
  (and (memq feature classicist-features) t))

(defconst classicist-feature-wants
  '((treebank     diorisis)
    (dictionaries lexica)
    (notes        texts tei-corpora))
  "What a feature wants, as (FEATURE . ONE-OF).
A feature is useful when one of the features it wants is also awake -- so
`notes\=' is content with either browser, and `treebank\=' wants the one corpus
it annotates.  The five not named here stand alone.

DATA AND NOT PROSE, so that `classicist-check-features\=' and the
configuration builder answer from the same place.  Derived by reading: the
treebank requires `diorisis.el\=' outright, the printed dictionaries are a
banner on a lexicon entry, and a note is about a passage in some browser.")

(defun classicist-check-features ()
  "Say which awake features want one that is not.
Interactively, say so either way."
  (interactive)
  (let ((missing
         (cl-loop for (feature . wants) in classicist-feature-wants
                  when (and (classicist-feature-p feature)
                            (not (cl-some #'classicist-feature-p wants)))
                  collect (cons feature wants))))
    (cond
     ((null missing)
      (when (called-interactively-p 'interactive)
        (message "Every feature has what it wants"))
      t)
     (t
      (message
       "%s"
       (mapconcat
        (lambda (m)
          (format "`%s' wants %s, and none of those is on"
                  (car m)
                  (mapconcat (lambda (w) (format "`%s'" w)) (cdr m) " or ")))
        missing "; "))
      nil))))

(provide 'classicist-groups)

;;; classicist-groups.el ends here
