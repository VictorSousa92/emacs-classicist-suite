;;; tei-browser.el --- other corpora, as TEI XML -*- lexical-binding: t; -*-

;; Keywords: classics, greek, latin, tei
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:

;; THE CORPORA DIOGENES DOES NOT HAVE.  Its eight are the CD-ROM databases in
;; their own binary format; Perseus, the First Thousand Years of Greek, the
;; CSEL and the rest are TEI XML, published a file to an edition, and nothing
;; in the Perl reads them.
;;
;; What makes them worth adding is not only that they are more texts.  They are
;; filed under the SAME numbers: `tlg0059.tlg030' is Plato's Republic here and
;; author 0059 work 030 in the TLG.  So a note made against one answers for the
;; other, a link followed from either opens a passage, and the printed editions
;; are found for both -- none of which has to be arranged, the numbering having
;; been shared all along.
;;
;; THIS FILE IS THE REGISTRY and nothing more: which corpora a reader has, and
;; what each holds.  Reading a text is the next thing, and is not here.

;;; Code:

(require 'seq)

;; TRANSIENT, for the menu append.  diorisis.el requires it and this did
;; not, so transient-get-suffix warned as undefined -- and the file uses
;; transient's API either way.
(require 'transient)

;; THE SUITE FEATURE LIST, if this file is part of a suite at all.
;; Declared and not required: this file stands alone -- absent the suite the
;; guards fall back to what they did before, which is why the one in the
;; autoloaded form asks fboundp first.
(declare-function classicist-feature-p "classicist-groups" (feature))

(defgroup tei nil
  "Corpora published as TEI XML."
  :group 'tools
  :prefix "tei-")

(defcustom tei-directory nil
  "Where the TEI corpora are, or nil for none.

One directory holding a clone apiece:

    /mnt/archive/Diogenes Data/TEI/canonical-greekLit
    /mnt/archive/Diogenes Data/TEI/canonical-latinLit
    /mnt/archive/Diogenes Data/TEI/First1KGreek

    (setq tei-directory \"/mnt/archive/Diogenes Data/TEI\")

The index `tei-index.py\\=' writes is looked for here too.  Nothing in this file
works until it is set, and everything says so rather than failing obscurely."
  :type '(choice (const :tag "None" nil) directory)
  :group 'tei)

(defcustom tei-preferred-language nil
  "Which language to offer first where a work has more than one, or nil.

`grc\\=' or `lat\\=' for the original, `eng\\=' for a translation.  Nil offers every
edition and translation together and lets a reader choose, which is right for a
reader who wants the Greek in one window and the English in another.

A work often has both and sometimes several of each -- the Republic has
Burnet's text and Shorey's translation -- so this is about what comes first,
not about what is available."
  :type '(choice (const :tag "All of them" nil)
                 (const :tag "Greek" "grc")
                 (const :tag "Latin" "lat")
                 (const :tag "English" "eng")
                 string)
  :group 'tei)


;;;; --------------------------------------------------------------------
;;;; WHAT THERE IS
;;;; --------------------------------------------------------------------

(defvar tei--index nil
  "The index as last read: (FILE MODIFICATION-TIME . CORPORA).")

(defun tei--index-file ()
  "Where the index is, or nil."
  (and tei-directory
       (let ((file (expand-file-name "tei-index.eld"
                                     tei-directory)))
         (and (file-readable-p file) file))))

