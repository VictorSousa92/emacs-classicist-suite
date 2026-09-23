;;; classicist-phi-notes.el --- notes in phi-notes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor2971@gmail.com>
;; Keywords: classics, philology
;; Package-Requires: ((emacs "28.1"))

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

;; AN ALTERNATIVE TO THE ORG NOTES, and not a replacement: the same three
;; things -- a note on the passage in hand, what has been said about these
;; lines, and the way back -- kept in Bruno Conte's `phi-notes' instead of in
;; org.  A reader whose Zettelkasten is already markdown and wikilinks should
;; not have to keep a second one in org to annotate a text.
;;
;; NOTHING IN `phi-notes' IS MODIFIED, and that is the point of how this is
;; written.  It was built with the TLG in mind: `phi-note-types' already has a
;; `tlg-text' type, and `phi-create-common-note' already takes a `:tlg-fields'
;; plist and writes three frontmatter fields from it.  So this file fills those
;; fields and reads them back, and adds nothing to phi-notes' own vocabulary.
;;
;; HIS SPELLING IS KEPT.  The TLG field stays `ref_tlg', so a note this makes
;; is indistinguishable from one phi-notes made itself, and the other five
;; corpora follow the same pattern -- `ref_phi', `ref_ddp' and the rest, by
;; `classicist-phi-ref-fields'.  The field name is settled by LET-BINDING
;; `phi-tlg-ref-field' around the call, because `phi-create-common-note' reads
;; that variable when it writes the header; a sibling note type would not have
;; worked, the header function naming the variable rather than consulting the
;; type.
;;
;; THREE LEVELS INTO TWO FIELDS.  phi-notes gives a citation a `section' and a
;; `line', and a work may have two levels or four -- Aristotle is cited by
;; Bekker page and line, Cicero by actio, book, section and line.  So the last
;; level goes in `line' and everything above it in `section', joined by stops:
;;
;;     Aristotle  (1053a 15)    section 1053a      line 15
;;     Plato      (327a 1 5)    section 327a.1     line 5
;;     Cicero     (2 1 5 10)    section 2.1.5      line 10
;;
;; which is reversible, which is what matters: the way back splits `section' on
;; the stops and appends `line'.
;;
;; NOT TESTED.  Written against the two seams by reading them --
;; `classicist-browser-reference' on this side, `phi-note-types' and
;; `phi-create-common-note' on his -- with no phi-notes installed and no
;; corpora to hand.  The shapes are right; whether a note comes out with the
;; fields in it is the first thing to try.

;;; Code:

(require 'seq)
(require 'subr-x)

;; PHI-NOTES' OWN, DECLARED AND NOT REQUIRED.  This file is loaded when the
;; `phi-notes' feature is awake, which says the reader wants it; phi-notes
;; itself is a package of its own and may be absent, so every entry point
;; checks before it calls.
(declare-function phi-new-note "phi-notes" (&rest args))
(declare-function phi-get-note-field-contents "phi-notes"
                  (field &optional buffer))
(declare-function phi-get-fields "phi-notes" (&optional buffer))
(declare-function phi-mode "phi-notes" (&optional arg))
(defvar phi-tlg-ref-field)
(defvar phi-tlg-section-field)
(defvar phi-tlg-line-field)
(defvar phi-repository-alist)
(defvar phi-note-types)

;; THE SUITE'S OWN.
(declare-function classicist-browser-reference "classicist-citation" ())
(declare-function classicist-citation-to-string "classicist-citation"
                  (citation &optional labels))
(declare-function classicist-reference-to-string "classicist-citation"
                  (reference))
(declare-function classicist-open-passage "classicist-browser"
                  (corpus author work &optional passage))
(declare-function classicist-feature-p "classicist-groups" (feature))


;;;; Options

