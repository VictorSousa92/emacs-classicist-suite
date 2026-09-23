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
;; `tlg-text' type declaring `(ref_tlg section line)' as its `extra-fields'.
;; So this file fills those three and reads them back, and adds nothing to
;; phi-notes' own vocabulary.
;;
;; THROUGH `:fields' AND NOT `:tlg-fields', which took two attempts to get
;; right.  `:tlg-fields' is read by `phi-create-common-note'; the `tlg-text'
;; type's header function is `phi-md-header', which never sees it.  What
;; `phi-create-note' does is prompt for each of the type's own `extra-fields',
;; taking `:fields' as the default for each -- so supplying them means the
;; prompts arrive filled in and a reader presses return.  Offered and
;; editable, which is better than imposed.
;;
;; HIS SPELLING IS KEPT.  The TLG field stays `ref_tlg', so a note this makes
;; is indistinguishable from one phi-notes made itself.  The other corpora are
;; named by `classicist-phi-ref-fields' -- `ref_phi', `ref_ddp' and the rest.
;;
;; WHICH LEAVES ONE THING OPEN.  The field NAMES come from the note type, and
;; `tlg-text' declares `ref_tlg', so a note on a Latin text is prompted for
;; `ref_tlg' with a `ref_phi' value offered.  A sibling type per corpus is the
;; answer and is not written yet: `phi-note-types' is a plain defvar, so five
;; more entries copied from `tlg-text' with one key changed would do it
;; without touching phi-notes.
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
(declare-function phi-create-note "phi-notes" (type repo-dir &rest args))
(declare-function phi-get-note-id-from-file-name "phi-notes" (filename))
(declare-function phi-sidebar-adjust-buffer "phi-notes" (buffer))
;; OLIVETTI'S, DECLARED WITH AN UNSPECIFIED ARGLIST.  It is another package
;; again, wanted only to turn it off in the work note, and asked `boundp'
;; before it is called.
(declare-function olivetti-mode "olivetti" t t)
(defvar phi-sidebar-buffer)
(defvar phi-sidebar-display-alist)
(defvar phi-sidebar-persistent-window)
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
(declare-function classicist-citation-abbreviation "classicist-citation"
                  (corpus author &optional work))
(declare-function classicist-citation-to-key "classicist-citation" (citation))
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

(defcustom classicist-phi-tag-functions
  '(classicist-phi-tag-author
    classicist-phi-tag-work
    classicist-phi-tag-code)
  "Functions that name a passage note's tags.
Each is called with the reference plist and returns a tag string, or nil to
add none.  The `#\=' is phi-notes' to add.

THREE BY DEFAULT: the author, the work and the corpus code -- `A.R.\=',
`Arg.\=', `tlg0001.001\='.  The first two are the abbreviations the
dictionaries use, so they are the names a classicist would search for; the
third is exact where an abbreviation is missing or ambiguous, and most of both
corpora have no abbreviation at all.

ADD YOUR OWN by adding a function.  It is given the whole reference --
`:corpus\=', `:author\=', `:work\=', `:from\=', `:to\=', `:labels\=',
`:text\=', `:key\=' -- so a tag can be made of anything in it."
  :type '(repeat function)
  :group 'classicist-phi-notes)