(defun tei-index ()
  "Every corpus the index knows, read again whenever it has changed.

Nil where there is none, and the caller says how to make one: it is
`tei-index.py\\=' that writes it, and a reader who has not run it has nothing
rather than something stale."
  (let* ((file (tei--index-file))
         (stamp (and file (file-attribute-modification-time
                           (file-attributes file)))))
    (cond
     ((null file) nil)
     ((and tei--index
           (equal (car tei--index) file)
           (equal (cadr tei--index) stamp))
      (cddr tei--index))
     (t
      (let ((datum (with-temp-buffer
                     (insert-file-contents file)
                     (goto-char (point-min))
                     (read (current-buffer)))))
        (setq tei--index (cons file (cons stamp datum)))
        datum)))))

(defun tei-corpora ()
  "The corpora a reader actually has, as plists."
  (tei-index))

(defun tei-corpus (id)
  "The corpus called ID, or nil."
  (seq-find (lambda (corpus) (equal (plist-get corpus :id) id))
            (tei-corpora)))

(defun tei-authors (corpus)
  "Every (NUMBER NAME WORKS) in CORPUS."
  (plist-get corpus :authors))

(defun tei-author (corpus number)
  "The author NUMBER in CORPUS, or nil."
  (assoc number (tei-authors corpus)))

(defun tei-works (corpus number)
  "Every work of author NUMBER in CORPUS.
Each is (WORK TITLE EDITIONS TRANSLATIONS), and a version is
\(LANGUAGE LABEL FILE)."
  (nth 2 (tei-author corpus number)))

(defun tei-versions (work)
  "Every text of WORK, editions and translations together.

TOGETHER, because a reader choosing what to read is choosing between them: the
Greek and the English of the Republic are two ways of reading one work and the
distinction between an edition and a translation is not what one chooses by.
`tei-preferred-language\\=' puts one kind first where a reader has a
habit."
  (let ((all (append (nth 2 work) (nth 3 work))))
    (if (not tei-preferred-language)
        all
      (append
       (seq-filter (lambda (v)
                     (string-prefix-p tei-preferred-language
                                      (or (car v) "")))
                   all)
       (seq-remove (lambda (v)
                     (string-prefix-p tei-preferred-language
                                      (or (car v) "")))
                   all)))))


;;;; --------------------------------------------------------------------
;;;; SAYING WHAT THERE IS
;;;; --------------------------------------------------------------------

;;;###autoload
(defun tei-list-corpora ()
  "Say which TEI corpora are configured, and how much is in each."
  (interactive)
  (let ((corpora (tei-corpora)))
    (unless corpora
      (user-error
       (concat "No TEI index.  Set tei-directory, clone a corpus "
               "into it, and run: python3 tei-index.py DIRECTORY")))
    (with-current-buffer (get-buffer-create "*Classicist TEI corpora*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "TEI corpora\n\n" 'face 'bold))
        (dolist (corpus corpora)
          (let* ((authors (tei-authors corpus))
                 (works (apply #'+ (mapcar (lambda (a) (length (nth 2 a)))
                                           authors)))
                 (texts (apply #'+
                               (mapcar
                                (lambda (a)
                                  (apply #'+
                                         (mapcar
                                          (lambda (w)
                                            (+ (length (nth 2 w))
                                               (length (nth 3 w))))
                                          (nth 2 a))))
                                authors))))
            (insert (format "%-34s %s\n"
                            (propertize (or (plist-get corpus :name) "?")
                                        'face 'success)
                            (plist-get corpus :language)))
            (insert (format "   %d authors, %d works, %d texts\n"
                            (length authors) works texts))
            (insert (format "   %s\n\n"
                            (propertize (or (plist-get corpus :directory) "")
                                        'face 'shadow)))))
        (goto-char (point-min)))
      (special-mode)
      (pop-to-buffer (current-buffer)))))

;;;###autoload
(defun tei-select-work ()
  "Choose a corpus, an author and a work, and return what was chosen.

Returns (CORPUS AUTHOR-NUMBER WORK VERSION), the reading of it being somebody
else\\='s business -- this is the registry, and the registry\\='s part is to say
what there is and let a reader point at one of it."
  (interactive)
  (let ((corpora (tei-corpora)))
    (unless corpora
      (user-error "No TEI index: run tei-index.py first"))
    (let* ((corpus
            (if (= (length corpora) 1)
                (car corpora)
              (let ((names (mapcar (lambda (c)
                                     (cons (plist-get c :name) c))
                                   corpora)))
                (cdr (assoc (completing-read "Corpus: " names nil t)
                            names)))))
           (authors (tei-authors corpus))
           (by-name (mapcar (lambda (entry)
                              (cons (format "%s (%s)"
                                            (or (nth 1 entry) "?")
                                            (car entry))
                                    entry))
                            authors))
           (author (cdr (assoc (completing-read "Author: " by-name nil t)
                               by-name)))
           (works (nth 2 author))
           (by-title (mapcar (lambda (work)
                               (cons (format "%s (%s)"
                                             (or (nth 1 work) "?")
                                             (car work))
                                     work))
                             works))
           (work (cdr (assoc (completing-read "Work: " by-title nil t)
                             by-title)))
           (versions (tei-versions work))
           (version
            (if (= (length versions) 1)
                (car versions)
              (let ((labels
                     (mapcar (lambda (v)
                               (cons (format "%-8s %s" (or (car v) "?")
                                             (or (nth 1 v)
                                                 (file-name-base (nth 2 v))))
                                     v))
                             versions)))
                (cdr (assoc (completing-read "Text: " labels nil t)
                            labels))))))
      (list corpus (car author) work version))))