(defgroup classicist-phi-notes ()
  "Passage notes kept in `phi-notes' rather than in org.

BESIDE THE ORG GROUP AND NOT UNDER IT.  A reader uses one or the other, and
the one they do not use is not a sub-part of the one they do."
  :group 'tools)

(defcustom classicist-phi-ref-fields
  '(("tlg"  . "ref_tlg")
    ("phi"  . "ref_phi")
    ("ddp"  . "ref_ddp")
    ("ins"  . "ref_ins")
    ("chr"  . "ref_chr")
    ("misc" . "ref_misc")
    ("cop"  . "ref_cop"))
  "The frontmatter field naming each corpus, as (CORPUS . FIELD).

`ref_tlg' IS BRUNO CONTE'S OWN and is kept exactly: a note this file makes
about a Greek text has the same field, in the same format, as one phi-notes
made itself, so his own tooling reads it without knowing this exists.  The
other six follow the pattern rather than inventing one.

A corpus not named here gets no reference field, and the commands here say so
rather than writing a note that cannot be followed back."
  :type '(alist :key-type (string :tag "Corpus")
                :value-type (string :tag "Frontmatter field"))
  :group 'classicist-phi-notes)

(defcustom classicist-phi-note-type 'tlg-text
  "The `phi-note-types' entry a passage note is made as.

`tlg-text' FOR EVERY CORPUS, and not a type apiece.  The type decides the
header function, the file extension and the required tag, and those are the
same whatever the text is; only the reference field differs, and that is
settled by `classicist-phi-ref-fields' when the note is written."
  :type 'symbol
  :group 'classicist-phi-notes)

(defcustom classicist-phi-repository nil
  "The phi-notes repository a passage note goes in.
Nil asks, as phi-notes asks.  A string is a repository name in
`phi-repository-alist'; the symbol `current' means the one the current buffer
is in, without asking."
  :type '(choice (const :tag "Ask" nil)
                 (const :tag "The current buffer's" current)
                 (string :tag "Repository name"))
  :group 'classicist-phi-notes)

(defcustom classicist-phi-notes-directories nil
  "Where to look for notes about a passage.
Nil reads the directories out of `phi-repository-alist', which is what a
reader with one Zettelkasten wants.  A list of directories overrides it."
  :type '(choice (const :tag "Every phi-notes repository" nil)
                 (repeat directory))
  :group 'classicist-phi-notes)

(defcustom classicist-phi-keys
  '((classicist-phi-note  . "C-c n n")
    (classicist-phi-notes . "C-c n l"))
  "The keys this file binds in a browser buffer, as (COMMAND . KEY).
Nil for a KEY binds nothing.  Consulted when the keys are installed, so set
it before the browser loads."
  :type '(alist :key-type function
                :value-type (choice key-sequence (const :tag "Unbound" nil)))
  :group 'classicist-phi-notes)


;;;; phi-notes, present or not

(defun classicist-phi--available-p ()
  "Whether phi-notes is here to be used."
  (and (featurep 'phi-notes)
       (fboundp 'phi-new-note)))

(defun classicist-phi--require ()
  "Load phi-notes, or say why the command cannot run."
  (unless (classicist-phi--available-p)
    (unless (require 'phi-notes nil t)
      (user-error
       (concat "phi-notes is not installed."
               "  It is a package of its own:"
               " https://github.com/brunocbr/phi-notes"))))
  t)


;;;; A reference, into phi-notes' three fields and back

(defun classicist-phi--ref-field (corpus)
  "The frontmatter field CORPUS's references go in, or nil."
  (cdr (assoc corpus classicist-phi-ref-fields)))

(defun classicist-phi--level-strings (citation)
  "CITATION with every level as a string.

DIOGENES GIVES NEITHER STRINGS NOR ALL ONE TYPE.  A citation comes back with
some levels as numbers and some as symbols -- `1053a\=' is a symbol, 15 is a
number.  `classicist-citation-from-key\=' says as much of its own output, and
it is true of `classicist-browser-reference\='\='s `:from\=' too.  Passing
that to `string-join\=' reaches `concat\=' with a number in it:

    Wrong type argument: sequencep, 1

and phi-notes would trip on the same thing in `replace-regexp-in-string\='.  So
everything is made a string once, here, rather than guarded at each use."
  (mapcar (lambda (level)
            (if (stringp level) level (format "%s" level)))
          citation))

(defun classicist-phi--fields-from-reference (reference)
  "REFERENCE as the three values phi-notes keeps, or nil.
A plist: `:tlg-ref', `:tlg-section' and `:tlg-line', which are the keys
`phi-create-common-note' reads whatever the corpus -- the FIELD those are
written to is `classicist-phi-ref-fields'' business and is settled by the
caller."
  (let* ((corpus (plist-get reference :corpus))
         (author (plist-get reference :author))
         (work (plist-get reference :work))
         (from (classicist-phi--level-strings
                (plist-get reference :from))))
    (when (and corpus author work)
      (list :tlg-ref (concat author ":" work)
            ;; EVERYTHING ABOVE THE LAST LEVEL, joined by stops, because a
            ;; work may have two levels or four and phi-notes has two fields.
            ;; Reversible, which is the whole requirement.
            :tlg-section (if (cdr from)
                             (string-join (butlast from) ".")
                           "")
            :tlg-line (if from (car (last from)) "")))))

(defun classicist-phi--reference-from-fields (&optional buffer)
  "The passage the note in BUFFER is about, as a plist, or nil.
`:corpus', `:author', `:work' and `:levels' -- enough for
`classicist-open-passage'.  The corpus is whichever of
`classicist-phi-ref-fields'' fields the note actually has, so a note needs no
field saying which corpus it is: the name of the reference field says it."
  (when (classicist-phi--available-p)
    (let* ((buf (or buffer (current-buffer)))
           (found
            (seq-some
             (lambda (cell)
               (let ((value (ignore-errors
                              (phi-get-note-field-contents (cdr cell) buf))))
                 (and value (not (string-empty-p (string-trim value)))
                      (cons (car cell) (string-trim value)))))
             classicist-phi-ref-fields)))
      (when found
        (let* ((parts (split-string (cdr found) ":" t))
               (section (ignore-errors
                          (phi-get-note-field-contents
                           phi-tlg-section-field buf)))
               (line (ignore-errors
                       (phi-get-note-field-contents phi-tlg-line-field buf)))
               (levels (append
                        (and section
                             (split-string (string-trim section) "[.]" t))
                        (and line (not (string-empty-p (string-trim line)))
                             (list (string-trim line))))))
          (when (cdr parts)
            (list :corpus (car found)
                  :author (nth 0 parts)
                  :work (nth 1 parts)
                  :levels levels)))))))


;;;; Making a note

;;;###autoload
(defun classicist-phi-note ()
  "Make a phi-notes note about the passage in this browser buffer.

THE FIELDS ARE FILLED AND NOT PROMPTED FOR: the reference, the section and the
line come from the buffer, which is the point of doing this from a browser
rather than from the note side.  phi-notes asks for the title and the
repository as it always does.

The reference field is named for the corpus -- `ref_tlg' for the TLG, as
phi-notes itself names it -- by let-binding `phi-tlg-ref-field' around the
call: `phi-create-common-note' reads that variable when it writes the header,
so this settles the name without a note type of our own and without touching
phi-notes."
  (interactive)
  (classicist-phi--require)
  (let ((reference (and (fboundp 'classicist-browser-reference)
                        (classicist-browser-reference))))
    (unless reference
      (user-error "Not in a Diogenes browser -- there is no passage to note"))
    (let* ((corpus (plist-get reference :corpus))
           (field (classicist-phi--ref-field corpus))
           (fields (classicist-phi--fields-from-reference reference)))
      (unless field
        (user-error
         (concat "No reference field for the `%s' corpus"
                 " -- see classicist-phi-ref-fields")
         corpus))
      (unless fields
        (user-error "This browser does not record which work it is showing"))
      (let ((phi-tlg-ref-field field))
        (apply #'phi-new-note
               (append
                (list :type classicist-phi-note-type
                      :tlg-fields fields)
                (when classicist-phi-repository
                  (list :repository classicist-phi-repository))
                ;; A TITLE OFFERED AND NOT IMPOSED: the citation as a reader
                ;; writes it, which is what the note is about, and phi-notes
                ;; lets them edit it.
                (when (fboundp 'classicist-reference-to-string)
                  (list :title
                        (classicist-reference-to-string reference)))))))))


