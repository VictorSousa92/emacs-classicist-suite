;;; diogenes-roam-index.el --- An index of the notes on a work -*- lexical-binding: t -*-

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; URL: https://github.com/VictorSousa92/diogenes-roam
;; Keywords: classics, philology, org, roam
;; Version: 0.1
;; Package-Requires: ((emacs "28.1") (org "9.6") (org-roam "2.2.2"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; ONE PLACE TO SEE EVERY NOTE ON A TEXT, in the order of the text.
;;
;; `diogenes-org-notes' answers `what have I said about the lines in front of
;; me', which is the question a reader has while reading.  This answers the
;; other one -- `what have I said about this dialogue' -- which is the
;; question one has on sitting down to write, and which a list of citations
;; answers better than a search does.
;;
;; The index is an org-roam node like any other, and so must keep its ID
;; across a regeneration: a rewritten file would lose it, and with it every
;; link made to the index.  So only a dynamic block is rewritten.  The header,
;; the ID, and anything written by hand outside the block are left alone --
;; which leaves room to write about the work above the list.
;;
;; It opens beside the browser in a side window.  Side windows are not counted
;; by `delete-other-windows', so closing the index leaves the browser filling
;; the frame with nothing to tidy away.
;;
;; Requires the org-integration branch of diogenes.el: see the README.

;;; Code:

(require 'org)
(require 'seq)
(require 'cl-lib)
(require 'diogenes-roam)

;; OPTIONAL.  Without diogenes-books the index is one flat list, which is what
;; it was before books were known of.
(require 'diogenes-books nil t)
(require 'diogenes-org)           ; --passage-parts, --same-work-p, --levels
(require 'diogenes-books)         ; diogenes-books-declared, --known

;; ORG-ROAM IS OPTIONAL and these are its own.  The sibling file declares
;; org-roam-directory too; a declaration is per file.
(defvar org-roam-directory)

(declare-function diogenes-org--where "diogenes-org" (path))
(declare-function diogenes-org--work-name "diogenes-org" (corpus author work))
(declare-function diogenes-org--ref-at-point "diogenes-org" ())
(declare-function diogenes-org--page-span "diogenes-org" ())
(declare-function classicist-browser-reference "classicist-citation" ())
(declare-function org-roam-db-query "org-roam-db" (sql &rest args))
(declare-function org-roam-db-update-file "org-roam-db" (&optional file-path))
(declare-function diogenes-books--load "diogenes-books" ())
(declare-function diogenes-books--greek-letter "diogenes-books" (title))



;;;; Options

(defgroup diogenes-roam-index nil
  "An index of the notes on a work."
  :group 'diogenes-roam
  :prefix "diogenes-roam-index-")

(defcustom diogenes-roam-index-name "index.org"
  "What the index of a work is called, inside the work's directory."
  :type 'string)

(defcustom diogenes-roam-index-snippet-width 88
  "How much of a note's first line to show beside its citation.
Nil for none."
  :type '(choice integer (const nil)))

(defcustom diogenes-roam-index-by-book t
  "Whether to divide the index into the books of the work.

Only where the books are already to hand: declared in
`diogenes-books-declared', or found once and remembered by `diogenes-books'.
Finding them means reading the whole work, and an index is rebuilt every time
a note is saved, so the index never asks for them -- a work whose books are
unknown gets one flat list, as before.

Run `diogenes-open-book' on a work once and its index divides from then on."
  :type 'boolean)

(defcustom diogenes-roam-index-side 'right
  "Which edge of the frame the index sits on, beside the browser."
  :type '(choice (const right) (const left) (const top) (const bottom)))

(defcustom diogenes-roam-index-size 0.35
  "How much of the frame the index takes.
A fraction of the width for `right' and `left', of the height otherwise.
An integer is taken as columns or lines instead."
  :type 'number)

(defcustom diogenes-roam-index-sidebar t
  "Whether the index opens beside the browser rather than in an ordinary
window."
  :type 'boolean)

(defcustom diogenes-roam-index-select t
  "Whether opening the index puts the cursor in it.
Non-nil to follow a link straight away; nil to keep reading and glance over."
  :type 'boolean)

(defcustom diogenes-roam-index-open-in 'default
  "Where a note opens when followed from the index.

`default' leaves it to `pop-up-frames', so a reader who has set that for
Diogenes' sake gets the same behaviour here.  `window' and `frame' force one
or the other.

Never in the index's own window, whichever this is."
  :type '(choice (const default) (const window) (const frame)))


;;;; What is there

(defun diogenes-roam-index--rows (corpus author work)
  "Notes on CORPUS:AUTHOR:WORK as (PATH ID TITLE FILE PARTS).
In the order of the text.

`diogenes-org--refs' gives what roam knows but not the file a note is in,
which the snippets want, so the query is made again here -- the same query,
with one more column."
  (unless (require 'org-roam nil t)
    (user-error "This wants org-roam"))
  (let ((want (list corpus author work))
        rows)
    (dolist (row (org-roam-db-query
                  [:select [refs:ref nodes:id nodes:title nodes:file]
                   :from refs
                   :join nodes :on (= refs:node-id nodes:id)]))
      (when-let* ((ref (nth 0 row))
                  (p (ignore-errors (diogenes-org--passage-parts ref))))
        (when (diogenes-org--same-work-p p want)
          (push (list ref (nth 1 row) (nth 2 row) (nth 3 row) p) rows))))
    (sort rows (lambda (a b)
                 (diogenes-roam-index--citation<
                  (nth 3 (nth 4 a)) (nth 3 (nth 4 b)))))))

(defun diogenes-roam-index--normalise (cite)
  "CITE with a lone column letter joined to the page before it.

THE CORPORA ARE NOT OF ONE MIND.  Aristotle\='s lines are printed `1046a.3\=',
the Bekker page and its column as a single level; Plato\='s are `327.a.5\=', the
Stephanus column being a level of its own.  And `diogenes-books-declared\='
writes `327a\=', which is the form `diogenes-open-passage\=' wants.

`diogenes-org--levels\=' reckons `1046a\=' as one number and a bare `a\=' as
nothing, so `327.a.5\=' comes out (327 0 5) against the declared (3270) and
every note in the Republic falls before its first book.  Joined, the three
forms agree."
  (replace-regexp-in-string "\\.\\([a-e]\\)\\(\\'\\|\\.\\)" "\\1\\2"
                            (or cite "")))

(defun diogenes-roam-index--citation< (a b)
  "Whether citation A comes strictly before citation B.

`diogenes-org--before-p' answers at-or-before, which is what covering a
passage wants and what sorting does not: a predicate that calls equals true
leaves the order undefined.  So: the same arithmetic made strict, with the
shorter citation first where one is a prefix of the other -- and both sides
put through `diogenes-roam-index--normalise' first, the corpora and the
declarations not writing a citation the same way."
  (let ((x (diogenes-org--levels (diogenes-roam-index--normalise a)))
        (y (diogenes-org--levels (diogenes-roam-index--normalise b))))
    (catch 'done
      (cl-loop for i in x
               for j in y
               do (cond ((< i j) (throw 'done t))
                        ((> i j) (throw 'done nil))))
      (< (length x) (length y)))))

(defun diogenes-roam-index--snippet (file)
  "The first line of prose in FILE, cut to the configured width."
  (when (and diogenes-roam-index-snippet-width file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      ;; Past the drawer, the keywords and the blank lines: property lines and
      ;; the drawer's ends all begin with a colon, keywords with a hash.
      (while (and (not (eobp))
                  (looking-at "^\\(:.*\\|#\\+.*\\|[ \t]*\\)$"))
        (forward-line 1))
      (unless (eobp)
        (let ((line (string-trim
                     (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position))))
              (w diogenes-roam-index-snippet-width))
          (unless (string-empty-p line)
            (if (> (length line) w) (concat (substring line 0 w) "…") line)))))))


;;;; The block

(defun diogenes-roam-index--books (corpus author work)
  "The books of CORPUS:AUTHOR:WORK, as (TITLE CITATION), or nil.

WHAT IS ALREADY TO HAND, and nothing more.  `diogenes-books--find' will read
a whole work to find its books, which is seconds of Perl; an index is rebuilt
every time a note is saved and cannot spend that.  So: declared outright, or
found once and remembered, or nothing."
  (when (and diogenes-roam-index-by-book
             (boundp 'diogenes-books-declared))
    (let ((key (list corpus author work)))
      (or (cdr (assoc key diogenes-books-declared))
          (progn (when (fboundp 'diogenes-books--load) (diogenes-books--load))
                 (and (boundp 'diogenes-books--known)
                      (cdr (assoc key diogenes-books--known))))))))

(defun diogenes-roam-index--book-of (cite books)
  "The book of BOOKS that CITE falls in, as (TITLE CITATION N), or nil.

The last book beginning at or before CITE.  BOOKS are in the order the work
prints them, so the last that qualifies is the one the passage is in."
  (let ((n 0) found)
    (dolist (book books)
      (setq n (1+ n))
      (unless (diogenes-roam-index--citation< cite (cadr book))
        (setq found (list (nth 0 book) (nth 1 book) n))))
    found))

(defun diogenes-roam-index--group (rows books)
  "ROWS as ((BOOK . ROWS) ...), in the order of the text.
BOOK is nil for anything falling before the first book begins."
  (let (groups)
    (dolist (row rows)
      (let* ((book (diogenes-roam-index--book-of (nth 3 (nth 4 row)) books))
             (cell (assoc book groups)))
        (if cell
            (setcdr cell (cons row (cdr cell)))
          (push (cons book (list row)) groups))))
    (mapcar (lambda (cell) (cons (car cell) (nreverse (cdr cell))))
            (nreverse groups))))

(defun diogenes-roam-index--book-label (book)
  "BOOK as the index heads its notes.

THE LETTER AND THE NUMBER BOTH.  `diogenes-books' is at pains to say that
they differ -- Theta is the ninth book of the Metaphysics and the eighth
letter, Alpha Minor having none of its own -- so a reader is shown both rather
than left to count."
  (if (null book)
      "*Before the first book*"
    (let ((letter (and (fboundp 'diogenes-books--greek-letter)
                       (diogenes-books--greek-letter (nth 0 book)))))
      (format "*%s*%s /book %d, from %s/"
              (nth 0 book)
              (if letter (format " (%c)" letter) "")
              (nth 2 book)
              (nth 1 book)))))

(defun diogenes-roam-index--entry (row &optional indent)
  "ROW as a list item, INDENT spaces in."
  (format "%s- [[id:%s][%s]]%s\n"
          (make-string (or indent 0) ?\s)
          (nth 1 row)
          (diogenes-org--where (nth 0 row))
          (if-let* ((s (diogenes-roam-index--snippet (nth 3 row))))
              (concat " — " s) "")))

(defun org-dblock-write:dio-index (params)
  "Write the list of notes for the work named in PARAMS.

Each note is offered by its passage -- `diogenes-org--where' gives the
citation alone, the corpus and the author and the work being the same down
the whole list -- and then by its first line, which is what tells one note on
1048a27 from another.

DIVIDED INTO BOOKS where the books are known: a nested list and not headings,
a dynamic block being a greater element that cannot hold a headline."
  (let* ((corpus (plist-get params :corpus))
         (author (plist-get params :author))
         (work   (plist-get params :work))
         (rows   (diogenes-roam-index--rows corpus author work))
         (books  (diogenes-roam-index--books corpus author work)))
    (cond
     ((null rows)
      (insert "No notes on this work yet.\n"))
     (books
      (dolist (group (diogenes-roam-index--group rows books))
        (insert (format "- %s\n" (diogenes-roam-index--book-label (car group))))
        (dolist (row (cdr group))
          (insert (diogenes-roam-index--entry row 2)))))
     (t
      (dolist (row rows) (insert (diogenes-roam-index--entry row)))))
    (insert (format "\n/%d note%s%s · %s/\n"
                    (length rows)
                    (if (= 1 (length rows)) "" "s")
                    (if books
                        (format " in %d book%s" (length books)
                                (if (= 1 (length books)) "" "s"))
                      "")
                    (format-time-string "%Y-%m-%d %H:%M")))))


;;;; The file

;; `diogenes-roam-author-dir' and `-work-dir' read the passage in hand.  An
;; index is built for a work named outright, so the override is bound.

(defun diogenes-roam-index--author-dir (corpus author)
  (let ((diogenes-roam--parts-override (list corpus author nil)))
    (diogenes-roam-author-dir)))

(defun diogenes-roam-index--work-dir (corpus author work)
  (let ((diogenes-roam--parts-override (list corpus author work)))
    (diogenes-roam-work-dir)))

(defun diogenes-roam-index--path (corpus author work)
  "Where the index of CORPUS:AUTHOR:WORK lives.
Alongside the notes themselves, so the work's directory is whole."
  (expand-file-name
   (if diogenes-roam-subdirectory
       (format "%s/%s/%s/%s" diogenes-roam-subdirectory
               (diogenes-roam-index--author-dir corpus author)
               (diogenes-roam-index--work-dir corpus author work)
               diogenes-roam-index-name)
     (format "%s/%s/%s"
             (diogenes-roam-index--author-dir corpus author)
             (diogenes-roam-index--work-dir corpus author work)
             diogenes-roam-index-name))
   org-roam-directory))

(defun diogenes-roam-index--header (corpus author work)
  "The part of the file that is never regenerated."
  (let ((wname (diogenes-roam--tidy
                (or (ignore-errors
                      (diogenes-org--work-name corpus author work))
                    (format "work %s" work))))
        (adir (diogenes-roam-index--author-dir corpus author)))
    (concat "#+title: " (capitalize adir) ", " wname " — notes\n"
            "#+filetags: :index:" adir ":\n"
            "#+startup: showall\n"
            "\n"
            "The list below is written by `org-dblock-write:dio-index'.\n"
            "Anything outside the block is kept; follow a link to edit a note.\n"
            "\n"
            (format
             "#+BEGIN: dio-index :corpus \"%s\" :author \"%s\" :work \"%s\"\n"
             corpus author work)
            "#+END:\n")))

(defun diogenes-roam-index-ensure (corpus author work)
  "The index file for CORPUS:AUTHOR:WORK, made if it is not there.
Returns the path."
  (let ((path (diogenes-roam-index--path corpus author work)))
    (unless (file-exists-p path)
      (make-directory (file-name-directory path) t)
      (with-temp-file path
        (insert (diogenes-roam-index--header corpus author work)))
      ;; The ID has to be put in by org, and kept: every regeneration after
      ;; this one touches only the block.
      (with-current-buffer (find-file-noselect path)
        (let ((inhibit-read-only t))
          (goto-char (point-min))
          (org-id-get-create)
          (save-buffer))
        (when (fboundp 'org-roam-db-update-file)
          (org-roam-db-update-file path))))
    path))

;;;###autoload
(defun diogenes-roam-index-update (corpus author work)
  "Regenerate the index of CORPUS:AUTHOR:WORK and save it.
Returns the path."
  (let ((path (diogenes-roam-index-ensure corpus author work)))
    (with-current-buffer (find-file-noselect path)
      (let ((inhibit-read-only t))
        (org-update-all-dblocks)
        (save-buffer)))
    path))


;;;; The buffer

(defvar diogenes-roam-index-mode-map
  (let ((map (make-sparse-keymap)))
    ;; RET must be taken from org, which would open the note in this very
    ;; window -- and in Doom from `+org/dwim-at-point', which is also there.
    (define-key map (kbd "RET") #'diogenes-roam-index-open-at-point)
    (define-key map (kbd "q")   #'diogenes-roam-index-close)
    (define-key map (kbd "g")   #'diogenes-roam-index-refresh)
    (define-key map (kbd "M-n") #'diogenes-roam-index-next)
    (define-key map (kbd "M-p") #'diogenes-roam-index-previous)
    map)
  "Keys in an index buffer.")

;;;###autoload
(define-minor-mode diogenes-roam-index-mode
  "Minor mode for a generated index of passage notes."
  :lighter " Index"
  :keymap diogenes-roam-index-mode-map)


(defun diogenes-roam-index-buffer-p (&optional buffer)
  "Whether BUFFER is an index of passage notes."
  (let ((file (buffer-file-name (or buffer (current-buffer)))))
    (and file
         (string-match-p
          (concat "\\`" (regexp-quote (expand-file-name org-roam-directory))
                  ".*" (regexp-quote diogenes-roam-index-name) "\\'")
          (expand-file-name file)))))

(defun diogenes-roam-index--setup ()
  "Make an index buffer read-only, and give it its keys."
  (when (diogenes-roam-index-buffer-p)
    (read-only-mode 1)
    (diogenes-roam-index-mode 1)))


;;;; The sidebar

(defun diogenes-roam-index--display-action ()
  "How to put an index buffer on the screen.
DEDICATED, so that `display-buffer' will not reuse the sidebar for anything
else -- a note followed from the index, most of all."
  `(display-buffer-in-side-window
    (side . ,diogenes-roam-index-side)
    (slot . 0)
    (window-width . ,diogenes-roam-index-size)
    (window-height . ,diogenes-roam-index-size)
    (dedicated . t)
    (window-parameters . ((no-delete-other-windows . t)))))

(defun diogenes-roam-index--show (path)
  "Put PATH's buffer in the sidebar, or in a window of its own.
Returns the window."
  (let ((buffer (find-file-noselect path)))
    (with-current-buffer buffer (diogenes-roam-index--setup))
    (if diogenes-roam-index-sidebar
        ;; A side window is wanted, not a frame, whatever `pop-up-frames'
        ;; says for the rest of the session.
        (let* ((pop-up-frames nil)
               (window (display-buffer
                        buffer (diogenes-roam-index--display-action))))
          (when (and window diogenes-roam-index-select)
            (select-window window))
          window)
      (pop-to-buffer buffer))))

(defun diogenes-roam-index--windows ()
  "Every window showing an index of passage notes."
  (seq-filter (lambda (w) (diogenes-roam-index-buffer-p (window-buffer w)))
              (window-list nil 'never)))

;;;###autoload
(defun diogenes-roam-index-close ()
  "Shut the index, leaving the browser alone in the frame."
  (interactive)
  (let ((windows (diogenes-roam-index--windows)))
    (if (null windows)
        (message "No index open")
      (dolist (w windows)
        (cond ((window-parameter w 'window-side) (delete-window w))
              ((one-window-p t) (bury-buffer (window-buffer w)))
              (t (delete-window w)))))))

;;;###autoload
(defun diogenes-roam-index-open-at-point ()
  "Follow the link at point, anywhere but in the index's own window.

Org opens an `id:' link with whatever `org-link-frame-setup' names for
`file', and that is `find-file' -- which takes over the window it is called
from.  Called from a sidebar, that is the sidebar, and the index is replaced
by the note.  So the entry is shadowed for the length of the call:
`find-file-other-window' honours `pop-up-frames', and so gives a frame where
the rest of the session would have one and a window where it would not."
  (interactive)
  (let* ((pop-up-frames (pcase diogenes-roam-index-open-in
                          ('window nil)
                          ('frame  t)
                          (_ pop-up-frames)))
         (org-link-frame-setup
          (cons '(file . find-file-other-window) org-link-frame-setup)))
    (org-open-at-point)))

;;;###autoload
(defun diogenes-roam-index-refresh ()
  "Regenerate the index being looked at."
  (interactive)
  (if-let* ((p (diogenes-roam-index--here)))
      (progn (apply #'diogenes-roam-index-update p)
             (let ((inhibit-read-only t)) (revert-buffer t t t))
             (diogenes-roam-index--setup)
             (message "Index rebuilt"))
    (user-error "No passage reference here")))


;;;; Getting to it

(defun diogenes-roam-index--here ()
  "(CORPUS AUTHOR WORK) for wherever point is, or nil.

`diogenes-roam--parts' answers in a browser and in a note.  An index has no
ref of its own, so the block's own arguments are read instead."
  (or (diogenes-roam--parts)
      (when (diogenes-roam-index-buffer-p)
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward
                 (concat "^#\\+BEGIN: +dio-index +"
                         ":corpus +\"\\([^\"]+\\)\" +"
                         ":author +\"\\([^\"]+\\)\" +"
                         ":work +\"\\([^\"]+\\)\"")
                 nil t)
            (list (match-string 1) (match-string 2) (match-string 3)))))))

;;;###autoload
(defun diogenes-roam-index-visit ()
  "Open the index of the work in view, regenerated."
  (interactive)
  (if-let* ((p (diogenes-roam-index--here)))
      (diogenes-roam-index--show (apply #'diogenes-roam-index-update p))
    (user-error "No passage here: run this from a browser or a passage note")))

;;;###autoload
(defun diogenes-roam-index-toggle ()
  "Open the index beside the browser, or shut it if it is open."
  (interactive)
  (if (diogenes-roam-index--windows)
      (diogenes-roam-index-close)
    (diogenes-roam-index-visit)))

;;;###autoload
(defun diogenes-roam-index-rebuild-all ()
  "An index for every work there are notes on."
  (interactive)
  (unless (require 'org-roam nil t) (user-error "This wants org-roam"))
  (let (seen)
    (dolist (row (org-roam-db-query [:select refs:ref :from refs]))
      (when-let* ((p (ignore-errors
                      (diogenes-org--passage-parts (car row)))))
        (cl-pushnew (list (nth 0 p) (nth 1 p) (nth 2 p)) seen :test #'equal)))
    (dolist (p seen)
      (ignore-errors (apply #'diogenes-roam-index-update p)))
    (message "%d index%s" (length seen) (if (= 1 (length seen)) "" "es"))))


;;;; Walking the notes

;; THE ORDER OF THE TEXT, and not the order they were written in.  A reader
;; going through what they have said about a dialogue wants to meet the notes
;; as the dialogue meets them, and `diogenes-roam-index--rows' is sorted that
;; way already.

(defun diogenes-roam-index--id-at-point ()
  "The `id:' link at point, or nil.
In an index, that names the note the line is about."
  (when (derived-mode-p 'org-mode)
    (let ((ctx (org-element-context)))
      (when (and (memq (org-element-type ctx) '(link))
                 (equal (org-element-property :type ctx) "id"))
        (org-element-property :path ctx)))))

(defun diogenes-roam-index--own-id ()
  "The ID of the node point is in, or nil."
  (when (derived-mode-p 'org-mode)
    (or (org-entry-get nil "ID" t)
        (save-excursion (goto-char (point-min)) (org-entry-get nil "ID")))))

(defun diogenes-roam-index--citation-here ()
  "The citation point is at in a browser, as a string, or nil.

`classicist-browser-reference' has no `:key' on the very first line of a
freshly opened browser -- see `diogenes-roam--parts' -- so the page's own
extent is asked for instead, which searches forward."
  (when (derived-mode-p 'diogenes-browser-mode)
    (or (plist-get (ignore-errors (classicist-browser-reference)) :key)
        (when-let* ((span (ignore-errors (diogenes-org--page-span)))
                    (p (ignore-errors
                         (diogenes-org--passage-parts (car span)))))
          (nth 3 p)))))

(defun diogenes-roam-index--position (rows)
  "Where among ROWS point is: an index, or (before . CITATION), or nil.

An integer where point is ON a note -- in the index, or in the note itself.
A cons where point is in a browser, holding the citation of the line in view,
which is between notes rather than at one."
  (let ((id (or (diogenes-roam-index--id-at-point)
                (unless (diogenes-roam-index-buffer-p)
                  (diogenes-roam-index--own-id)))))
    (or (and id (seq-position rows id
                              (lambda (row key) (equal (nth 1 row) key))))
        (when-let* ((cite (diogenes-roam-index--citation-here)))
          (cons 'before cite)))))

(defun diogenes-roam-index--step (rows position n)
  "The row N on from POSITION among ROWS, or nil at the ends."
  (pcase position
    ((and (pred integerp) i)
     (let ((j (+ i n)))
       (and (>= j 0) (< j (length rows)) (nth j rows))))
    (`(before . ,cite)
     ;; Between notes: the first after, or the last before.
     (if (> n 0)
         (seq-find (lambda (row)
                     (diogenes-roam-index--citation< cite (nth 3 (nth 4 row))))
                   rows)
       (car (last (seq-filter
                   (lambda (row)
                     (diogenes-roam-index--citation< (nth 3 (nth 4 row)) cite))
                   rows)))))
    (_ (if (> n 0) (car rows) (car (last rows))))))

(defun diogenes-roam-index--goto-row (row)
  "Open ROW's note, and put the sidebar's point on its line."
  (dolist (w (diogenes-roam-index--windows))
    (with-current-buffer (window-buffer w)
      (save-excursion
        (goto-char (point-min))
        (when (search-forward (concat "[[id:" (nth 1 row) "]") nil t)
          (set-window-point w (line-beginning-position))))))
  (let* ((pop-up-frames (pcase diogenes-roam-index-open-in
                          ('window nil)
                          ('frame  t)
                          (_ pop-up-frames)))
         (buffer (find-file-noselect (nth 3 row))))
    (if (diogenes-roam-index-buffer-p)
        ;; Never in the index's own window.
        (pop-to-buffer buffer)
      (pop-to-buffer-same-window buffer))
    (message "%s" (diogenes-org--where (nth 0 row)))))

;;;###autoload
(defun diogenes-roam-index-next (&optional n)
  "Open the next note on this work, in the order of the text.
With a numeric prefix N, that many on; negative to go back.

Works from a browser, from a note, and from the index."
  (interactive "p")
  (let* ((parts (or (diogenes-roam--parts)
                    (and (diogenes-roam-index-buffer-p)
                         (diogenes-roam-index--here))
                    (user-error "No work here")))
         (rows (apply #'diogenes-roam-index--rows parts)))
    (unless rows (user-error "No notes on this work"))
    (let* ((position (diogenes-roam-index--position rows))
           (row (diogenes-roam-index--step rows position (or n 1))))
      (if row
          (diogenes-roam-index--goto-row row)
        (message "No further notes on this work")))))

;;;###autoload
(defun diogenes-roam-index-previous (&optional n)
  "Open the previous note on this work, in the order of the text."
  (interactive "p")
  (diogenes-roam-index-next (- (or n 1))))


;;;; Keeping up

(defun diogenes-roam-index--refresh-windows ()
  "Re-read any index on screen, its file having been rewritten."
  (dolist (w (diogenes-roam-index--windows))
    (with-current-buffer (window-buffer w)
      (let ((inhibit-read-only t))
        (ignore-errors (revert-buffer t t t)))
      (diogenes-roam-index--setup))))

(defvar diogenes-roam-index--captured nil
  "(CORPUS AUTHOR WORK) of the capture last begun.")

(defun diogenes-roam-index--note-capture (&rest _)
  "Remember which work is being captured into.
`diogenes-roam-dir' runs during every passage capture, which is where the
work can be learnt; by the time the capture is finalised the info is gone."
  (setq diogenes-roam-index--captured (diogenes-roam--parts)))

(defun diogenes-roam-index--after-capture ()
  "Rebuild the index of the work just captured into, and any sidebar."
  (when diogenes-roam-index--captured
    (let ((p diogenes-roam-index--captured))
      (setq diogenes-roam-index--captured nil)
      (ignore-errors (apply #'diogenes-roam-index-update p))
      (diogenes-roam-index--refresh-windows))))

;; A NOTE IS EDITED AS OFTEN AS IT IS WRITTEN, and the index shows each note's
;; first line, so an edit to that line makes the index wrong.  Saving is the
;; moment to put it right.

(defvar diogenes-roam-index--rebuilding nil
  "Bound while an index is being written, to keep it from rebuilding itself.")

(defun diogenes-roam-index--note-parts ()
  "(CORPUS AUTHOR WORK) if this buffer is a passage note, else nil.

STRICTLY FROM THE REF.  An index has no ref of its own and must not be
mistaken for a note, or saving one would rebuild it for ever."
  (unless (diogenes-roam-index-buffer-p)
    (when-let* ((ref (ignore-errors (diogenes-org--ref-at-point)))
                (p (ignore-errors (diogenes-org--passage-parts ref))))
      (list (nth 0 p) (nth 1 p) (nth 2 p)))))

(defun diogenes-roam-index--after-save ()
  "Rebuild the index of the work whose note has just been saved."
  (unless diogenes-roam-index--rebuilding
    (when-let* ((p (and (derived-mode-p 'org-mode)
                       (diogenes-roam-index--note-parts))))
      (let ((diogenes-roam-index--rebuilding t))
        (ignore-errors (apply #'diogenes-roam-index-update p))
        (diogenes-roam-index--refresh-windows)))))

(defun diogenes-roam-index--browser-gone ()
  "Shut a sidebar whose browser has been killed."
  (when (and (derived-mode-p 'diogenes-browser-mode)
             (diogenes-roam-index--windows))
    (ignore-errors (diogenes-roam-index-close))))

(defun diogenes-roam-index--browser-setup ()
  (add-hook 'kill-buffer-hook #'diogenes-roam-index--browser-gone nil t))


;;;; The mode

;;;###autoload
(define-minor-mode diogenes-roam-index-global-mode
  "Keep an index of the notes on each work, and open it beside the browser."
  :global t
  :group 'diogenes-roam-index
  (if diogenes-roam-index-global-mode
      (progn
        (add-hook 'find-file-hook #'diogenes-roam-index--setup)
        (add-hook 'after-save-hook #'diogenes-roam-index--after-save)
        (add-hook 'org-capture-after-finalize-hook
                  #'diogenes-roam-index--after-capture)
        (add-hook 'diogenes-browser-mode-hook
                  #'diogenes-roam-index--browser-setup)
        (advice-add 'diogenes-roam-dir :before
                    #'diogenes-roam-index--note-capture))
    (remove-hook 'find-file-hook #'diogenes-roam-index--setup)
    (remove-hook 'after-save-hook #'diogenes-roam-index--after-save)
    (remove-hook 'org-capture-after-finalize-hook
                 #'diogenes-roam-index--after-capture)
    (remove-hook 'diogenes-browser-mode-hook
                 #'diogenes-roam-index--browser-setup)
    (advice-remove 'diogenes-roam-dir
                   #'diogenes-roam-index--note-capture)))

(provide 'diogenes-roam-index)

;;; diogenes-roam-index.el ends here