;;;; --------------------------------------------------------------------
;;;; READING ONE
;;;; --------------------------------------------------------------------

;; DERIVED FROM DIOGENES' BROWSER where Diogenes is present, and from
;; `special-mode' where it is not.
;;
;; Which is the whole reason for doing it this way.  `C-c C-c' looks a word up
;; because the lookup reads the BUFFER and not the corpus; `C-c l' stores an
;; org link because it asks `classicist-browser-reference'; `C-c C-r' finds
;; Burnet's printed page because the editions package reads the citation.  None
;; of the three knows or cares where the text came from, so all three work on a
;; Perseus text the moment it is rendered in the shape they expect.
;;
;; What cannot be inherited is PAGING: in the real browser that is a running
;; Perl process, and there is none here.  But the whole text is on disk, so
;; paging becomes moving about a buffer, which is simpler and better.

(defvar tei--directory
  (file-name-directory (or load-file-name buffer-file-name
                           (locate-library "tei-browser") ""))
  "Where this package's own files are.

CAPTURED AS THIS FILE LOADS, because `load-file-name\=' is bound only while a
file is being loaded and is nil by the time a command runs.  Asking for it then
fell back on `default-directory\=' -- wherever the reader happened to be -- and
the scripts were reported missing while sitting beside the elisp all along.")

(defcustom tei-read-script nil
  "Where `tei-read.py\=' is, or nil to look beside this file.

Nil is right for a package installed as a package: the script is in the
repository beside the elisp, and `tei--directory\=' finds it.  Set this where
the two have been separated -- a build directory holding only the elisp, which
is what some package managers make."
  :type '(choice (const :tag "Beside tei-browser.el" nil) file)
  :group 'tei)

(defun tei--script ()
  "Where the reading script is, or an error saying where it was looked for."
  (or (and tei-read-script (file-exists-p tei-read-script) tei-read-script)
      (let ((beside (expand-file-name "tei-read.py" tei--directory)))
        (and (file-exists-p beside) beside))
      (let ((library (ignore-errors
                       (expand-file-name
                        "tei-read.py"
                        (file-name-directory (locate-library "tei-browser"))))))
        (and library (file-exists-p library) library))
      ;; AND THROUGH THE SYMLINK, which is the straight case and answers it
      ;; exactly.  straight SYMLINKS the .el files into
      ;; straight/build-VERSION/NAME and leaves every other file in the
      ;; repository, so both places tried above are inside a build and hold
      ;; no .py -- but the symlink's target IS the file in the repository,
      ;; and the script sits beside that wherever the repository happens to
      ;; be.  The search below cannot reach it when the recipe says
      ;; `:local-repo' and the repository is nowhere near straight/repos:
      ;; found that way on Doom, with the repository on a mounted share,
      ;; where the reader was told to set `tei-read-script' by hand.
      (let ((true (ignore-errors
                    (expand-file-name
                     "tei-read.py"
                     (file-name-directory
                      (file-truename (locate-library "tei-browser")))))))
        (and true (file-exists-p true) true))
      ;; AND THE SOURCE CHECKOUT, which is where a .py actually is.  A
      ;; package manager builds .el files into a build directory and leaves
      ;; everything else where it cloned -- straight keeps
      ;; straight/build-VERSION/NAME beside straight/repos/REPO, quelpa
      ;; builds into .cache/quelpa/build/NAME and installs the elisp into
      ;; elpa.  Both places tried above are inside the build, so a reader who
      ;; INSTALLED rather than cloned had no script at all and was told to
      ;; name it -- twice today, on two distributions.
      ;;
      ;; ASKED OF THE DIRECTORY RATHER THAN OF THE MANAGER: whatever built
      ;; this, the file sits beside a copy of the repository somewhere near,
      ;; and one search of the parent finds it.  tei-index.py and
      ;; diorisis-index.py need none of this -- they are named in messages
      ;; and run in a shell, never from here.
      (let* ((dir (or tei--directory
                      (ignore-errors
                        (file-name-directory
                         (locate-library "tei-browser"))))))
        (and dir
             (car (ignore-errors
                    (directory-files-recursively
                     (expand-file-name "../.." dir)
                     (concat "\\`" (regexp-quote "tei-read.py") "\\'")
                     nil
                     ;; NOT INTO node_modules OR .git, which are large and
                     ;; hold no script of ours.
                     (lambda (d)
                       (not (string-match-p
                             "\\`\\(?:[.]\\|node_modules\\)"
                             (file-name-nondirectory d)))))))))
      (user-error
       (concat "tei-read.py not found.  Looked beside tei-browser.el (%s) "
               "and where the library is.  Set tei-read-script to its path")
       (or tei--directory "nowhere"))))