;;;; What has been said about these lines

(defun classicist-phi--note-directories ()
  "The directories to look for notes in."
  (or classicist-phi-notes-directories
      (and (boundp 'phi-repository-alist)
           (seq-filter #'file-directory-p
                       (mapcar #'cadr phi-repository-alist)))))

(defun classicist-phi--frontmatter (file)
  "The frontmatter of FILE as an alist of (FIELD . VALUE), read as text.

READ WITHOUT phi-notes, deliberately.  Asking `phi-get-fields' would want each
file visited in a buffer with `phi-mode' on, which for a Zettelkasten of some
thousands of notes is a great deal of work to answer one question.  The
frontmatter is `field:\\tvalue' lines before the first blank one, and reading
it as text is enough to say whether a note is about this passage."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)
    (goto-char (point-min))
    (let ((fields nil))
      (while (and (not (eobp))
                  (not (looking-at-p "^[ \t]*$")))
        (when (looking-at
               "^\\([A-Za-z_][A-Za-z0-9_]*\\):[ \t]*\\(.*?\\)[ \t]*$")
          (push (cons (match-string 1) (match-string 2)) fields))
        (forward-line 1))
      (nreverse fields))))

(defun classicist-phi--notes-on (corpus author work)
  "Notes about WORK of AUTHOR in CORPUS, as (FILE SECTION LINE TITLE)."
  (let ((field (classicist-phi--ref-field corpus))
        (ref (concat author ":" work))
        (out nil))
    (when field
      (dolist (dir (classicist-phi--note-directories))
        (dolist (file (directory-files-recursively
                       dir "\\.\\(md\\|markdown\\)\\'"))
          (let* ((fm (ignore-errors (classicist-phi--frontmatter file)))
                 (this (cdr (assoc field fm))))
            (when (and this (equal (string-trim this) ref))
              (push (list file
                          (or (cdr (assoc "section" fm)) "")
                          (or (cdr (assoc "line" fm)) "")
                          (or (cdr (assoc "title" fm))
                              (file-name-base file)))
                    out))))))
    (nreverse out)))

;;;###autoload
(defun classicist-phi-notes ()
  "List the phi-notes notes about the work in this browser buffer.

BY THE WORK AND NOT BY THE LINE, because a note on the lines in front of you
is rarer than a note somewhere in the same work, and the second is what a
reader actually wants to see.  The section and line of each are shown, so the
ones about this passage are visible among them."
  (interactive)
  (classicist-phi--require)
  (let ((reference (and (fboundp 'classicist-browser-reference)
                        (classicist-browser-reference))))
    (unless reference
      (user-error "Not in a Diogenes browser"))
    (let* ((corpus (plist-get reference :corpus))
           (author (plist-get reference :author))
           (work (plist-get reference :work))
           (notes (classicist-phi--notes-on corpus author work)))
      (if (null notes)
          (message "No phi-notes notes on %s"
                   (if (fboundp 'classicist-reference-to-string)
                       (classicist-reference-to-string reference)
                     (concat author ":" work)))
        (let* ((rows (mapcar
                      (lambda (n)
                        (cons (format "%-12s %-6s %s"
                                      (nth 1 n) (nth 2 n) (nth 3 n))
                              (car n)))
                      notes))
               (pick (completing-read
                      (format "Notes on this work (%d): " (length rows))
                      rows nil t)))
          (find-file (cdr (assoc pick rows))))))))


;;;; The way back

;;;###autoload
(defun classicist-phi-goto-passage ()
  "Open the passage the phi-notes note in this buffer is about.
The corpus is whichever reference field the note has, so nothing in the note
need say which corpus it is."
  (interactive)
  (classicist-phi--require)
  (let ((reference (classicist-phi--reference-from-fields)))
    (unless reference
      (user-error
       "This note has no passage reference -- no %s field in its frontmatter"
       (string-join (mapcar #'cdr classicist-phi-ref-fields) ", ")))
    (classicist-open-passage (plist-get reference :corpus)
                             (plist-get reference :author)
                             (plist-get reference :work)
                             (plist-get reference :levels))))


;;;; Keys

;;;###autoload
(defun classicist-phi-install-keys ()
  "Bind `classicist-phi-keys' in the browser.
Interactive, and asks `boundp' first, so that a reader who turns the feature
on mid-session need not restart -- as `classicist-browser-install-mouse-keys'
is and does, for the same reasons."
  (interactive)
  (when (boundp 'classicist-browser-mode-map)
    (dolist (cell classicist-phi-keys)
      (when (cdr cell)
        (keymap-set (symbol-value 'classicist-browser-mode-map)
                    (cdr cell) (car cell))))))

;; INSTALLED WHEN THE BROWSER LOADS, and only when the feature is awake.  The
;; cookie copies this into the generated autoloads, where it runs before this
;; file is loaded -- so it must ask nothing of this file beyond a name, and
;; `classicist-phi-install-keys' is autoloaded and therefore nameable.
;;;###autoload
(with-eval-after-load 'classicist-browser
  (when (and (fboundp 'classicist-feature-p)
             (classicist-feature-p 'phi-notes))
    (classicist-phi-install-keys)))

(provide 'classicist-phi-notes)

;;; classicist-phi-notes.el ends here
