;;; diogenes-roam.el --- Passage notes by author and work -*- lexical-binding: t -*-

;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; Keywords: classics, philology, org, roam
;; Version: 0.1
;; Package-Requires: ((emacs "28.1") (org "9.6") (org-roam "2.2.2"))
;; URL: https://github.com/VictorSousa92/diogenes-roam

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

;; A NOTE ON A PASSAGE BELONGS WITH THE OTHER NOTES ON THAT TEXT.  Diogenes
;; and org-roam together will keep notes anchored to citations, which is the
;; hard part and is `diogenes-org's; what is left is where the files go, and
;; org-roam is indifferent to that by design.  A flat directory of three
;; hundred notes named for timestamps is a poor thing to look at in dired.
;;
;; So: notes filed by author and then by work --
;;
;;     ref/aristotle/metaphysica/arist-metaph-1048a27.org
;;     ref/plato/respublica/plat-rep-327a5.org
;;
;; and tagged to match, `:passage:aristotle:metaphysica:', so that the same
;; grouping is reachable from completion where it is wanted and from the
;; filesystem where that is easier.
;;
;; THE CORPORA NAME AN AUTHOR AT LENGTH.  Author 0086 of the TLG is
;; `Aristoteles Phil. et Corpus Aristotelicum, Aristotle (0086)': the Latin
;; name, a genre marker, the English name, and the number.  A directory wants
;; one word of that, and sometimes not the word the corpus chose -- hence
;; `diogenes-roam-name-overrides'.
;;
;; Requires the org-integration branch of diogenes.el: see the README.

;;; Code:

(require 'org)
(require 'seq)
(require 'cl-lib)
(require 'diogenes-org)           ; diogenes-org-capture-template, which this sets

(declare-function diogenes-org--reference-string "diogenes-org" (&optional it))
(declare-function diogenes-org--ref-at-point "diogenes-org" ())
(declare-function diogenes-org--work-name "diogenes-org" (corpus author work))
(declare-function classicist-browser-reference "classicist-citation" ())
(declare-function classicist-citation-abbreviation "classicist-citation"
                  (corpus author &optional work))
(declare-function diogenes--get-author-list "diogenes-perl-interface"
                  (options &optional author-regex))
(declare-function diogenes--assoc-cadr "diogenes-lisp-utils" (key alist))

(defvar org-roam-capture--info)
(defvar org-roam-directory)
(declare-function org-roam-node-find "org-roam-node" (&optional other-window initial-input pred))
(declare-function org-roam-node-tags "org-roam-node" (node))


;;;; Options

;; `diogenes-org-capture-template' WAS DECLARED HERE with a bare `defvar',
;; which is what one writes for a variable another file defines.  In one
;; package with the file that defines it, requiring is the right half of that
;; pair -- and this mode reads the option, saves it, and sets it, so it cannot
;; work without `diogenes-org' anyway.
(defgroup diogenes-roam nil
  "Passage notes filed by author and work."
  :group 'diogenes
  :prefix "diogenes-roam-")

(defcustom diogenes-roam-subdirectory "ref"
  "Where passage notes live, under `org-roam-directory'.
Nil to file them at the root."
  :type '(choice string (const nil)))

(defcustom diogenes-roam-tag "passage"
  "The tag every passage note carries, before the author and the work."
  :type 'string)

(defcustom diogenes-roam-name-overrides nil
  "What to call an author, where the corpus's own name will not do.

An alist of (CORPUS AUTHOR) onto a directory name -- keyed as
`diogenes-abbreviations' is, the author zero-padded as the corpus writes it:

    ((\"tlg\" \"0086\") . \"aristotle\")
    ((\"tlg\" \"0059\") . \"plato\")

Worth setting for the authors one reads often.  `Aristoteles' is what the TLG
says and defensible; `aristotle' is what one types."
  :type '(alist :key-type (list string string) :value-type string))

(defcustom diogenes-roam-file-name 'citation
  "What a passage note's file is called.

`citation' is the passage alone -- 1048a-27.org -- which sorts in the text's
order in dired, THE AUTHOR AND THE WORK BEING IN THE PATH ALREADY so the name
need not repeat them.  `slug' is the title slugified, which org-roam would
have chosen.  `timestamped' prefixes the citation with the time, which is
longer to read and cannot collide."
  :type '(choice (const citation) (const slug) (const timestamped)))

(defcustom diogenes-roam-install-capture-template t
  "Whether enabling `diogenes-roam-mode' sets `diogenes-org-capture-template'.
Nil to write your own and keep the directory naming."
  :type 'boolean)


;;;; The passage in hand

;; `diogenes-org--passage-parts' takes a ref exactly as org-roam stores it --
;; link type, kind marker, escaped colons and all -- and gives back
;; (CORPUS AUTHOR WORK FROM TO), or nil where the ref names a dictionary entry
;; or a page rather than a passage.  So there is no parsing to do here, and
;; refs of the other kinds fall out on their own.

(defvar diogenes-roam--parts-override nil
  "(CORPUS AUTHOR WORK), where there is no ref to read it from.
Let-bound when a path is built for a work named outright.")

(defun diogenes-roam--parts ()
  "(CORPUS AUTHOR WORK) of the passage in hand, or nil.

From `diogenes-roam--parts-override' where it is bound; else from the capture
in progress; else from the browser or the note at point.

IN A BROWSER, THE PLIST DIRECTLY.  `diogenes-org--reference-string' wants a
`:key' as well, and a freshly opened browser has none: point is on the very
first line, whose citation belongs to the lines below it, and
`diogenes-browser-citation-at' searches backward.  What is wanted here is the
work and not the line, so the missing key does not matter."
  (or diogenes-roam--parts-override
      (diogenes-roam--parts-from-capture)
      (diogenes-roam--parts-from-browser)
      (diogenes-roam--parts-from-point)))

(defun diogenes-roam--parts-from-capture ()
  "(CORPUS AUTHOR WORK) of the capture in progress, or nil."
  (when-let* ((ref (and (boundp 'org-roam-capture--info)
                        (plist-get org-roam-capture--info :ref)))
              (p (ignore-errors (diogenes-org--passage-parts ref))))
    (list (nth 0 p) (nth 1 p) (nth 2 p))))

(defun diogenes-roam--parts-from-browser ()
  "(CORPUS AUTHOR WORK) of the browser buffer, or nil."
  (when (derived-mode-p 'diogenes-browser-mode)
    (when-let* ((it (ignore-errors (classicist-browser-reference))))
      (let ((corpus (plist-get it :corpus))
            (author (plist-get it :author))
            (work   (plist-get it :work)))
        (when (and corpus author work)
          (list corpus author work))))))

(defun diogenes-roam--parts-from-point ()
  "(CORPUS AUTHOR WORK) of the note at point, or nil."
  (when-let* ((ref (or (ignore-errors (diogenes-org--reference-string))
                       (ignore-errors (diogenes-org--ref-at-point))))
              (p (ignore-errors (diogenes-org--passage-parts ref))))
    (list (nth 0 p) (nth 1 p) (nth 2 p))))


;;;; Names into directory names

(defun diogenes-roam--author-name (corpus author)
  "What CORPUS calls AUTHOR, or nil.
Goes through the caching in `diogenes--get-info', so the Perl call is made
once per corpus per session."
  (ignore-errors
    (car (diogenes--assoc-cadr
          author (diogenes--get-author-list (list :type corpus))))))

(defun diogenes-roam--tidy (s)
  "S with the corpus's furniture stripped off.
`Metaphysica (025)' becomes `Metaphysica'; `Aristoteles Phil. et Corpus
Aristotelicum, Aristotle (0086)' becomes `Aristoteles Phil. et Corpus
Aristotelicum'."
  (let* ((s (or s ""))
         (s (replace-regexp-in-string "([^)]*)" " " s))
         (s (replace-regexp-in-string "[0-9]+" " " s))
         (s (car (split-string s "," t "[ \t]+"))))
    (string-trim (or s ""))))

(defun diogenes-roam--first-word (s)
  "The first word of S, or nil."
  (car (split-string (or s "") nil t)))

(defun diogenes-roam--slug (s fallback)
  "S as a directory name, or FALLBACK if it comes to nothing."
  (let ((out (string-trim
              (downcase (replace-regexp-in-string "[^A-Za-z0-9]+" "-" (or s "")))
              "-+" "-+")))
    (if (string-empty-p out) fallback out)))

(defun diogenes-roam-author-dir ()
  "Directory name for the author of the passage in hand: one word.
An override where there is one, else the first word of the corpus's name,
else the dictionaries' abbreviation, else the bare number."
  (if-let* ((p (diogenes-roam--parts)))
      (or (cdr (assoc (list (nth 0 p) (nth 1 p)) diogenes-roam-name-overrides))
          (diogenes-roam--slug
           (or (diogenes-roam--first-word
                (diogenes-roam--tidy
                 (diogenes-roam--author-name (nth 0 p) (nth 1 p))))
               (diogenes-roam--tidy
                (car (ignore-errors
                       (classicist-citation-abbreviation (nth 0 p) (nth 1 p))))))
           (format "%s%s" (nth 0 p) (nth 1 p))))
    "unplaced"))

(defun diogenes-roam-work-dir ()
  "Directory name for the work, kept whole: `ethica-nicomachea'.
The corpus's Latin title, else the abbreviation, else the number."
  (if-let* ((p (diogenes-roam--parts)))
      (diogenes-roam--slug
       (diogenes-roam--tidy
        (or (ignore-errors
              (diogenes-org--work-name (nth 0 p) (nth 1 p) (nth 2 p)))
            (cdr (ignore-errors
                   (classicist-citation-abbreviation
                    (nth 0 p) (nth 1 p) (nth 2 p))))))
       (format "work-%s" (nth 2 p)))
    "unplaced"))

(defun diogenes-roam-dir ()
  "Relative directory for the passage in hand, made if it is not there.
org-roam will not create intermediate directories itself, and a capture
target that names one that does not exist is an error."
  (let ((dir (if diogenes-roam-subdirectory
                 (format "%s/%s/%s" diogenes-roam-subdirectory
                         (diogenes-roam-author-dir) (diogenes-roam-work-dir))
               (format "%s/%s"
                       (diogenes-roam-author-dir) (diogenes-roam-work-dir)))))
    (make-directory (expand-file-name dir org-roam-directory) t)
    dir))

(defun diogenes-roam-tags ()
  "Filetags for the passage in hand."
  (format ":%s:%s:%s:" diogenes-roam-tag
          (diogenes-roam-author-dir) (diogenes-roam-work-dir)))

(defun diogenes-roam--citation-file-name ()
  "The citation of the passage in hand as a file name.

NOT FOR THE `slug' CASE, which never passes through here: `${slug}' is
org-roam's own placeholder and must sit in the template LITERALLY for org-roam
to expand it.  An elisp escape that returns the string `${slug}.org' expands
to nothing -- org-capture evaluates `%(...)' after org-roam has made its
`${...}' pass, so the braces reach the filesystem unread, every capture lands
in one file called `${slug}.org', and `file+head' appends to it rather than
making a new note."
  (let* ((ref (and (boundp 'org-roam-capture--info)
                   (plist-get org-roam-capture--info :ref)))
         (parts (and ref (ignore-errors (diogenes-org--passage-parts ref))))
         (from (or (nth 3 parts) "passage"))
         (to (nth 4 parts))
         (cite (diogenes-roam--slug
                (concat from (and to (concat "-" to))) "passage")))
    (if (eq diogenes-roam-file-name 'timestamped)
        (concat (format-time-string "%Y%m%d%H%M%S-") cite ".org")
      (concat cite ".org"))))


;;;; The capture template

(defun diogenes-roam-capture-template ()
  "A `diogenes-org-capture-template' that files notes by author and work.

Read when `diogenes-roam-mode' is enabled, so `diogenes-roam-file-name' takes
effect from the next time the mode is turned on -- `(diogenes-roam-mode -1)'
and again, or set `diogenes-org-capture-template' by hand."
  `(("d" "a passage" plain "%?"
     :target (file+head
              ,(concat "%(diogenes-roam-dir)/"
                       ;; `${slug}' LITERALLY, for org-roam to expand.
                       (if (eq diogenes-roam-file-name 'slug)
                           "${slug}.org"
                         "%(diogenes-roam--citation-file-name)"))
              ,(concat "#+title: ${title}\n"
                       "#+filetags: %(diogenes-roam-tags)\n\n"))
     :unnarrowed t)))


;;;; Finding them again

;;;###autoload
(defun diogenes-roam-find-passage ()
  "Find a passage note, whatever the author."
  (interactive)
  (org-roam-node-find
   nil nil
   (lambda (node) (member diogenes-roam-tag (org-roam-node-tags node)))))

;;;###autoload
(defun diogenes-roam-find-by-author (author)
  "Find a passage note on AUTHOR, named as its directory is."
  (interactive
   (list (completing-read "Author: " (diogenes-roam--known-authors) nil t)))
  (org-roam-node-find
   nil nil
   (lambda (node) (member author (org-roam-node-tags node)))))

(defun diogenes-roam--known-authors ()
  "The author directories there are notes in."
  (let ((root (expand-file-name (or diogenes-roam-subdirectory ".")
                                org-roam-directory)))
    (when (file-directory-p root)
      (seq-filter (lambda (f)
                    (and (file-directory-p (expand-file-name f root))
                         (not (member f '("." "..")))))
                  (directory-files root)))))


;;;; LaTeX

;;;###autoload
(defun diogenes-roam-setup-latex-export ()
  "Have a `diogenes:' link export as an italicised citation.

`diogenes-org' exports the link as its description, which is right for text
and plain for LaTeX; a citation in a paper is set in italics.  Opt in: this
changes a link type the rest of your config may have opinions about.

`:follow' and `:store' are left alone -- `org-link-set-parameters' merges
rather than replaces."
  (interactive)
  (require 'ol)
  (org-link-set-parameters
   (if (boundp 'diogenes-org-link-type) diogenes-org-link-type "diogenes")
   :export (lambda (_path desc format _info)
             (pcase format
               ((or 'latex 'beamer) (format "\\textit{%s}" (or desc "")))
               (_ (or desc ""))))))


;;;; The mode

(defvar diogenes-roam--saved-template nil
  "What `diogenes-org-capture-template' was before the mode was enabled.")

;;;###autoload
(define-minor-mode diogenes-roam-mode
  "File Diogenes passage notes by author and by work.

Sets `diogenes-org-capture-template' so that a note captured from the browser
lands under its author and its work, and is tagged to match.  Everything else
-- the citation in `ROAM_REFS', the lookup by overlap -- is `diogenes-org's
and is untouched."
  :global t
  :group 'diogenes-roam
  (if diogenes-roam-mode
      (when (and diogenes-roam-install-capture-template
                 (boundp 'diogenes-org-capture-template))
        (setq diogenes-roam--saved-template diogenes-org-capture-template
              diogenes-org-capture-template (diogenes-roam-capture-template)))
    (when (boundp 'diogenes-org-capture-template)
      (setq diogenes-org-capture-template diogenes-roam--saved-template))))

(provide 'diogenes-roam)

;;; diogenes-roam.el ends here