(define-derived-mode tei-mode special-mode "TEI"
  "A TEI text, read as Diogenes reads its own.

DERIVED FROM `special-mode\=' AND THEN LENT THE BROWSER'S MAP, rather than
derived from the browser itself.

Deriving from it would be neater to read and cannot be done: the parent of a
`define-derived-mode\=' is fixed when the form is compiled, and whether
Diogenes is installed is not known until the file is loaded.  A macro reading
a variable at expansion time was worse still -- a `defvar\=' at the top level
only DECLARES when compiling, so the variable was void and the compile failed.

What deriving would have bought is the browser's keymap and its commands, and
those can be had directly: the map is made the parent of ours, so every key
Diogenes binds works here and ours take precedence.  The commands themselves
read the buffer, not the corpus, so they work on a TEI text unchanged.

\\{tei-mode-map}"
  (setq-local truncate-lines nil)
  (visual-line-mode 1)
  ;; THE BROWSER'S KEYS, where there is a browser.  `C-c C-c' to look a word
  ;; up, `C-c C-r' for the printed edition, and the rest: they read the
  ;; citation off the buffer and do not care where the text came from.
  (tei--lend-browser-keys)
  ;; AND COUNTED AS A BROWSER, which is what everything actually tests.
  ;;
  ;; `classicist-browser-reference' opens with
  ;; `(when (derived-mode-p \='classicist-browser-mode) ...)' -- and so, in their
  ;; turn, do the org store, the notes and the editions.  Lending the keymap
  ;; gave the KEYS and not the answer: every command ran and every one of them
  ;; declined, `No method for storing a link from this buffer'.
  ;;
  ;; `derived-mode-add-parents' says that this mode is one of those, without
  ;; deriving from it -- which cannot be done here, the parent of a
  ;; `define-derived-mode' being fixed when the form is compiled and Diogenes
  ;; not known to be installed until it is loaded.  Emacs 30 has the function;
  ;; on 29 the property it sets can be put there directly.
  (tei--count-as-browser))