(defcustom classicist-phi-extra-tags nil
  "Tags put on every passage note, whatever it is about.
Strings, without the `#\='.  For a reader who wants all of these gathered
under one tag of their own."
  :type '(repeat string)
  :group 'classicist-phi-notes)

(defcustom classicist-phi-structure-notes t
  "Whether a passage note is filed under a note for its work.

A STRUCTURE NOTE PER WORK, which is how a Zettelkasten organises rather than
how a database does.  The work gets a note of its own -- its reference field
names the work and its section and line are empty, which is what makes it the
note about the whole of it -- and every passage note links to it as parent.
phi-notes then does the indexing itself: `phi-backlinks' on the work's note
lists everything said about that text, the sidebar shows it, and the
breadcrumb gives each note its way up.

AND THE WORK'S NOTE IS A PAGE, which a query result is not.  That is the
argument for this over `classicist-phi-notes' alone: somewhere to write what
you think about the Metaphysics as against what you think about 1053a15.

Nil files nothing and leaves the notes flat, which `classicist-phi-notes' can
still search."
  :type 'boolean
  :group 'classicist-phi-notes)

(defcustom classicist-phi-notes-directories nil
  "Where to look for notes about a passage.
Nil reads the directories out of `phi-repository-alist', which is what a
reader with one Zettelkasten wants.  A list of directories overrides it."
  :type '(choice (const :tag "Every phi-notes repository" nil)
                 (repeat directory))
  :group 'classicist-phi-notes)

(defcustom classicist-phi-index-markers
  '("<!-- classicist:index -->" . "<!-- /classicist:index -->")
  "The lines an index is written between, as (OPENING . CLOSING).

BOTH OR NOTHING.  The index is only ever written where both markers are
found, and the region replaced is what lies strictly between them.  A work
note without them gets no index and no complaint -- `classicist-phi-index-work'
offers to add them, and until it is asked nothing touches the file.

THAT IS THE WHOLE SAFETY ARGUMENT.  This is the only thing here that writes
into a file a reader also edits by hand, so the failure it must not have is
eating prose.  Requiring both markers means the worst case is that nothing
happens."
  :type '(cons string string)
  :group 'classicist-phi-notes)

(defcustom classicist-phi-index-line
  "- [[%i]] %c%t"
  "How a note is written in the index.

  %i  the note's id, so `%i' inside brackets is a wikilink phi-mode follows
  %c  its citation -- the section and line as the note records them
  %t  its title, preceded by an em dash when there is one

Ordered by citation, so the index reads down the work."
  :type 'string
  :group 'classicist-phi-notes)

(defcustom classicist-phi-sidebar-side 'ask
  "Which edge of the frame the work note sits on, beside the browser.

  `ask\='    ask on the first use, and remember the answer for the session;
            a prefix argument asks again
  `right\=', `left\=', `top\=', `bottom\='    always that edge
  ALIST     an action alist of your own, passed to `display-buffer\='

ASKED AND REMEMBERED, because which side is right depends on the frame and
the reading, and answering it every time would be tiresome by the fifth note.
One character -- `l\=', `r\=', `t\=', `b\=' -- and `C-u C-c n s\=' moves it,
closing the window it was in.

`right\=', `left\=', `top\=', `bottom\=' AS `diogenes-roam-index-side\=' NAMES
THEM, so a reader who has configured that index need not learn a second
vocabulary.  They are also `display-buffer-in-side-window\='\='s own names;
`display-buffer-in-direction\=', which is the fallback, wants `above\=' and
`below\=' instead, and this file translates where it must.

NOT YET `defer\='.  `diogenes-roam-index-side\=' takes it, and hands the
placement to `classicist-window-behaviour\=' and `classicist-display-actions\='
so that a preset reaches the index.  That is the better design and wants the
suite\='s display machinery rather than a side window of our own."
  :type '(choice (const :tag "Ask, and remember" ask)
                 (const right) (const left) (const top) (const bottom)
                 (alist :tag "A display-buffer action alist"))
  :group 'classicist-phi-notes)

(defcustom classicist-phi-sidebar-size 0.35
  "How much of the frame the work note takes.
A fraction of the width for `right\=' and `left\=', of the height otherwise.
An integer is taken as columns or lines instead.

`diogenes-roam-index-size\='\='s own default, for the same reason its side
names are used."
  :type 'number
  :group 'classicist-phi-notes)

(defcustom classicist-phi-sidebar-manage-sides-vertical t
  "Whether `window-sides-vertical\=' is set to suit the side asked for.

WHICH AXIS OWNS THE FRAME.  Nil, its default, gives top and bottom side
windows the full frame width and confines left and right ones between them;
`t\=' reverses that.  So whichever axis it favours has room and the other may
not:

  with nil, a bottom sidebar can be made from a right one -- it takes the
  whole width, including where the right one was -- but a right one cannot be
  made from a bottom one, there being no full-height column free.

Which is exactly the asymmetry a reader meets: `b\=' and `t\=' reachable from
`l\=' and `r\=', and not the other way back.  So it is set to match: `t\=' for
left and right, nil for top and bottom, and both directions work.

SET AND NOT LET-BOUND, because Emacs consults it again when the frame is
laid out afresh, and a binding undone the moment the window exists would
leave it to be re-confined later.

IT IS GLOBAL, which is the reason this is an option.  Every side window on
the frame answers to it -- another package\='s outline or file tree included --
so a reader who arranges those deliberately should set this to nil and choose
one axis for everything."
  :type 'boolean
  :group 'classicist-phi-notes)

(defcustom classicist-phi-sidebar-verbose nil
  "Whether the side window says what it asked for and what came back.

FOR WHEN IT LANDS SOMEWHERE UNEXPECTED.  The action is assembled from three
sources -- the side and size settled by
`classicist-phi-sidebar-side\=' and `classicist-phi-sidebar-size\=',
phi-notes\=' own `phi-sidebar-display-alist\=' minus those, and its window
parameters -- and reading the code to work out what reached
`display-buffer\=' is slower than printing it."
  :type 'boolean
  :group 'classicist-phi-notes)

(defcustom classicist-phi-sidebar-select t
  "Whether showing the work note puts the cursor in it.
Non-nil to follow a link straight away; nil to keep reading and glance over.
As `diogenes-roam-index-select\='."
  :type 'boolean
  :group 'classicist-phi-notes)

(defcustom classicist-phi-sidebar-olivetti nil
  "Whether olivetti is left on in the work note\='s window.

OFF, BECAUSE AN INDEX IS NOT PROSE.  phi-notes\=' own
`phi-sidebar-adjust-buffer\=' calls `olivetti-set-width\=' where olivetti is
on, which is right for reading a note and wrong for a column of one-line
entries: it centres a narrow body in a window that is already narrow, and the
citations end up in the middle of nowhere.

His adjuster is still called either way -- it is what buttonises the
wikilinks, without which `[[0002]]\=' is not clickable -- and olivetti is
turned off after it where this is nil."
  :type 'boolean
  :group 'classicist-phi-notes)

(defcustom classicist-phi-open-in 'default
  "Where a note opens when reached from the browser or from a list.

`default\=' leaves it to `pop-up-frames\=', so a reader who has set that for
Diogenes\=' sake gets the same behaviour here.  `window\=' and `frame\=' force
one or the other.

NEVER IN THE WINDOW IT WAS ASKED FROM, which is the whole point of the
option.  `find-file\=' and `switch-to-buffer\=' take over the current window,
and the current window is the browser: a reader who lists the notes on a work
and opens one should not lose the text they were reading to it.  The same held
for the note `classicist-phi-note\=' has just written, and for the work note.

`diogenes-roam-index-open-in\='\='s own name and values, which says of itself
`never in the index\='s own window, whichever this is\='.  The same rule, one
window along."
  :type '(choice (const default) (const window) (const frame))
  :group 'classicist-phi-notes)

(defcustom classicist-phi-keys
  '((classicist-phi-note  . "C-c n n")
    (classicist-phi-notes . "C-c n l")
    (classicist-phi-work-note . "C-c n w")
    (classicist-phi-index-work . "C-c n i")
    (classicist-phi-sidebar . "C-c n s"))
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

(defun classicist-phi--tag-string (text)
  "TEXT as something phi-notes will accept as a tag, or nil.
`phi-tag-regex\=' allows letters, digits and a handful of punctuation but no
space, so runs of whitespace become underscores and anything else that is not
allowed is dropped."
  (when (and text (stringp text))
    (let* ((joined (replace-regexp-in-string "[ \t]+" "_" (string-trim text)))
           (kept (replace-regexp-in-string "[^[:alnum:]._:/-]" "" joined)))
      (unless (string-empty-p kept) kept))))

(defun classicist-phi-tag-author (reference)
  "The author of REFERENCE, as the dictionaries abbreviate him."
  (when (fboundp 'classicist-citation-abbreviation)
    (classicist-phi--tag-string
     (car (classicist-citation-abbreviation
           (plist-get reference :corpus)
           (plist-get reference :author))))))

(defun classicist-phi-tag-work (reference)
  "The work of REFERENCE, as the dictionaries abbreviate it."
  (when (fboundp 'classicist-citation-abbreviation)
    (classicist-phi--tag-string
     (cdr (classicist-citation-abbreviation
           (plist-get reference :corpus)
           (plist-get reference :author)
           (plist-get reference :work))))))

(defun classicist-phi-tag-code (reference)
  "REFERENCE\='s corpus and numbers, as `tlg0001.001\='.

EXACT WHERE AN ABBREVIATION IS NOT.  Most of both corpora have none -- the
table covers the five hundred works of the TLG and two hundred and seventy of
the PHI that the lexicographers had occasion to quote -- so for everything
else this is the only tag that names the text at all.

A STOP AND NOT A COLON, unlike the reference field\='s `0001:001\='.  A colon
happens to fall inside `phi-tag-regex\=''s character range, but by accident of
where `/-_\=' lands in ASCII rather than by anyone\='s intention, and a tag
should not rest on that."
  (let ((corpus (plist-get reference :corpus))
         (author (plist-get reference :author))
         (work (plist-get reference :work)))
    (when (and corpus author work)
      (concat corpus author "." work))))

(defun classicist-phi--tags (reference)
  "Every tag a passage note about REFERENCE should carry."
  (delete-dups
   (delq nil
         (append (mapcar (lambda (fn)
                           (and (functionp fn)
                                (classicist-phi--tag-string
                                 (funcall fn reference))))
                         classicist-phi-tag-functions)
                 (mapcar #'classicist-phi--tag-string
                         classicist-phi-extra-tags)))))

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

(defun classicist-phi--line-field (reference)
  "The `line\=' field for REFERENCE, which may name a span.

A MARKED REGION IS AN INTERVAL, and phi-notes has a `section\=' and a `line\='
and no notion of a range.  So the range goes in `line\=':

    1.23 alone          23
    1.23 to 1.24        23-24        the section is the same, so only the
                                     last level differs
    1.23 to 2.5         23-2.5       it is not, so the far end is written
                                     out in full

READ BACK BY TAKING WHAT IS BEFORE THE HYPHEN, which is all
`classicist-phi-goto-passage\=' wants: a browser opens AT a passage and pages
from there, so the beginning is the whole of what it needs.  The far end is
recorded for the reader, not for the machine -- which is also why a form that
cannot be parsed back is acceptable here and would not be in `section\='."
  (let* ((from (classicist-phi--level-strings (plist-get reference :from)))
         (to (classicist-phi--level-strings (plist-get reference :to)))
         (start (and from (car (last from)))))
    (cond
     ((null start) "")
     ((null to) start)
     ;; THE SAME EVERYWHERE ABOVE THE LAST LEVEL: only the last differs, so
     ;; only the last is worth saying.
     ((equal (butlast from) (butlast to))
      (if (equal start (car (last to)))
          start
        (concat start "-" (car (last to)))))
     (t (concat start "-" (string-join to "."))))))

(defun classicist-phi--fields-from-reference (reference &optional field)
  "REFERENCE as the fields phi-notes will ask for, or nil.

AN ALIST KEYED BY THE FIELD SYMBOL, which is what `:fields\=' takes, and NOT
the `:tlg-fields\=' plist.  `:tlg-fields\=' is read by
`phi-create-common-note\='; the `tlg-text\=' type\='s header function is
`phi-md-header\=', which never sees it.  What `phi-create-note\=' does is prompt
for each of the type\='s own `extra-fields\=' --

    (read-string (format \"%s: \" k) (alist-get k transformed-fields))

-- taking `:fields\=' as the DEFAULT for each.  So supplying them here means
the three prompts arrive filled in and a reader presses return, which is the
behaviour wanted: offered, and editable, rather than imposed.

FIELD is the reference field\='s name, `classicist-phi-ref-fields\=' having
settled it for the corpus; nil uses whatever the type declares first."
  (let* ((corpus (plist-get reference :corpus))
         (author (plist-get reference :author))
         (work (plist-get reference :work))
         (from (classicist-phi--level-strings
                (plist-get reference :from))))
    (when (and corpus author work)
      (list (cons (intern (or field "ref_tlg"))
                  (concat author ":" work))
            ;; EVERYTHING ABOVE THE LAST LEVEL, joined by stops, because a
            ;; work may have two levels or four and phi-notes has two fields.
            ;; Reversible, which is the whole requirement.
            (cons 'section (if (cdr from)
                               (string-join (butlast from) ".")
                             ""))
            (cons 'line (classicist-phi--line-field reference))))))

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
               ;; BEFORE THE HYPHEN, `line' possibly naming a span -- see
               ;; `classicist-phi--line-field'.  The beginning is all a
               ;; browser needs.
               (start (and line
                           (car (split-string (string-trim line) "-" t))))
               (levels (append
                        (and section
                             (split-string (string-trim section) "[.]" t))
                        (and start (not (string-empty-p start))
                             (list start)))))
          (when (cdr parts)
            (list :corpus (car found)
                  :author (nth 0 parts)
                  :work (nth 1 parts)
                  :levels levels)))))))



;;;; Which repository, resolved here

;; RESOLVED HERE AND NOT BY `phi-new-note', which cannot be called from a
;; browser at all.  It computes its default repository unconditionally --
;;
;;     (def-repository (phi-repository-for-path (buffer-file-name)))
;;
;; -- before it looks at the `:repository' it was given, and a Diogenes
;; browser buffer has no file, so `buffer-file-name' is nil and the chain
;; ends in `expand-file-name(nil)':
;;
;;     phi-in-repository-p(nil "Notes")
;;     Wrong type argument: stringp, nil
;;
;; Passing `:repository' does not help, the default being computed either
;; way.  So the repository is settled here and `phi-create-note' is called
;; directly, which takes the directory and asks nothing.  Worth reporting
;; upstream: it is every fileless buffer, not just ours.

(defmacro classicist-phi--in-repository (dir &rest body)
  "Run BODY in a buffer that looks like a file in DIR.

PHI-NOTES ASSUMES IT IS CALLED FROM A NOTE, in more than one place, and a
Diogenes browser buffer has no file at all.  Two of its functions reach for
`buffer-file-name\=' without checking:

  `phi-repository-for-path\=', through `phi-new-note\=''s default repository --
  avoided by calling `phi-create-note\=' directly.

  `phi--grep-tag-list\=', through `phi-read-tags\=', which greps the directory
  of the current buffer\='s file for the `#hashtags\=' already in use.  That one
  cannot be avoided: `phi-create-note\=' calls it to offer tag completion.

So the call is made from a temporary buffer carrying a file name inside the
repository.  Nothing is written to it -- `phi-create-note\=' makes its own
buffer and does its own `write-file\=' -- and the name is cleared before the
temporary buffer dies, so nothing offers to save it.

Worth reporting upstream, both of them: it is every fileless buffer and not
only ours."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (setq buffer-file-name
           (expand-file-name ".classicist-phi-note" ,dir))
     (unwind-protect (progn ,@body)
       (set-buffer-modified-p nil)
       (setq buffer-file-name nil))))

(defun classicist-phi--repository-directory ()
  "The directory a note goes in, by `classicist-phi-repository'."
  (unless (and (boundp 'phi-repository-alist) phi-repository-alist)
    (user-error "No phi-notes repository set -- use `phi-add-repository'"))
  (let* ((name
          (cond
           ((stringp classicist-phi-repository) classicist-phi-repository)
           ;; `current' CANNOT MEAN THE BROWSER'S, there being no file
           ;; there; it means the last note visited, and failing that it
           ;; asks.
           ((eq classicist-phi-repository 'current)
            (or (classicist-phi--repository-of-last-note)
                (completing-read "Note repository: " phi-repository-alist
                                 nil t)))
           (t (if (= 1 (length phi-repository-alist))
                  (car (car phi-repository-alist))
                (completing-read "Note repository: " phi-repository-alist
                                 nil t)))))
         (dir (cadr (assoc name phi-repository-alist))))
    (unless dir
      (user-error "No such phi-notes repository: %s" name))
    dir))

(defun classicist-phi--repository-of-last-note ()
  "The repository name of the most recent phi-notes buffer, or nil."
  (when (boundp 'phi-repository-alist)
    (seq-some
     (lambda (buffer)
       (with-current-buffer buffer
         (and (buffer-file-name)
              (seq-some (lambda (entry)
                          (and (file-in-directory-p (buffer-file-name)
                                                    (cadr entry))
                               (car entry)))
                        phi-repository-alist))))
     (buffer-list))))


;;;; The note for a work

(defun classicist-phi--open (file-or-buffer)
  "Show FILE-OR-BUFFER, by `classicist-phi-open-in', and select it.
Never in the window this was called from."
  (let ((buffer (if (bufferp file-or-buffer)
                    file-or-buffer
                  (find-file-noselect file-or-buffer))))
    (pcase classicist-phi-open-in
      ('frame (pop-to-buffer buffer '(display-buffer-pop-up-frame)))
      ('window (pop-to-buffer buffer '(display-buffer-pop-up-window
                                       (inhibit-same-window . t))))
      ;; `default': `pop-to-buffer' consults `display-buffer-alist' and
      ;; `pop-up-frames' as any other buffer would, which is what a reader
      ;; who has set those for Diogenes' sake will expect.  The one thing
      ;; insisted on is that it is not this window.
      (_ (pop-to-buffer buffer '(nil (inhibit-same-window . t)))))
    buffer))


(defun classicist-phi--work-note (corpus author work)
  "The id and file of the structure note for WORK, or nil.

RECOGNISED BY WHAT IT LACKS.  A note whose reference field names this work and
whose `section\=' and `line\=' are both empty is the note about the work
itself, not about a passage in it -- no separate marker is wanted, and none
would survive a reader editing the frontmatter by hand.

Returns (ID . FILE)."
  (let ((field (classicist-phi--ref-field corpus))
        (ref (concat author ":" work)))
    (when field
      (seq-some
       (lambda (file)
         (let* ((fm (ignore-errors (classicist-phi--frontmatter file)))
                (this (cdr (assoc field fm)))
                (section (or (cdr (assoc "section" fm)) ""))
                (line (or (cdr (assoc "line" fm)) ""))
                (id (or (cdr (assoc "id" fm))
                        (and (fboundp 'phi-get-note-id-from-file-name)
                             (phi-get-note-id-from-file-name file)))))
           (and this (equal (string-trim this) ref)
                (string-empty-p (string-trim section))
                (string-empty-p (string-trim line))
                id
                (cons (string-trim id) file))))
       (classicist-phi--note-files)))))

(defun classicist-phi--make-work-note (reference)
  "Make the structure note for the work REFERENCE names.
Returns (ID . FILE), or nil if the note came out without an id."
  (let* ((corpus (plist-get reference :corpus))
         (author (plist-get reference :author))
         (work (plist-get reference :work))
         (field (classicist-phi--ref-field corpus))
         (dir (classicist-phi--repository-directory))
         ;; THE WORK AND NOT THE PASSAGE, so the reference is rebuilt without
         ;; `:text\='.  `Arist. Metaph.\=' and not `Arist. Metaph. 1053a15\='.
         (title (if (fboundp 'classicist-reference-to-string)
                    (classicist-reference-to-string
                     (list :corpus corpus :author author :work work))
                  (concat author ":" work)))
         (buffer
          (classicist-phi--in-repository dir
            (apply #'phi-create-note
                   classicist-phi-note-type
                   dir
                   (list :title title
                         ;; SECTION AND LINE LEFT EMPTY, which is what says
                         ;; this is the work and not a place in it.
                         :fields
                         (list (cons (intern (or field "ref_tlg"))
                                     (concat author ":" work))
                               (cons 'section "")
                               (cons 'line "")))))))
    (when (buffer-live-p buffer)
      (let ((file (buffer-file-name buffer)))
        (when file
          (cons (or (and (fboundp 'phi-get-note-id-from-file-name)
                         (phi-get-note-id-from-file-name file))
                    "")
                file))))))

(defun classicist-phi--work-note-parent (reference)
  "The `:parent-props\=' a passage note about REFERENCE should carry, or nil.
Finds the work\='s structure note, making it when there is none."
  (when classicist-phi-structure-notes
    (let* ((corpus (plist-get reference :corpus))
           (author (plist-get reference :author))
           (work (plist-get reference :work))
           (found (or (classicist-phi--work-note corpus author work)
                      (classicist-phi--make-work-note reference))))
      (when (and found (not (string-empty-p (car found))))
        (list (cons 'id (car found)))))))

;;;###autoload
(defun classicist-phi-work-note ()
  "Visit the structure note for the work in this browser, making it if new.
The place to write what you think about a text as against a passage of it."
  (interactive)
  (classicist-phi--require)
  (let ((reference (and (fboundp 'classicist-browser-reference)
                        (classicist-browser-reference))))
    (unless reference
      (user-error "Not in a Diogenes browser"))
    (let* ((corpus (plist-get reference :corpus))
           (author (plist-get reference :author))
           (work (plist-get reference :work))
           (found (or (classicist-phi--work-note corpus author work)
                      (classicist-phi--make-work-note reference))))
      (if (and found (cdr found))
          (classicist-phi--open (cdr found))
        (user-error "Could not find or make a note for this work")))))

;;;; Making a note

;;;###autoload
(defun classicist-phi-note ()
  "Make a phi-notes note about the passage in this browser buffer.

THE FIELDS ARE FILLED AND NOT PROMPTED FOR: the reference, the section and the
line come from the buffer, which is the point of doing this from a browser
rather than from the note side.  phi-notes asks for the title and the
repository as it always does.

The three fields arrive as defaults in phi-notes' own prompts, so they can be
edited before the note is written.  See `classicist-phi--fields-from-reference'
for why they go in `:fields' and not in `:tlg-fields'."
  (interactive)
  (classicist-phi--require)
  (let ((reference (and (fboundp 'classicist-browser-reference)
                        (classicist-browser-reference))))
    (unless reference
      (user-error "Not in a Diogenes browser -- there is no passage to note"))
    (let* ((corpus (plist-get reference :corpus))
           (field (classicist-phi--ref-field corpus))
           (fields (classicist-phi--fields-from-reference reference field)))
      (unless field
        (user-error
         (concat "No reference field for the `%s' corpus"
                 " -- see classicist-phi-ref-fields")
         corpus))
      (unless fields
        (user-error "This browser does not record which work it is showing"))
      (let* ((dir (classicist-phi--repository-directory))
             (buffer
              (classicist-phi--in-repository dir
                (apply #'phi-create-note
                     classicist-phi-note-type
                     dir
                     (append
                      (list :fields fields
                            :tags (classicist-phi--tags reference))
                      ;; FILED UNDER THE WORK'S OWN NOTE, so that
                      ;; phi-backlinks and the sidebar do the indexing and
                      ;; the breadcrumb gives this note its way up.
                      (let ((parent
                             (classicist-phi--work-note-parent reference)))
                        (when parent (list :parent-props parent)))
                      ;; A TITLE OFFERED AND NOT IMPOSED: the citation as a
                      ;; reader writes it, which is what the note is about.
                      (when (fboundp 'classicist-reference-to-string)
                        (list :title
                              (classicist-reference-to-string
                               reference))))))))
        (when (buffer-live-p buffer)
          (classicist-phi--open buffer))
        buffer))))


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
          ;; WITHOUT THE YAML QUOTES.  A title is written `title: "A.R."',
          ;; and the quotes are the format's rather than the title's -- they
          ;; reached the index as `1.1 -- "A.R. 1.1"'.  phi-notes has
          ;; `phi--without-quotes' for this; doing it here keeps the text
          ;; parser independent of it.
          (push (cons (match-string 1)
                      (string-trim (match-string 2) "\"" "\""))
                fields))
        (forward-line 1))
      (nreverse fields))))

(defun classicist-phi--note-files ()
  "Every markdown file in the note directories."
  (let ((out nil))
    (dolist (dir (classicist-phi--note-directories))
      (setq out (append out (directory-files-recursively
                             dir "\\.\\(md\\|markdown\\)\\'"))))
    out))

(defun classicist-phi--notes-on (corpus author work)
  "Notes about WORK of AUTHOR in CORPUS, as (FILE SECTION LINE TITLE)."
  (let ((field (classicist-phi--ref-field corpus))
        (ref (concat author ":" work))
        (out nil))
    (when field
      (dolist (file (classicist-phi--note-files))
        (let* ((fm (ignore-errors (classicist-phi--frontmatter file)))
               (this (cdr (assoc field fm))))
          (when (and this (equal (string-trim this) ref))
            (push (list file
                        (or (cdr (assoc "section" fm)) "")
                        (or (cdr (assoc "line" fm)) "")
                        (or (cdr (assoc "title" fm))
                            (file-name-base file)))
                  out)))))
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
          (classicist-phi--open (cdr (assoc pick rows))))))))



;;;; An index in the work note

;; WRITTEN INTO THE WORK NOTE and not into a file of its own, which is what
;; makes it a Zettelkasten index rather than a report: `phi-mode' follows the
;; wikilinks, `phi-toggle-sidebar' shows it beside the text, and it is a
;; document to write in as well as to read.
;;
;; AND IT IS WHY THE SIDEBAR WORKS AT ALL.  Three of phi-notes' functions
;; reach for `buffer-file-name' unchecked -- `phi-repository-for-path',
;; `phi--grep-tag-list' and `phi-basic-type-check-p', the last through
;; `phi-get-fields' -- so none of them can be called from a Diogenes browser.
;; A work note is a file, so from there they all work.  Hence an index in the
;; note, opened in the sidebar, rather than a panel of our own.
;;
;; BY HAND FOR NOW.  Refreshing on `after-save-hook' is the obvious next
;; thing and is deliberately not here yet: a hook that rewrites a buffer
;; while it is being typed in should be opted into after the writing is
;; trusted, not before.  `classicist-phi-index-work' is the whole of it.

(defun classicist-phi--index-citation (section line)
  "SECTION and LINE as one citation for an index line."
  (let ((s (string-trim (or section "")))
        (l (string-trim (or line ""))))
    (cond ((and (string-empty-p s) (string-empty-p l)) "")
          ((string-empty-p s) l)
          ((string-empty-p l) s)
          (t (concat s "." l)))))

(defun classicist-phi--index-sort-key (section line)
  "A key for sorting an index line, numeric where the levels are numbers."
  (mapcar (lambda (part)
            (if (string-match-p "\\`[0-9]+\\'" part)
                (string-to-number part)
              part))
          (append (split-string (string-trim (or section "")) "[.]" t)
                  (split-string (car (split-string (string-trim (or line ""))
                                                   "-" t))
                                "[.]" t))))

(defun classicist-phi--index-less-p (a b)
  "Whether index entry A cites an earlier passage than B."
  (let ((x (classicist-phi--index-sort-key (nth 1 a) (nth 2 a)))
        (y (classicist-phi--index-sort-key (nth 1 b) (nth 2 b))))
    (catch 'done
      (while (or x y)
        (let ((p (car x)) (q (car y)))
          (cond ((null p) (throw 'done t))
                ((null q) (throw 'done nil))
                ((and (numberp p) (numberp q))
                 (unless (= p q) (throw 'done (< p q))))
                (t (let ((ps (format "%s" p)) (qs (format "%s" q)))
                     (unless (string= ps qs)
                       (throw 'done (string< ps qs)))))))
        (setq x (cdr x) y (cdr y)))
      nil)))

(defun classicist-phi--index-lines (corpus author work)
  "The index of WORK, as a list of strings, the work's own note excluded."
  (let* ((notes (classicist-phi--notes-on corpus author work))
         (passages
          (seq-remove (lambda (n)
                        ;; THE WORK'S OWN NOTE IS NOT IN ITS OWN INDEX: it is
                        ;; the one with no section and no line.
                        (and (string-empty-p (string-trim (nth 1 n)))
                             (string-empty-p (string-trim (nth 2 n)))))
                      notes))
         (sorted (sort (copy-sequence passages)
                       #'classicist-phi--index-less-p)))
    (mapcar
     (lambda (n)
       (let* ((file (nth 0 n))
              (id (or (and (fboundp 'phi-get-note-id-from-file-name)
                           (phi-get-note-id-from-file-name file))
                      ""))
              (citation (classicist-phi--index-citation (nth 1 n) (nth 2 n)))
              (title (string-trim (or (nth 3 n) ""))))
         (replace-regexp-in-string
          "%i" id
          (replace-regexp-in-string
           "%c" citation
           (replace-regexp-in-string
            "%t" (if (string-empty-p title) "" (concat " \u2014 " title))
            classicist-phi-index-line t t)
           t t)
          t t)))
     sorted)))

(defun classicist-phi--index-write (file lines)
  "Replace the index in FILE with LINES, or say why it cannot.

NOTHING IS TOUCHED WITHOUT BOTH MARKERS.  Returns t when the block was
written, nil when the markers are not both there -- and in that case the
file is not modified at all, which is the point."
  (let ((opening (car classicist-phi-index-markers))
        (closing (cdr classicist-phi-index-markers)))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (let* ((open-at (and (search-forward opening nil t)
                             (progn (forward-line 1) (point))))
               (close-at (and open-at
                              (save-excursion
                                (when (search-forward closing nil t)
                                  (goto-char (match-beginning 0))
                                  (point))))))
          (when (and open-at close-at (<= open-at close-at))
            (delete-region open-at close-at)
            (goto-char open-at)
            (insert (if lines
                        (concat (string-join lines "\n") "\n")
                      "(no notes yet)\n"))
            (save-buffer)
            t))))))

;;;###autoload
(defun classicist-phi-index-work ()
  "Write the index of this work into its work note.

Run from a Diogenes browser.  The work's note is found -- or made -- and the
notes on that work are listed in it between
`classicist-phi-index-markers\=', ordered by citation.

WHERE THE MARKERS ARE ABSENT nothing is written and this offers to add them,
because the alternative is guessing where in a reader\='s own prose an index
belongs."
  (interactive)
  (classicist-phi--require)
  (let ((reference (and (fboundp 'classicist-browser-reference)
                        (classicist-browser-reference))))
    (unless reference
      (user-error "Not in a Diogenes browser"))
    (let* ((corpus (plist-get reference :corpus))
           (author (plist-get reference :author))
           (work (plist-get reference :work))
           (found (or (classicist-phi--work-note corpus author work)
                      (classicist-phi--make-work-note reference)))
           (file (cdr found))
           (lines (classicist-phi--index-lines corpus author work)))
      (unless file
        (user-error "Could not find or make a note for this work"))
      (unless (classicist-phi--index-write file lines)
        (if (yes-or-no-p
             (format "No index markers in %s -- add them at the end? "
                     (file-name-nondirectory file)))
            (progn
              (with-current-buffer (find-file-noselect file)
                (save-excursion
                  (goto-char (point-max))
                  (unless (bolp) (insert "\n"))
                  (insert "\n" (car classicist-phi-index-markers) "\n"
                          (cdr classicist-phi-index-markers) "\n"))
                (save-buffer))
              (classicist-phi--index-write file lines))
          (user-error "Index not written")))
      (message "%d note%s indexed in %s"
               (length lines) (if (= 1 (length lines)) "" "s")
               (file-name-nondirectory file)))))

(defconst classicist-phi--split-directions
  '((left . left) (right . right) (top . above) (bottom . below))
  "The direction each side is called by `display-buffer-in-direction\='.

TWO VOCABULARIES FOR THE SAME FOUR PLACES.  `display-buffer-in-side-window\='
takes `top\=' and `bottom\='; `display-buffer-in-direction\=' takes `above\='
and `below\='.  This file speaks the side window\='s names throughout, those
being `diogenes-roam-index-side\='\='s as well, and translates here.")

(defvar classicist-phi--sidebar-side nil
  "The side answered for this session, or nil before anything was asked.")

(defconst classicist-phi--sidebar-sides
  '((?l . left) (?r . right) (?t . top) (?b . bottom))
  "The characters the side prompt takes.")

(defun classicist-phi--ask-side ()
  "Ask which side, one character, and remember the answer."
  (let* ((char (read-char-choice
                "Show the work note: (l)eft (r)ight (t)op (b)ottom "
                (mapcar #'car classicist-phi--sidebar-sides)))
         (side (cdr (assq char classicist-phi--sidebar-sides))))
    (setq classicist-phi--sidebar-side side)
    side))

(defun classicist-phi--sidebar-side (&optional ask)
  "The side to show the work note on.
ASK non-nil asks again even where an answer is remembered."
  (let ((setting classicist-phi-sidebar-side))
    (cond
     ((and (listp setting) setting) setting)   ; an action alist of their own
     ((memq setting '(left right top bottom)) setting)
     ((or ask (null classicist-phi--sidebar-side)) (classicist-phi--ask-side))
     (t classicist-phi--sidebar-side))))

(defun classicist-phi--sidebar-size-key (side)
  "Whether a window on SIDE is measured across or down."
  (if (memq side '(top bottom)) 'window-height 'window-width))

(defun classicist-phi--side-window (buffer side)
  "BUFFER in a side window on SIDE, as phi-notes would, or nil if refused.

THROUGH `display-buffer\=' AND NOT CALLED DIRECTLY.
`display-buffer-in-side-window\=' is an ACTION FUNCTION, and says of itself
that it

    should be called only by `display-buffer\=' or a function directly or
    indirectly called by the latter

-- so called on its own it returns nil, relying on state `display-buffer\='
sets up.  Which it did here, silently, while the fallback split took the work
and looked like a sidebar gone wrong.  The form wanted is the one an entry in
`display-buffer-alist\=' has, the action function INSIDE the action:

    (display-buffer BUFFER \='(display-buffer-in-side-window
                             (side . right) (window-width . 0.3)))

SAYS WHY IT FAILED, and still falls back.  `ignore-errors\=' was here and
hid the reason for a whole evening: the side window was refused, the split
below took the work, and nothing in the echo area said so.  So a failure is
reported and nil returned -- the split still happens, and the reader learns
what the side window objected to.

THE ALIST IS REPORTED TOO, at `classicist-phi-sidebar-verbose\='.  An action
assembled from three sources -- the side and size settled here, phi-notes\='
own `phi-sidebar-display-alist\=' minus those, and its window parameters --
is not something to reconstruct by reading the code when it can be printed."
  (let* ((his (and (boundp 'phi-sidebar-display-alist)
                   phi-sidebar-display-alist))
         (key (classicist-phi--sidebar-size-key side))
         (size (or classicist-phi-sidebar-size (cdr (assq key his))))
         (action
          (append (list 'display-buffer-in-side-window
                        (cons 'side side)
                        ;; NOT THE WINDOW THIS WAS ASKED FROM.
                        ;; `display-buffer' prefers a window already showing
                        ;; the buffer, so asked from inside the sidebar it
                        ;; hands that one back unchanged and reports
                        ;; success -- which is why moving the index from the
                        ;; bottom to the right did nothing when the index
                        ;; itself was selected, and worked from the browser.
                        '(inhibit-same-window . t))
                  (when size (list (cons key size)))
                  ;; HIS, MINUS WHAT THIS HAS SETTLED -- AND MINUS
                  ;; `window-parameters', WHICH BREAKS THE THING IT IS IN.
                  ;;
                  ;; `display-buffer-in-side-window' installs `window-side'
                  ;; and `window-slot' itself, and says that it
                  ;;
                  ;;     neither modifies ALIST nor installs any other
                  ;;     window parameters unless they have been explicitly
                  ;;     provided via a `window-parameters' entry
                  ;;
                  ;; Providing one REPLACES what it would have installed
                  ;; rather than adding to it, so `window-side' is never set
                  ;; and what comes back is an ordinary window that merely
                  ;; sits where it was asked to.  No error, no nil -- it
                  ;; reports success, which is why this took an evening and
                  ;; ten wrong guesses about frames, purpose-mode and
                  ;; buffer-local variables.
                  ;;
                  ;; Measured: the same action with the entry gives
                  ;; `window-side' nil, and without it `right'.
                  ;;
                  ;; NOTHING IS LOST BY DROPPING IT.  phi-notes adds it from
                  ;; `phi-sidebar-persistent-window' to keep
                  ;; `delete-other-windows' from removing the sidebar -- and
                  ;; a side window is already exempt from that, so the
                  ;; parameter was redundant as well as destructive.
                  ;;
                  ;; `slot' goes too: one chosen for a sidebar at the bottom
                  ;; means nothing on the right.
                  (seq-remove (lambda (cell)
                                (memq (car cell)
                                      '(side slot window-parameters
                                             window-width window-height)))
                              his))))
    ;; THE AXIS BEFORE THE WINDOW.  `window-sides-vertical' decides which
    ;; of the two axes owns the frame, and the other may have no room; set
    ;; it to suit the side asked for and both directions work.  See
    ;; `classicist-phi-sidebar-manage-sides-vertical'.
    (when classicist-phi-sidebar-manage-sides-vertical
      (setq window-sides-vertical (and (memq side '(left right)) t)))
    (when classicist-phi-sidebar-verbose
      (message "classicist-phi: side window action %S (sides-vertical %s)"
               action window-sides-vertical))
    (condition-case err
        (let ((window (display-buffer buffer action)))
          (cond
           ((null window)
            (when classicist-phi-sidebar-verbose
              (message (concat "classicist-phi: no window on the %s"
                               " -- an ordinary one instead")
                       side))
            nil)
           ;; A WINDOW IS NOT YET A SIDE WINDOW.  `display-buffer' can
           ;; answer with an ordinary one and call it success, which is
           ;; exactly what a `window-parameters' entry in the action made it
           ;; do.  So the parameter is read back rather than trusted, and a
           ;; plain window is reported as the failure it is.
           ((null (window-parameter window 'window-side))
            (when classicist-phi-sidebar-verbose
              (message (concat "classicist-phi: %s came back an ordinary"
                               " window, not a side window")
                       side))
            window)
           (t (when classicist-phi-sidebar-verbose
                (message "classicist-phi: side window on the %s" side))
              window)))
      (error
       (message "classicist-phi: side window on the %s refused: %s"
                side (error-message-string err))
       nil))))

(defun classicist-phi--split-beside (buffer side)
  "BUFFER in a window on SIDE, by an ordinary split.
SIDE is named as `display-buffer-in-side-window\=' names it;
`classicist-phi--split-directions\=' translates."
  (let* ((key (classicist-phi--sidebar-size-key side))
         (size (or classicist-phi-sidebar-size
                   (cdr (assq key (and (boundp 'phi-sidebar-display-alist)
                                       phi-sidebar-display-alist)))))
         (direction (or (cdr (assq side classicist-phi--split-directions))
                        side)))
    (display-buffer
     buffer
     (append (list 'display-buffer-in-direction
                   (cons 'direction direction))
             (when size (list (cons key size)))))))

(defun classicist-phi--windows-showing (buffer)
  "Every window on this frame showing BUFFER.

WALKED AND NOT ASKED FOR.  `get-buffer-window\=' answers nil for a buffer in a
side window on the selected frame -- measured, from a browser, with the note
plainly visible in one below it:

    (get-buffer-window (get-buffer \"0001 A.R..markdown\"))  =>  nil
    (one-window-p t)                                     =>  t

while `window-list\=' found the same window without trouble.  Both of those
were used to decide whether an old sidebar needed closing, so neither found
it, nothing was closed, and `display-buffer\=' then did what its docstring
says it may: reused the existing side window and changed its slot.  Which is
why a sidebar at the bottom would not move to the right."
  (seq-filter (lambda (window) (eq (window-buffer window) buffer))
              (window-list)))

(defun classicist-phi--close-sidebar (buffer)
  "Delete every window on this frame showing BUFFER, keeping one window.

MOVING SIDES MEANS CLOSING THE OLD ONE, or `display-buffer\=' reuses it and
only its slot changes.  A `no-delete-other-windows\=' parameter, which
phi-notes sets when `phi-sidebar-persistent-window\=' is on, is cleared
first: it is there to stop `delete-other-windows\=', and this is not that.

The last window on the frame is left alone -- deleting it would error, and
the new display reuses it anyway."
  (let ((deleted nil))
    (dolist (window (classicist-phi--windows-showing buffer))
      (when (> (length (window-list)) 1)
        (set-window-parameter window 'no-delete-other-windows nil)
        (set-window-dedicated-p window nil)
        (ignore-errors (delete-window window) (setq deleted t))))
    deleted))

(defun classicist-phi--close-own-window ()
  "Delete the window this buffer is in, on `kill-buffer-hook\='.
A side window is dedicated, so a killed note would otherwise leave an empty
window that `delete-other-windows\=' declines to clear."
  (let ((buffer (current-buffer)))
    (dolist (window (classicist-phi--windows-showing buffer))
      (when (> (length (window-list)) 1)
        (set-window-parameter window 'no-delete-other-windows nil)
        (set-window-dedicated-p window nil)
        (ignore-errors (delete-window window))))))

(defun classicist-phi--show-beside (buffer side)
  "Show BUFFER on SIDE, by a side window or failing that a split.
Returns the window, or nil."
  (if (and (listp side) side)
      (display-buffer buffer side)
    (or (classicist-phi--side-window buffer side)
        (classicist-phi--split-beside buffer side))))

;;;###autoload
(defun classicist-phi-sidebar (&optional ask)
  "Show this work\='s note beside the text.

A TOGGLE.  Pressed once it shows the note; pressed again, with the note
already on that side, it hides the window.  The BUFFER is left alone, so
nothing is asked about saving and nothing is lost -- and an index is not
somewhere to keep anything that a hidden window would lose.

WHICH SIDE is `classicist-phi-sidebar-side\=': asked on the first use and
remembered for the session, and a prefix argument ASK asks again.  ASK moves
it rather than hiding it, a position changed being the same buffer on another
edge and not a close: the old window is deleted and a new one made, because
`display-buffer\=' would otherwise reuse the old one and change only its
slot.

THE WINDOW IS MADE HERE, using neither of phi-notes\=' two routes to a sidebar,
because both want a file buffer and a Diogenes browser has none:

  `phi-toggle-sidebar\=' asks `phi-get-linked-project-note-id\=', which reaches
  `phi-get-fields\=', which guesses the note type from
  `(file-name-extension (buffer-file-name buffer))\='.

  `phi-sidebar-create-window\=' takes an id, which avoids that, and resolves
  it through `phi-matching-file-name\=' and `phi-notes-path\=', which calls
  `phi--enforce-directory\=', which sets `default-directory\=' from
  `buffer-file-name\='.

`classicist-phi--work-note\=' already knows the file, having found it by
reading frontmatter, so `find-file-noselect\=' and `display-buffer\=' do the
whole job.  His `phi-sidebar-adjust-buffer\=' is still called, so it looks as
his sidebar does, and `phi-sidebar-buffer\=' is set, so his
`phi-toggle-sidebar\=' closes what this opens."
  (interactive "P")
  (classicist-phi--require)
  (let ((reference (and (fboundp 'classicist-browser-reference)
                        (classicist-browser-reference))))
    (unless reference
      (user-error "Not in a Diogenes browser"))
    (let* ((corpus (plist-get reference :corpus))
           (author (plist-get reference :author))
           (work (plist-get reference :work))
           (found (or (classicist-phi--work-note corpus author work)
                      (classicist-phi--make-work-note reference)))
           (file (cdr found)))
      (unless (and file (file-exists-p file))
        (user-error "No note for this work to show"))
      (let* ((buffer (find-file-noselect file))
             ;; WALKED, for the reason `classicist-phi--windows-showing'
             ;; gives: `get-buffer-window' does not find a side window here.
             (shown (car (classicist-phi--windows-showing
                          (find-file-noselect file))))
             (side (classicist-phi--sidebar-side ask)))
        (when (fboundp 'phi-sidebar-adjust-buffer)
          (setq buffer (phi-sidebar-adjust-buffer buffer)))
        ;; AFTER HIS ADJUSTER, which is what turned olivetti on.
        (unless classicist-phi-sidebar-olivetti
          (with-current-buffer buffer
            (when (bound-and-true-p olivetti-mode)
              (olivetti-mode -1))))
        (setq phi-sidebar-buffer buffer)
        ;; ALREADY THERE AND NOT MOVING: select it rather than flickering it
        ;; shut and open again.
        ;; THE WINDOW GOES WITH THE BUFFER.  A side window is dedicated, so
        ;; killing the note leaves an empty window that
        ;; `delete-other-windows' will not clear.
        (with-current-buffer buffer
          (add-hook 'kill-buffer-hook
                    #'classicist-phi--close-own-window nil t))
        (if (and shown
                 ;; THE PARAMETER IS THE SIDE WINDOW'S NAME, which is the
                 ;; vocabulary this file uses -- so they compare directly.
                 ;; It is nil for an ordinary split, which no side equals, so
                 ;; a split is always closed and remade.  Which is right:
                 ;; there is nothing to compare it against.
                 (eq side (window-parameter shown 'window-side))
                 (not ask))
            ;; SHOWING ALREADY, AND ON THIS SIDE: hide it.  A second press
            ;; of the same key should put away what the first put up, as
            ;; `phi-toggle-sidebar' does; selecting a window that is already
            ;; in front of the reader wastes the binding.
            ;;
            ;; HIDDEN AND NOT KILLED.  The buffer stays, so nothing is asked
            ;; about saving and nothing is lost -- and a position changed
            ;; with a prefix argument is not a close at all, being the same
            ;; buffer moved to another edge.
            (progn (classicist-phi--close-sidebar buffer)
                   (message "Work note hidden"))
          (classicist-phi--close-sidebar buffer)
          (let ((window (classicist-phi--show-beside buffer side)))
            (unless window
              (user-error "Could not show %s beside this window"
                          (buffer-name buffer)))
            (when classicist-phi-sidebar-select
              (select-window window))))))))

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