(defun tei--count-as-browser ()
  "Have `derived-mode-p\=' count this buffer as a Diogenes browser.

Only where Diogenes is installed: a mode claiming to derive from something
absent would have every command that tests for it fail obscurely rather than
not offering itself at all."
  (when (or (featurep 'classicist-browser)
            (and (locate-library "classicist-browser")
                 (require 'classicist-browser nil t)))
    (cond
     ((fboundp 'derived-mode-add-parents)
      (derived-mode-add-parents 'tei-mode '(classicist-browser-mode)))
     (t
      ;; Emacs 29 and before: the same thing, said to the symbol itself.
      (put 'tei-mode 'derived-mode-extra-parents
           '(classicist-browser-mode))))))

(defun tei--lend-browser-keys ()
  "Make Diogenes' browser map the parent of ours, where there is one.

TRIED AGAIN AT EVERY MODE START, and once more when `classicist-browser\=' loads.
The map is defined by that file, and a reader who opens a TEI text before ever
opening a Diogenes browser has not loaded it -- so the first attempt found
nothing bound and the keys were simply absent, with no error to say why.

`require\=' rather than waiting, where Diogenes is installed at all: the file
is wanted now, and loading it is cheap beside reading a text."
  (when (or (featurep 'classicist-browser)
            (and (locate-library "classicist-browser")
                 (require 'classicist-browser nil t)))
    (when (and (boundp 'classicist-browser-mode-map)
               (keymapp classicist-browser-mode-map)
               (not (eq (keymap-parent tei-mode-map)
                        classicist-browser-mode-map)))
      (set-keymap-parent tei-mode-map classicist-browser-mode-map))))

;; NO COOKIE, AND THIS ONE DID NOT EVEN ERROR.  The guard is (boundp
;; 'tei-mode-map), and in the autoloads context that variable is unbound --
;; so the form ran, found nothing, and did nothing.  Silently: a no-op is
;; worse than the void function two forms down, which at least said so.
;;
;; Without the cookie the keys are lent when this file loads, which is when
;; tei-mode-map exists and there is a keymap to lend to.
(with-eval-after-load 'classicist-browser
  (when (boundp 'tei-mode-map)
    (tei--lend-browser-keys)))

(defvar-local tei--datum nil
  "The text this buffer is showing, as `tei-read.py' wrote it.")

(defvar-local tei--sections nil
  "An alist of (CITATION . POSITION), where each passage begins.")

(defun tei--citation-levels (citation)
  "CITATION as Diogenes writes its levels: `327a\\=' as (327 a).

WHAT THE `cit\\=' PROPERTY HOLDS.  Diogenes puts a list of numbers and symbols
on each line -- (327 a) -- and `classicist-browser-citation-at' hands it on to
everything that asks where a line is.  A string would not do: the callers
compare level by level.

A page and its section are two levels, as the corpora count them."
  (let ((out nil))
    (dolist (part (split-string (or citation "") "[.]" t))
      (if (string-match "\\`\\([0-9]+\\)\\([a-z]\\)\\'" part)
          (setq out (append out
                            (list (string-to-number (match-string 1 part))
                                  (intern (match-string 2 part)))))
        (setq out (append out
                          (list (if (string-match-p "\\`[0-9]+\\'" part)
                                    (string-to-number part)
                                  (intern part)))))))
    out))

(defun tei--render (datum)
  "Put DATUM's text in the current buffer, citation by citation."
  (let ((inhibit-read-only t)
        (places nil)
        (last-second nil))
    (erase-buffer)
    (dolist (passage (plist-get datum :passages))
      ;; (CITATION SECOND . WORDS), as `tei-read.py' writes it.  SECOND is the
      ;; other way of referring to the passage where the text marks one --
      ;; Kuehn's page for Galen -- and nil where it does not.
      (let* ((citation (car passage))
             (second (cadr passage))
             (words (cddr passage))
             (levels (tei--citation-levels citation))
             (start (point)))
        (push (cons citation start) places)
        ;; THE SECOND REFERENCE ONLY WHERE IT CHANGES.  Kuehn's page covers
        ;; several sections, and printing it against each would say the same
        ;; thing five times over.
        ;; NOR WHERE IT IS THE CITATION ITSELF.  For Plato the milestone IS
        ;; the citation -- `327a' is both -- and printing it above the line
        ;; that already says it says it twice.
        (when (and second
                   (not (equal second citation))
                   (not (equal second last-second)))
          (insert (propertize (format "%s\n" second)
                              'face 'font-lock-comment-face
                              'cit levels)))
        (setq last-second second)
        (insert (propertize (format "%-8s " citation)
                           'face 'shadow
                           'cit levels)
                (propertize words 'cit levels)
                "\n\n")
        ;; THE CITATION ON EVERY CHARACTER of the section, not only on its
        ;; marker.  `classicist-browser-citation-at' searches backward where the
        ;; line it is asked about has none -- so a property only on the marker
        ;; would answer for the whole section anyway -- but a note stored from
        ;; the middle of a long section should say which section, not hunt for
        ;; it.
        (let ((fill-column (min (or fill-column 80) 78)))
          (fill-region start (point)))))
    (setq tei--sections (nreverse places))
    (setq tei--datum datum)
    (goto-char (point-min))
    (set-buffer-modified-p nil)))

(defun tei--diogenes-locals (datum urn)
  "Tell Diogenes' own commands what this buffer is showing.

`classicist-browser-reference' reads these, and everything that asks where a
reader is asks IT.  Setting them is what makes a Perseus text answer to the
lookups, the org links and the printed editions -- the numbering being
Diogenes' own already, there is nothing to convert.

URN is `urn:cts:greekLit:tlg0059.tlg030.perseus-grc2', of which the author and
the work are the part that matters."
  (let* ((tail (car (last (split-string (or urn "") ":"))))
         (parts (split-string (or tail "") "[.]"))
         (author (and (nth 0 parts)
                      (replace-regexp-in-string "[^0-9]" "" (nth 0 parts))))
         (work (and (nth 1 parts)
                    (replace-regexp-in-string "[^0-9]" "" (nth 1 parts)))))
    (dolist (pair (list (cons 'classicist--browser-corpus "tlg")
                        (cons 'classicist--browser-author author)
                        (cons 'classicist--browser-work work)
                        (cons 'classicist--browser-language
                              (if (equal (plist-get datum :language) "lat")
                                  "latin" "greek"))
                        (cons 'classicist--browser-labels
                              (plist-get datum :levels))))
      ;; SET WHETHER OR NOT DIOGENES HAS DECLARED IT.  The guard was
      ;; `(when (boundp ...))', so a variable Diogenes had not yet declared
      ;; was skipped -- and then the lookup, which by now had its keys, found
      ;; `classicist--browser-language' void.
      ;;
      ;; Making a buffer-local binding for a symbol nobody else uses costs
      ;; nothing, and where Diogenes is loaded it is the same symbol its own
      ;; commands read.
      (set (make-local-variable (car pair)) (cdr pair)))))

(defun tei--resolve (file)
  "FILE as an absolute path.

THE INDEX MAY HOLD A RELATIVE ONE.  `tei-index.py\=' records the paths as it
was given them, so an index built with `.\=' for the directory holds
`./canonical-greekLit/...\=' -- which resolves against whatever buffer a
command is run from, and so resolves to nothing.  Resolved here against
`tei-directory\=', which is where the corpora are by definition."
  (cond ((file-name-absolute-p file) file)
        (tei-directory (expand-file-name file tei-directory))
        (t (expand-file-name file))))

(defcustom tei-convert-quietly nil
  "Whether a text that will not convert is passed over without a word.

Nil says so: a reader who asked for a text is owed an answer, and `it marks
neither divisions nor milestones\=' is an answer.  Non-nil declines silently,
for a reader working through a corpus and not wanting to hear about each
failure."
  :type 'boolean
  :group 'tei)

(defun tei--read-file (file)
  "FILE's `.eld', reading the text first where there is none.

The conversion is `tei-read.py''s: a megabyte of TEI with the citations as
milestones is a stream parser's work, and the result is read in one go."
  (setq file (tei--resolve file))
  (unless (file-readable-p file)
    (user-error "No such text: %s" file))
  (let ((eld (concat (file-name-sans-extension file) ".eld")))
    (unless (and (file-readable-p eld)
                 (file-newer-than-file-p eld file))
      (let ((script (tei--script)))
        (message "Reading %s ..." (file-name-nondirectory file))
        ;; WHAT THE SCRIPT SAID.  Discarding its output left `Could not read'
        ;; and nothing to act on -- and the script says exactly what was
        ;; wrong: a text that marks no sections, a file that is not TEI.
        (with-temp-buffer
          (let ((status (call-process "python3" nil t nil script file eld)))
            (unless (and (eq status 0) (file-readable-p eld))
              (user-error "Could not read %s: %s"
                          (file-name-nondirectory file)
                          (string-trim (buffer-string))))))))
    (with-temp-buffer
      (insert-file-contents eld)
      (goto-char (point-min))
      (read (current-buffer)))))

;;;###autoload
(defun tei--open-version (work version)
  "Read the file VERSION names and show it, WORK naming the text.
THE CALLABLE HALF of `tei-open-work', which prompts.  Split out for the
lexica: a citation in an entry asks the index whether the text is here and
then wants to open it, with nobody to ask which edition -- the prompt is the
command's business and the opening is not."
  (let* ((file (nth 2 version))
         (datum (tei--read-file file))
         (name (format "*TEI: %s (%s)*"
                       (or (nth 1 work) "?")
                       (or (car version) "?"))))
    (let ((buffer (get-buffer-create name)))
      (with-current-buffer buffer
        (tei-mode)
        (tei--diogenes-locals datum (plist-get datum :urn))
        (tei--render datum))
      ;; THROUGH THE SUITE, as diorisis.el does.  A raw pop-to-buffer
      ;; means pop-up-frames makes a frame and the suite places nothing,
      ;; so a text opened in a frame of its own beside the dashboard.  A
      ;; TEI text is a text, so 'browser.
      (if (fboundp 'classicist-display-buffer)
          (classicist-display-buffer buffer :kind 'browser)
        (pop-to-buffer buffer)))))

;;;###autoload
;; NAMED BY THE AUTOLOADED MENU APPEND, so it must be reachable before
;; this file has loaded -- Suffix command is not defined or autoloaded,
;; otherwise.  Lost when tei--open-version was split out of this command,
;; the split having rewritten the defun and not the cookie above it.
(defun tei-open-work ()
  "Choose a TEI text and read it."
  (interactive)
  (let* ((chosen (tei-select-work)))
    (tei--open-version (nth 2 chosen) (nth 3 chosen))))

(defun tei-goto-citation (citation)
  "Move to CITATION in this text."
  (interactive
   (list (completing-read "Citation: " (mapcar #'car tei--sections) nil t)))
  (let ((where (cdr (assoc citation tei--sections))))
    (unless where (user-error "No %s in this text" citation))
    (goto-char where)
    (recenter 0)))

(defun tei-open-book ()
  "Move to one of this text's books.

FROM THE TEXT, not from a table.  A Perseus text marks its books --
`<div subtype=\"book\" n=\"1\">' -- so the Republic gives its ten and the Laws
its twelve without anyone having typed them."
  (interactive)
  (let ((books (plist-get tei--datum :books)))
    (unless books
      (user-error "This text marks no books"))
    (let* ((labels (mapcar (lambda (book)
                             (cons (format "%-6s at %s"
                                           (car book) (cadr book))
                                   book))
                           books))
           (picked (cdr (assoc (completing-read "Book: " labels nil t)
                               labels))))
      (tei-goto-citation (cadr picked)))))

(defun tei-next-passage (&optional n)
  "Move to the next passage, or the Nth after this one."
  (interactive "p")
  (let ((places (mapcar #'cdr tei--sections)))
    (setq places (sort (copy-sequence places) #'<))
    (let ((next (seq-find (lambda (where) (> where (point))) places)))
      (dotimes (_ (1- (or n 1)))
        (let ((after (seq-find (lambda (w) (> w (or next (point)))) places)))
          (when after (setq next after))))
      (if next (progn (goto-char next) (recenter 0))
        (message "The last passage")))))

(defun tei-previous-passage (&optional n)
  "Move to the previous passage, or the Nth before this one."
  (interactive "p")
  (let* ((places (sort (mapcar #'cdr tei--sections) #'<))
         (before (seq-filter (lambda (where) (< where (point))) places))
         (want (nth (1- (or n 1)) (reverse before))))
    (if want (progn (goto-char want) (recenter 0))
      (message "The first passage"))))

(let ((map tei-mode-map))
  (keymap-set map "g" #'tei-goto-citation)
  (keymap-set map "b" #'tei-open-book)
  (keymap-set map "w" #'tei-open-work)
  (keymap-set map "n" #'tei-next-passage)
  (keymap-set map "p" #'tei-previous-passage)
  ;; PAGING TAKEN OVER, not let through.  The buffer claims to be a Diogenes
  ;; browser -- which is what makes the lookups and the links work -- and
  ;; `classicist-browser-forward' would therefore be reached by `C-c C-n' and
  ;; would talk to a Perl process that does not exist here.
  ;;
  ;; The whole text is in the buffer, so what those keys mean is moving about
  ;; it.  Bound in OUR map, which is the child, so they take precedence over
  ;; the browser's own without anything of the browser's being altered.
  (keymap-set map "C-c C-n" #'tei-next-passage)
  (keymap-set map "C-c C-p" #'tei-previous-passage)
  (keymap-set map "C-c C-<right>" #'tei-next-passage)
  (keymap-set map "C-c C-<left>" #'tei-previous-passage)
  ;; And quitting is quitting a buffer, not a Perl process.
  (keymap-set map "C-c C-q" #'quit-window))


;;;; --------------------------------------------------------------------
;;;; IN DIOGENES' OWN MENU
;;;; --------------------------------------------------------------------

;; APPENDED BY THIS PACKAGE, and not declared by Diogenes.  The entry belongs
;; to whoever owns the command, and Diogenes cannot name a command it has never
;; heard of: a branch carrying the entry would break for a reader who cloned it
;; without this package.
;;
;; `with-eval-after-load' so the order of loading does not matter, and
;; `ignore-errors' so a Diogenes whose menu is arranged otherwise -- a suffix
;; renamed, a column rearranged -- costs a message and not a broken startup.

(defcustom tei-add-to-diogenes-menu t
  "Whether to put an entry in Diogenes\=' own transient menu.

Non-nil appends `Browse other corpora\=' beside its BROWSE entries, so the TEI
corpora are reached the same way the TLG is.  Nil leaves the menu alone, for a
reader who would rather bind `tei-select-work\=' themselves.

The entry appears only where both packages are present: Diogenes knows nothing
of this one, and this one adds itself."
  :type 'boolean
  :group 'tei)

;;;###autoload
;; AUTOLOADED BECAUSE THE MENU HOOK NAMES IT, and add-hook runs from
;; the autoloads where this file has not loaded: run-hooks then found
;; a void function.  A cookie makes the name reachable, which is what
;; the fboundp guards above were doing by hand.
(defun tei--add-to-diogenes-menu ()
  "Put our entry in Diogenes' menu.  Idempotent."
  (when (and (classicist-feature-p 'tei-corpora)
             tei-add-to-diogenes-menu
             (fboundp 'transient-append-suffix))
    (ignore-errors
      (transient-append-suffix 'diogenes "bm"
        '("bt" "Browse other corpora (TEI)" tei-open-work)))))
;;;###autoload
;; THE COOKIE IS RIGHT AND THE OLD BODY WAS WRONG.  This form is the one
;; that runs on a FRESH Emacs, before this file has loaded -- so it must ask
;; nothing of it.  It called tei--add-to-diogenes-menu, which was void, and
;; I removed the cookie instead of the fault: the error went and so did the
;; menu entry, which then appeared only once something had pulled this file
;; in and vanished at the next restart.
;;
;; diorisis.el had solved this already and says so in its own comment.  The
;; shape: call the function where it exists, and otherwise do the appending
;; here, naming only tei-open-work, which is autoloaded.
;; ON classicist AND NOT ON diogenes.  This appends to the diogenes
;; transient, and that prefix is defined in classicist.el now -- its
;; autoload used to name the base file, which is why the base loaded and
;; this fired.  With the autoload corrected, waiting on the base means
;; waiting for a file that may never load, while the file defining the
;; thing being modified loads under another name.
(with-eval-after-load 'classicist
  (if (fboundp 'tei--add-to-diogenes-menu)
      (tei--add-to-diogenes-menu)
    (when (and (or (not (fboundp 'classicist-feature-p))
                   (classicist-feature-p 'tei-corpora))
               (if (boundp 'tei-add-to-diogenes-menu)
                   tei-add-to-diogenes-menu
                 t)
               (fboundp 'transient-append-suffix))
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "bt"))
          (transient-append-suffix 'diogenes "bm"
            (list "bt" "Browse other corpora (TEI)" 'tei-open-work)))))))

;; AND AGAIN WHEN THE BASE LOADS, because its own
;; transient-define-prefix REPLACES the diogenes prefix wholesale and
;; takes the appended suffixes with it: the first press showed them and
;; the second did not, the base having loaded in between.
;;
;; IDEMPOTENT, so twice is safe: each append asks transient-get-suffix
;; first, which is what that guard was put there for.
(with-eval-after-load 'diogenes
  (if (fboundp 'tei--add-to-diogenes-menu)
      (tei--add-to-diogenes-menu)
    (when (and (or (not (fboundp 'classicist-feature-p))
                   (classicist-feature-p 'tei-corpora))
               (if (boundp 'tei-add-to-diogenes-menu)
                   tei-add-to-diogenes-menu
                 t)
               (fboundp 'transient-append-suffix))
      (ignore-errors
        (unless (ignore-errors (transient-get-suffix 'diogenes "bt"))
          (transient-append-suffix 'diogenes "bm"
            (list "bt" "Browse other corpora (TEI)" 'tei-open-work)))))))

(defun tei--work-in-index-p (corpus author work)
  "Whether the index holds AUTHOR's WORK in CORPUS.
A LOOKUP AND NOT A GUESS.  The index is keyed by author number -- \`tei-authors\='
gives entries whose car is the number and whose third element is the works,
each work's car being its own -- so this asks it rather than assembling a CTS
URN and hoping something answers.

FOR THE LEXICA, which ask before offering a citation as a link.  Perseus and
the First Thousand Years of Greek are a few hundred works between them, so a
citation is often to a text that is not there, and an entry with fewer links
is better than one with links that lead nowhere."
  (when-let* ((corpora (ignore-errors (tei-corpora)))
              (c (seq-find (lambda (x)
                             (equal (plist-get x :id) corpus))
                           corpora))
              (a (assoc author (ignore-errors (tei-authors c)))))
    (and (assoc work (nth 2 a)) t)))


;; AND WHEN THE MENU IS DEFINED, which replaces the prefix whole and takes
;; every appended suffix with it.  The forms above stay: a reader may have
;; the base and not this suite's menu, and the entries belong there too.
;; Each append asks transient-get-suffix first, so twice is free.
;;;###autoload
(with-eval-after-load 'classicist
  (add-hook 'classicist-menu-defined-hook #'tei--add-to-diogenes-menu))

(provide 'tei-browser)
;;; tei-browser.el ends here
