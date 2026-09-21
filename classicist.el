;;; classicist.el --- Interface to diogenes -*- lexical-binding: t -*-

;; An interface to Peter Heslin's Diogenes
;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities
;;
;; Version: 0.1
;; Package-Requires: ((emacs "28.1") (diogenes "0.61"))

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

;; Agenda:
;; -  Windows?
;; -  Coptic?
;;   - select_authors:
;; - Browser Mode:
;;     - Make keybindings work in Evil Mode
;; - Info Manual

;;; Code:
(require 'cl-lib)
(require 'thingatpt)
(require 'transient)
(defun diogenes--theme-transient-keys (&rest _)
  "Keep the transient recurse key visible, following the current theme."
  (when (internal-lisp-face-p 'transient-key-recurse)
    (set-face-attribute 'transient-key-recurse nil
                        :foreground 'unspecified
                        :inherit 'font-lock-keyword-face)))

(with-eval-after-load 'transient (diogenes--theme-transient-keys))
(advice-add 'enable-theme :after #'diogenes--theme-transient-keys)
(advice-add 'diogenes :before #'diogenes--theme-transient-keys)
(require 'seq)

(require 'diogenes-lisp-utils)
(require 'diogenes-utils)
(require 'diogenes-perl-interface)
(require 'diogenes-user-interface)
(require 'classicist-browser)
;; The abbreviations LSJ and Lewis & Short use, generated from the dictionaries
;; themselves.  Optional: a reader without the file gets citations by number,
;; `tlg 0086/025 1053a15' instead of `Arist. Metaph. 1053a15', and nothing
;; fails.  `require' with NOERROR for that reason.
(require 'diogenes-abbreviations nil t)
(require 'diogenes-search)
(require 'classicist-morphology)
(require 'diogenes-complete)
(require 'diogenes-dict-faces)

;; The dictionary modules, loaded for everyone so that configuring a
;; dictionary is enough to have it.  Loading them here is NOT a declaration
;; that the user has any of them: `classicist--loading-bundle' is what lets
;; each module tell this from having been required by the user, which IS a
;; declaration.  A module already loaded -- required in an init file before
;; this file runs -- is untouched by the `require' below, `require' being a
;; no-op once the feature is present, so its own answer stands.
(let ((classicist--loading-bundle t))
  (require 'diogenes-old)
  (require 'diogenes-tll)
  (require 'diogenes-montanari)
  (require 'diogenes-cambridge)
  (require 'diogenes-bdag)
  (require 'diogenes-passow)
  (require 'diogenes-bailly)
  (require 'diogenes-bailly-pdf)
  (require 'diogenes-gaffiot)
  (require 'diogenes-gaffiot-pdf)
  (require 'diogenes-pape)
  (require 'diogenes-dge)
  (require 'diogenes-georges)
  (require 'diogenes-georges-pdf)
  (require 'diogenes-tgl))

(require 'diogenes-cheatsheet)
;; Evil integration: does nothing unless evil is loaded, and nothing to a
;; mode whose initial state the user has chosen, so it is required rather
;; than left for an init file to remember.  Unlike `diogenes-purpose' and
;; `diogenes-doom', which change where buffers appear and are therefore a
;; choice, this only hands back keys that evil would otherwise swallow.
(require 'diogenes-evil)
;; window-purpose integration: does nothing unless window-purpose is loaded.
;; An ordinary package that anyone may use -- Spacemacs enables it for
;; everyone, which is how most people meet it -- so this is required here
;; rather than left to an init file, as `diogenes-evil' is.  Without it
;; purpose has no entry for a lookup buffer and shows one in the window you
;; were reading in.
(require 'diogenes-purpose)
;; Presets: a directory of files, each a set of settings, switched between with
;; `M-x diogenes-load-preset'.  Does nothing until there is a preset to load.
(require 'diogenes-presets)

;; The focus keys, once the maps they go in exist.  Each mode's file may load
;; at any time -- a viewer's not until a scan is opened -- so the installer is
;; run after each rather than once and hopefully late enough.
(dolist (feature '(classicist-morphology classicist-browser classicist-lookup diogenes-search
                   diogenes-corpora diogenes-forms diogenes-pdf-search))
  (with-eval-after-load feature
    (when (fboundp 'classicist-install-focus-keys)
      (classicist-install-focus-keys))))
(require 'diogenes-pdf-search)
(diogenes-pdf-search-setup-keys)
;(require 'diogenes-window)
(require 'diogenes-legacy)
(require 'classicist-installation) ; is this set up, and if not what to say
(require 'classicist-windows)      ; where a buffer goes

(defgroup diogenes nil
  "Interface to P. Heslin's Diogenes."
  :group 'tools)


(defcustom diogenes-path nil
  "Path to the Diogenes installation."
  :type 'directory
  :group 'diogenes)


(defcustom diogenes-lexicon-files
  '(("greek" "grc.lsj.logeion.xml" "grc.lsj.xml")
    ("latin" "lat.ls.perseus-eng1.xml" "lat.ls.xml"))
  "Filenames to try for each language\='s lexicon, in order.

MORE THAN ONE NAME, because the same data ships under different ones.  The
Linux build produces grc.lsj.logeion.xml and lat.ls.perseus-eng1.xml; the
macOS app bundle carries grc.lsj.xml and lat.ls.xml.  A reader on a Mac was
told the Greek lexicon could not be found while it sat in that directory
under a shorter name -- and the Latin name was not an option at all, being
written into the code, so there was nothing to set.

The first that exists is used."
  :type '(alist :key-type string :value-type (repeat string))
  :group 'diogenes)

(defun diogenes--path ()
  (if diogenes-path
      (expand-file-name diogenes-path)
    (error "diogenes-path is not set!
Please set it to the root directory of your Diogenes installation!")))


(defun diogenes--perseus-path ()
  (directory-file-name (file-name-concat (diogenes--path)
					 "dependencies"
					 "data")))

(defun diogenes--dict-file (lang)
  "The lexicon file for LANG: the first name in `diogenes-lexicon-files\='
that exists, or the first name whatever happens.

THE FIRST THAT EXISTS, because the same data ships under different names --
see the option.  Falling back to the first rather than to nil so that a
reader who has none of them is told which was looked for, the checker and
the warnings both naming the file."
  (let ((names (cdr (assoc lang diogenes-lexicon-files))))
    (unless names
      (error "Undefined language %s" lang))
    (let ((dir (diogenes--perseus-path)))
      (or (seq-find #'file-exists-p
                    (mapcar (lambda (n) (file-name-concat dir n)) names))
          (file-name-concat dir (car names))))))

(defun classicist--tell-the-base-its-lexicon-name ()
  "Set the base\='s own option to the Greek lexicon that is there.

THE BASE HAS ITS OWN COPY of the lookup and its own validator, and both read
`diogenes-preferred-lsj-file\=', whose default is the name the Linux build
produces.  The macOS app ships the same data as grc.lsj.xml, so on a Mac the
base warned at startup and looked in the wrong place afterwards.

AND AN OVERRIDE WOULD NOT HELP.  The validator is top-level code: it runs
while diogenes.el is loading, before any `with-eval-after-load\=' can advise
anything.  Setting the option is the one thing that reaches it, and it reaches
the base\='s own lookup as well.

Only where the default is absent and another name is there, so a reader who
set it themselves is left alone."
  (when (and (boundp 'diogenes-preferred-lsj-file)
             (not (file-exists-p
                   (file-name-concat (diogenes--perseus-path)
                                     diogenes-preferred-lsj-file))))
    (when-let* ((found (seq-find
                        #'file-exists-p
                        (mapcar
                         (lambda (n)
                           (file-name-concat (diogenes--perseus-path) n))
                         (cdr (assoc "greek" diogenes-lexicon-files))))))
      (setq diogenes-preferred-lsj-file (file-name-nondirectory found)))))

;; AT LOAD AND AGAIN WHEN THE BASE LOADS, whichever of the two is first: the
;; option is right by the time anything reads it.  No cookie -- an autoloaded
;; form cannot name a function in its own file, and this one has to.
(classicist--tell-the-base-its-lexicon-name)

(with-eval-after-load 'diogenes
  (classicist--tell-the-base-its-lexicon-name))


;;; Validate that all data is present
(unless (file-exists-p (file-name-concat (diogenes--path)
					 "server"
					 "Diogenes"
					 "Base.pm"))
  (warn "Could not find a working Diogenes installation in %s"
	 (diogenes--path)))

(mapc (lambda (lang)
	(unless (file-exists-p (diogenes--dict-file lang))
	  (warn "Could not find %s lexicon at %s."
		 lang (diogenes--dict-file lang))))
      '("greek" "latin"))

(mapc (lambda (file)
	(unless (file-exists-p (file-name-concat (diogenes--perseus-path)
						 file))
	  (warn "Could not find %s in %s. Did you build them?"
		 file (diogenes--perseus-path))))
      '("greek-analyses.txt" "greek-lemmata.txt"
	"latin-analyses.txt" "latin-lemmata.txt"))

(defconst diogenes--corpora
  '(("phi" . "PHI Latin Corpus")
    ("tlg" . "TLG Texts")
    ("ddp" . "Duke Documentary Papyri")
    ("ins" . "Classical Inscriptions")
    ("chr" . "Christian Inscriptions")
    ("misc" . "Miscellaneous PHI Texts")
    ("cop" . "PHI Coptic Texts")
    ("bib" . "TLG Bibliography"))
  "Alist of the corpora that are supported by Diogenes.
The form is (ABBREV . FULL-NAME")

(defconst diogenes--corpora-abbrevs
  (mapcar #'car diogenes--corpora)
  "The abbreviations of the corpora supported by Diogenes.")

(defconst diogenes--corpora-names
  (mapcar #'cdr diogenes--corpora)
  "The names of the corpora supported by Diogenes.")

;;; SEARCH
;;;###autoload
(defun classicist-search-tlg (options-or-pattern
			    &optional author-plist prefix)
  "Search for a phrase in the Greek TLG database.
Uses the Diogenes Perl Module."
  (interactive "i\ni\np")
  (diogenes--search-database "tlg" options-or-pattern author-plist prefix))

;;;###autoload
(defun classicist-search-phi (options-or-pattern
			    &optional author-plist prefix)
  "Search for a phrase in the Latin PHI database.
Uses the Diogenes Perl Module."
  (interactive "i\ni\np")
  (diogenes--search-database "phi" options-or-pattern author-plist prefix))

;;;###autoload
(defun classicist-search-ddp (options-or-pattern
			    &optional author-plist prefix)
  "Search for a phrase in the Duke Documentary Papyri.
Uses the Diogenes Perl module."
  (interactive "i\ni\np")
  (diogenes--search-database "ddp" options-or-pattern author-plist prefix))

;;;###autoload
(defun classicist-search-ins (options-or-pattern
			    &optional author-plist prefix)
  "Search for a phrase in the Classical Inscriptions Database.
Uses the Diogenes Perl module."
  (interactive "i\ni\np")
  (diogenes--search-database "ins" options-or-pattern author-plist prefix))

;;;###autoload
(defun classicist-search-chr (options-or-pattern
			    &optional author-plist prefix)
  "Search for a phrase in the Christian Inscriptions Database.
Uses the Diogenes Perl module."
  (interactive "i\ni\np")
  (diogenes--search-database "chr" options-or-pattern author-plist prefix))

;;;###autoload
(defun classicist-search-misc (options-or-pattern
			    &optional author-plist prefix)
  "Search for a phrase in the Miscellaneous PHI Texts Database.
Uses the Diogenes Perl module."
  (interactive "i\ni\np")
  (diogenes--search-database "misc" options-or-pattern author-plist prefix))

;;;###autoload
(defun classicist-search-cop (options-or-pattern
			    &optional author-plist prefix)
  "Search for a phrase in the PHI Coptic Texts Database.
Uses the Diogenes Perl module."
  (interactive "i\ni\np")
  (diogenes--search-database "cop" options-or-pattern author-plist prefix))


;;; DUMP
;;;###autoload
(defun classicist-dump-tlg (&optional author work)
  "Dump a work from the Greek TLG database in its entirety.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--dump-from-database "tlg" author work))

;;;###autoload
(defun classicist-dump-phi (&optional author work)
  "Dump a work from the Latin PHI database in its entirety.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--dump-from-database "phi" author work))

;;;###autoload
(defun classicist-dump-ddp (&optional author work)
  "Dump a work from the Duke Documentary Database in its entirety.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--dump-from-database "ddp" author work))

;;;###autoload
(defun classicist-dump-ins (&optional author work)
  "Dump a work from the Classical Inscriptions Database in its entirety.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--dump-from-database "ins" author work))

;;;###autoload
(defun classicist-dump-chr (&optional author work)
  "Dump a work from the Christian Inscriptions Database in its entirety.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--dump-from-database "chr" author work))

;;;###autoload
(defun classicist-dump-misc (&optional author work)
  "Dump a work from the Miscellaneous PHI Texts Database in its entirety.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--dump-from-database "misc" author work))

;;;###autoload
(defun classicist-dump-cop (&optional author work)
  "Dump a work from the PHI Coptic Texts Database in its entirety.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--dump-from-database "cop" author work))


;;; BROWSE
;;;###autoload
(defun classicist-browse-tlg (&optional author work)
  "Browse a specific passage in a work from the Greek TLG database.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--browse-database "tlg" author work))

;;;###autoload
(defun classicist-browse-phi (&optional author work)
  "Browse a work from the Latin PHI database.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--browse-database "phi" author work))

;;;###autoload
(defun classicist-browse-ddp (&optional author work)
  "Browse a work from the Duke Documentary Database.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--browse-database "ddp" author work))

;;;###autoload
(defun classicist-browse-ins (&optional author work)
  "Browse a work from the Classical Inscriptions Database.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--browse-database "ins" author work))

;;;###autoload
(defun classicist-browse-chr (&optional author work)
  "Browse a work from the Christian Inscriptions Database.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--browse-database "chr" author work))

;;;###autoload
(defun classicist-browse-misc (&optional author work)
  "Browse a work from the Miscellaneous PHI Texts  Database.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--browse-database "misc" author work))

;;;###autoload
(defun classicist-browse-cop (&optional author work)
  "Browse a work from the  PHI Coptic Texts Database.
Uses the Diogenes Perl module."
  (interactive)
  (classicist--browse-database "cop" author work))


;;; DICTIONARY LOOKUP
;;
;; Each of these four goes to the dictionary Diogenes searches by default --
;; the LSJ in Greek, Lewis & Short in Latin -- and each will ask which
;; dictionary instead, given a prefix argument or
;; `diogenes-lookup-always-ask-dictionary\='.  The choice is among whatever
;; has registered itself for that language: Bailly, Pape and the DGE in
;; Greek, Gaffiot and Georges in Latin.
;;
;; Useful for a word the default dictionary does not carry, and for reading
;; a Greek word in German or French rather than in English.

;;;###autoload
(defun diogenes-lookup-greek (word &optional dictionary)
  "Search for a greek word in the LSJ Greek Dictionary.
Accepts both Unicode and Beta Code as input.

With a prefix argument, ask which Greek dictionary to search instead; see
`diogenes-lookup-always-ask-dictionary\=' to be asked every time."
  (interactive (classicist--lookup-read-args "greek" "Search LSJ for: "))
  (if dictionary
      (classicist--lookup-word-in-dictionary word dictionary)
    (classicist--lookup-dict word "greek")))

;;;###autoload
(defun diogenes-lookup-latin (word &optional dictionary)
  "Search for a latin word in the Lewis & Short Latin Dictionary.

With a prefix argument, ask which Latin dictionary to search instead; see
`diogenes-lookup-always-ask-dictionary\=' to be asked every time."
  (interactive (classicist--lookup-read-args "latin" "Search Lewis & Short for: "))
  (if dictionary
      (classicist--lookup-word-in-dictionary word dictionary)
    (classicist--lookup-dict word "latin")))

;;; MORPHEUS PARSING
;;;###autoload
(defun diogenes-parse-and-lookup-greek (word &optional dictionary)
  "Try to parse a greek word and look it up.

With a prefix argument, ask which Greek dictionary to show it in.  The word
is parsed either way -- an inflected form reaches its lemma -- but a chosen
dictionary is reached by that lemma rather than by the offset Diogenes
recorded, there being no offset for any dictionary but its own."
  (interactive (classicist--lookup-read-args "greek" "Parse greek word: "))
  (if dictionary
      (classicist--lookup-word-in-dictionary word dictionary t)
    (classicist--parse-and-lookup (diogenes--greek-ensure-beta word)
				"greek")))

;;;###autoload
(defun diogenes-parse-and-lookup-latin (word &optional dictionary)
  "Try to parse a latin word and look it up.

With a prefix argument, ask which Latin dictionary to show it in; see
`diogenes-parse-and-lookup-greek\=' on what that changes."
  (interactive (classicist--lookup-read-args "latin" "Parse latin word: "))
  (if dictionary
      (classicist--lookup-word-in-dictionary word dictionary t)
    (classicist--parse-and-lookup word "latin")))

;;;###autoload
(defun diogenes-parse-greek (query)
  "Parse a greek word and display the results.
QUERY is interpreted as a regular expression which must match the forms."
  (interactive (list (read-from-minibuffer "Parse Greek word: "
					   (thing-at-point 'word t))))
    (classicist--parse-and-show (diogenes--greek-ensure-beta query)
			      "greek"))

;;;###autoload
(defun diogenes-parse-latin (query)
  "Parse a latin word and display the results.
QUERY is interpreted as a regular expression which must match the forms."
  (interactive (list (read-from-minibuffer "Parse Latin word: "
					   (thing-at-point 'word t))))
  (classicist--parse-and-show query "latin"))

;;;###autoload
(defun diogenes-show-all-forms-greek (lemma)
  "Show all attested forms of a Greek lemma."
  (interactive (list (diogenes-read-lemma "greek" "Show all forms of: ")))
  (classicist--show-all-forms (diogenes--greek-ensure-beta lemma) "greek"))

;;;###autoload
(defun diogenes-show-all-forms-latin (lemma)
  "Show all attested forms of a Latin lemma."
  (interactive (list (diogenes-read-lemma "latin" "Show all forms of: ")))
  (classicist--show-all-forms lemma "latin"))

;;;###autoload
(defun diogenes-show-all-lemmata-greek (query)
  "Show all Greek lemmata and forms that match QUERY."
  (interactive (list (diogenes-read-lemma
                      "greek" "Show all lemmata matching: ")))
  (classicist--show-all-lemmata (diogenes--greek-ensure-beta query) "greek"))

;;;###autoload
(defun diogenes-show-all-lemmata-latin (query)
  "Show all Latin lemmata and forms that match QUERY."
  (interactive (list (diogenes-read-lemma
                      "latin" "Show all lemmata matching: ")))
  (classicist--show-all-lemmata query "latin"))


;;; UTILITIES
;;;###autoload
(defun diogenes-utf8-to-beta (str)
  "Convert greek beta code to utf-8.
If a region is active, convert the contents of the region in place;
otherwise, prompt the user for input."
  (interactive "i")
  (cond (str (diogenes--utf8-to-beta str))
	((use-region-p) (translate-region (point) (mark)
					  diogenes--utf8-to-beta-table))
	(t (let ((str (read-from-minibuffer "Convert to Greek Beta Code: "
					    nil nil nil nil
					    (thing-at-point 'word t))))
	     (message "%s" (diogenes-utf8-to-beta str))))))

;;;###autoload
(defun diogenes-beta-to-utf8 (str)
  "Convert greek unicode to beta code.
If a region is active, convert the contents of the region in place;
otherwise, prompt the user for input."
  (interactive "i")
  (cond (str (diogenes--beta-to-utf8 str))
	((use-region-p) (let ((start (min (point) (mark)))
			      (end (max (point) (mark))))
			  (translate-region start end diogenes--beta-to-utf8-table)
			  (replace-regexp-in-region "σ\\b\\|σ$" "ς" start end)))
	(t (let ((str (read-from-minibuffer "Convert from Greek Beta Code: "
					    nil nil nil nil
					    (thing-at-point 'word t))))
	     (message "%s" (diogenes--beta-to-utf8 str))))))

;;;###autoload
(defun diogenes-strip-diacritics (start end)
  "Remove all diacritics in the active region."
  (interactive "r")
  (when (region-active-p)
    (let ((stripped (diogenes--strip-diacritics (buffer-substring start end))))
      (delete-region start end)
      (insert stripped))))

;;;###autoload
(defun diogenes-ol-to-ad (ol)
  "Converts Ol. to A.D."
  (interactive "nPlease enter the Olypiad: ")
  (let ((ad (diogenes--ol-to-ad ol)))
    (message "%s – %s"
	     (diogenes--bc-and-ad ad)
	     (diogenes--bc-and-ad (let ((last-year (+ ad 3)))
				    (if (zerop last-year) 1
				      last-year))))))

;;;###autoload
(defun diogenes-ad-to-ol (ad)
  "Converts A.D. to Ol."
  (interactive "nPlease enter a year: ")
  (when (zerop ad)
    (error "There is no year 0!"))
  (let ((year (+ ad (if (< ad 0) 780 779))))
    (message "Ol. %d/%d" (/ year 4)
	     (1+ (mod year 4)))))


;;; DISPATCHER
(transient-define-prefix diogenes-morphology-greek ()
  "Dispatcher for the Diogenes' Greek morphology tool collection."
  ["Greek Morphology Tools"
   ("a" "Show all possible analyses matching query" diogenes-parse-greek)
   ("f" "Show all attested forms of lemma" diogenes-show-all-forms-greek)
   ("l" "Show all lemmata and their forms matching query"
    diogenes-show-all-lemmata-greek)])

(transient-define-prefix diogenes-morphology-latin ()
  "Dispatcher for the Diogenes' Latin morphology tool collection."
  ["Latin Morphology Tools"
   ("a" "Show all possible analyses matching query" diogenes-parse-latin)
   ("f" "Show all attested forms of lemma" diogenes-show-all-forms-latin)
   ("l" "Show all lemmata and their forms matching query"
    diogenes-show-all-lemmata-latin)])

;; THE AUTOLOAD NAMED THE BASE'S FILE, which is where this command used to
;; live -- so C-c d loaded diogenes.el and got ITS prefix, unguarded, while
;; the guarded one below waited in a file nothing had loaded.  SEARCH,
;; BROWSE and DUMP therefore showed with texts asleep.
;;
;; The same race as the twenty-one commands, and here written out in the
;; cookie rather than left to filename order.
;;;###autoload (autoload 'classicist-define-menu "classicist")
;;;###autoload (autoload 'diogenes "classicist" nil t)
;; DEFINED IN A FUNCTION, AND THE FUNCTION CALLED WHEN THE BASE HAS
;; LOADED.  Both packages define a `diogenes' transient and the later
;; definition wins -- which came down to the package manager: straight
;; loaded this suite last and a reader saw ours, package.el activates
;; alphabetically and the base's landed on top.
;;
;; A REQUIRE WOULD NOT DO IT.  Loading this file when the base loads
;; makes our prefix run EARLIER, not later: the base is part way
;; through its own file and defines its prefix after we have finished.
;; And the same form in our own autoloads can fire before `provide'
;; and recurse.
;;
;; The hook runs after the base by definition, so this is
;; deterministic under every manager.
(defvar classicist-menu-defined-hook nil
  "Run when `classicist-define-menu\=' has defined the menu.

WHY A HOOK AND NOT A GUESS.  Defining a transient prefix replaces it whole,
and with it every suffix anything had appended -- the Diorisis entries, the
annotated trees, the TEI corpora, all of which are appends.  They fired on
`classicist\=' and on `diogenes\=', which was a guess about when the prefix
was stable, and the guess became wrong the moment the definition moved into
a function called later than either.

So the definition says when it is done and the appends listen.  Each asks
`transient-get-suffix\=' before appending, so being run again costs nothing.")

(defun classicist-define-menu ()
  "Define the `diogenes\=' menu, this package\='s version of it.

Called from a `with-eval-after-load\=' below, so that it lands on top of
the base's own definition whichever of the two files loaded first.
Idempotent: defining a transient prefix again simply replaces it."
  (transient-define-prefix diogenes ()
    "Study Greek and Latin Texts with Peter Heslin's Diogenes.
  This is the main dispatcher function that starts the transient
  user interface."
    [["SEARCH"
      ;; ANY OF ITS MEMBERS, not `texts' alone: the appends from
      ;; diorisis.el and tei-browser.el land in this group, so asking
      ;; for `texts' hid the corpora that want no Diogenes data.
      :if (lambda () (or (classicist-feature-p 'texts) (classicist-feature-p 'diorisis) (classicist-feature-p 'treebank)))
      ("sg" "Search the Greek TLG"
       (lambda () (interactive) (transient-setup 'diogenes--search--select-mode nil nil
  					  :scope (list :type "tlg")))
       :transient transient--do-recurse :if (lambda () (classicist-feature-p 'texts)))
      ("sl" "Search the Latin PHI"
       (lambda () (interactive) (transient-setup 'diogenes--search--select-mode nil nil
  					  :scope (list :type "phi")))
       :transient transient--do-recurse :if (lambda () (classicist-feature-p 'texts)))
      ("sd" "Search the Duke Documentary Papyri"
       (lambda () (interactive) (transient-setup 'diogenes--search--select-mode nil nil
  					  :scope (list :type "ddp")))
       :transient transient--do-recurse :if (lambda () (classicist-feature-p 'texts)))
      ("si" "Search the Classical Inscriptions"
       (lambda () (interactive) (transient-setup 'diogenes--search--select-mode nil nil
  					  :scope (list :type "ins")))
       :transient transient--do-recurse :if (lambda () (classicist-feature-p 'texts)))
      ("sc" "Search the Christian Inscriptions"
       (lambda () (interactive) (transient-setup 'diogenes--search--select-mode nil nil
  					  :scope (list :type "chr")))
       :transient transient--do-recurse :if (lambda () (classicist-feature-p 'texts)))
      ("sm" "Search the Miscellaneous PHI Texts"
       (lambda () (interactive) (transient-setup 'diogenes--search--select-mode nil nil
  					  :scope (list :type "misc")))
       :transient transient--do-recurse :if (lambda () (classicist-feature-p 'texts)))]
     ["BROWSE"
      ;; ANY OF ITS MEMBERS, not `texts' alone: the appends from
      ;; diorisis.el and tei-browser.el land in this group, so asking
      ;; for `texts' hid the corpora that want no Diogenes data.
      :if (lambda () (or (classicist-feature-p 'texts) (classicist-feature-p 'diorisis) (classicist-feature-p 'tei-corpora)))
      ("bg" "Browse the Greek TLG" diogenes-browse-tlg :if (lambda () (classicist-feature-p 'texts)))
      ("bl" "Browse the Latin PHI" diogenes-browse-phi :if (lambda () (classicist-feature-p 'texts)))
      ("bd" "Browse the Duke Documentary Papyri" diogenes-browse-ddp :if (lambda () (classicist-feature-p 'texts)))
      ("bi" "Browse the Classical Inscriptions" diogenes-browse-ins :if (lambda () (classicist-feature-p 'texts)))
      ("bc" "Browse the Christian Inscriptions" diogenes-browse-chr :if (lambda () (classicist-feature-p 'texts)))
      ("bm" "Browse the Miscellaneous PHI Texts" diogenes-browse-misc :if (lambda () (classicist-feature-p 'texts)))]]
    [["MORPHOLOGY & DICTIONARY LOOKUP"
      :if (lambda () (classicist-feature-p 'lexica))
      ("lg" "Look up Greek word (LSJ; C-u to choose)" diogenes-lookup-greek)
      ("ll" "Look up Latin word (Lewis & Short; C-u to choose)"
       diogenes-lookup-latin)
      ("pg" "Try to parse and look up a Greek (C-u to choose)"
       diogenes-parse-and-lookup-greek)
      ("pl" "Try to parse and look up a Latin (C-u to choose)"
       diogenes-parse-and-lookup-latin)
      ("mg" "Greek morphology tools" diogenes-morphology-greek)
      ("ml" "Latin morphology tools" diogenes-morphology-latin)]
     ["DUMP AN ENTIRE WORK AS PLAIN TEXT"
      :if (lambda () (classicist-feature-p 'texts))
      ("dg" "Dump from the Greek TLG" diogenes-dump-tlg)
      ("dl" "Dump from the Latin PHI" diogenes-dump-phi)
      ("dd" "Dump from the Duke Documentary Papyri" diogenes-dump-ddp)
      ("di" "Dump from the Classical Inscriptions" diogenes-dump-ins)
      ("dc" "Dump from the Christian Inscriptions" diogenes-dump-chr)
      ("dm" "Dump from the Miscellaneous PHI Texts" diogenes-dump-misc)]]
    ;; The keys for going between the windows are NOT here.  This menu is for
    ;; STARTING things -- search a corpus, look a word up -- where going from one
    ;; Diogenes buffer to another is done while already in one, and `C-c C-b',
    ;; `C-c C-l', `C-c C-a' and `C-c C-e' are to hand there.  The cheatsheet lists
    ;; them under `Going between the windows and frames'.
    ["CUSTOM CORPORA"
      :if (lambda () (classicist-feature-p 'texts))
     ("c" "Manage custom search corpora" diogenes-manage-user-corpora)])
  ;; AND WHATEVER HAS SOMETHING TO APPEND.  The definition above replaced
  ;; the prefix whole and took every appended suffix with it, so this is the
  ;; moment they are wanted -- stated, rather than guessed at.
  (run-hooks 'classicist-menu-defined-hook))

;;;###autoload
;; AFTER THE BASE, whichever loaded first.  The autoload above reaches
;; `classicist-define-menu' by this file's own name, which is what an
;; autoload is for and does not recurse.
(with-eval-after-load 'diogenes
  (if (fboundp 'classicist-define-menu)
      (classicist-define-menu)
    ;; FROM THE AUTOLOADS, where this file has not loaded: naming the
    ;; function is enough, it being autoloaded itself.
    (ignore-errors (classicist-define-menu))))


;; And the mouse gestures a reader has asked for, which is nothing by default.
(with-eval-after-load 'classicist-browser
  ;; THE GESTURES A READER ASKED FOR, and only where the
  ;; browser is awake at all.
  (when (classicist-feature-p 'texts)
  (when (fboundp 'classicist-browser-install-mouse-keys)
    (classicist-browser-install-mouse-keys))
  (when (fboundp 'classicist-browser-install-turn-keys)
    (classicist-browser-install-turn-keys))))

;;;; --------------------------------------------------------------------
;;;; THE BASE'S OWN NAMES, POINTED HERE
;;;; --------------------------------------------------------------------

;; TWENTY-ONE COMMANDS THIS PACKAGE HAS ITS OWN VERSION OF, and a reader's
;; configuration, Diogenes' menu and everyone's muscle memory all name the
;; base's.  So the base's names are advised to reach ours.
;;
;; NOT A SECOND DEFUN, which is what this was.  Redefining a name works only
;; if the other definition came first, and across two packages that is the
;; order the autoload stubs were written -- filename order, in which
;; `diogenes' follows `classicist' and the base won.  A fresh Emacs got the
;; plain browser and the suite looked inert.  It had looked right here only
;; because a long session had pulled this file in last.
;;
;; AND AFTER THE BASE HAS LOADED, because advising a name the base has not
;; defined yet installs the advice on nothing.

;;;; --------------------------------------------------------------------
;;;; THE LEMMA SEARCH, GIVEN ITS OWN COMPLETION
;;;; --------------------------------------------------------------------

;; `diogenes--morphological-search' asks with a bare `read-from-minibuffer',
;; and this package has a reader that completes on the word list -- so the
;; prompt that most wants it was the one not using it.  A reader searching the
;; corpus for a lemma had no list, no frequencies and no way to check the
;; spelling, while the same reader looking a word up had all three.
;;
;; :filter-args IS THE SMALLEST THING THAT WORKS.  The base prompts only where
;; its LEMMA argument is nil, so filling it in beforehand leaves the search
;; itself untouched.

(defun classicist--search-lemma-args (args)
  "Fill in the lemma ARGS lack, with completion.
ARGS are `diogenes--morphological-search\='s: (TYPE &optional LEMMA AUTHORS).
Where LEMMA is there already -- a caller that knew it, or a second search of
the same word -- ARGS come back untouched."
  (if (or (cdr args) (not (fboundp 'diogenes-read-lemma)))
      args
    (let* ((type (car args))
           (lang (if (fboundp 'diogenes--probable-corpus-language)
                     (diogenes--probable-corpus-language type)
                   "greek")))
      (list type
            (diogenes-read-lemma
             lang
             (format "Lemma to search the %s for: " (upcase type)))))))

(defun classicist--install-search-lemma ()
  "Give the base's lemma search this package\='s completion.
Idempotent, and only where `lemmata\=' is awake -- the word list being a
hundred thousand lines and the index some megabytes, which a reader may
decline.  Without it they get Diogenes\=' own plain prompt."
  (when (and (or (not (fboundp 'classicist-feature-p))
                 (classicist-feature-p 'lemmata))
             (fboundp 'diogenes--morphological-search))
    (advice-add 'diogenes--morphological-search :filter-args
                #'classicist--search-lemma-args)))

(defun classicist--remove-search-lemma ()
  "Give the base\='s plain prompt back."
  (advice-remove 'diogenes--morphological-search
                 #'classicist--search-lemma-args))

(defconst classicist--overridden-commands
  (let (out)
    (dolist (family '("search" "dump" "browse"))
      (dolist (corpus '("tlg" "phi" "ddp" "ins" "chr" "misc" "cop"))
        (push (cons (intern (format "diogenes-%s-%s" family corpus))
                    (intern (format "classicist-%s-%s" family corpus)))
              out)))
    (nreverse out))
  "The base's command names, and ours that answer for them.
An alist of (THEIRS . OURS), built rather than written out: three families of
seven, and a list of twenty-one pairs typed by hand is twenty-one chances to
mistype one.")

(defun classicist-install-overrides ()
  "Point the base's browse, search and dump commands at ours.
Idempotent: `advice-add\=' with the same function is a no-op the second time.

ONLY WHERE `texts\=' IS AWAKE.  A reader who wants the corrections and not the
rest gets Diogenes\=' own commands, unadvised, which is what `texts\=' being
asleep should mean."
  (when (or (not (fboundp 'classicist-feature-p))
            (classicist-feature-p 'texts))
    (dolist (pair classicist--overridden-commands)
      (when (and (fboundp (car pair)) (fboundp (cdr pair)))
        (advice-add (car pair) :override (cdr pair))))
    ;; AND THE LEMMA SEARCH'S PROMPT, which is an argument filter rather than
    ;; an override but belongs to the same feature and the same moment.
    (classicist--install-search-lemma)))

(defun classicist-remove-overrides ()
  "Give the base's commands back.
What a redefinition could not do, and the reason this is advice."
  (interactive)
  (dolist (pair classicist--overridden-commands)
    (advice-remove (car pair) (cdr pair)))
  (classicist--remove-search-lemma))

;;;###autoload
(with-eval-after-load 'diogenes
  (if (fboundp 'classicist-install-overrides)
      (classicist-install-overrides)
    ;; FROM THE AUTOLOADS, where this file has not loaded: the pairs are
    ;; rebuilt here rather than read from the defconst above, so the form asks
    ;; nothing of its own file.  Ours are autoloaded, so naming them is
    ;; enough to reach them.
    (dolist (family '("search" "dump" "browse"))
      (dolist (corpus '("tlg" "phi" "ddp" "ins" "chr" "misc" "cop"))
        (let ((theirs (intern (format "diogenes-%s-%s" family corpus)))
              (ours (intern (format "classicist-%s-%s" family corpus))))
          (when (and (fboundp theirs) (fboundp ours))
            (advice-add theirs :override ours)))))
    ;; AND THE LEMMA SEARCH, where this file has not loaded: the filter is
    ;; autoloaded, so naming it is enough to reach it.
    (when (and (fboundp 'diogenes--morphological-search)
               (fboundp 'classicist--search-lemma-args))
      (advice-add 'diogenes--morphological-search :filter-args
                  #'classicist--search-lemma-args))))

(provide 'classicist)

;; AND `diogenes' TOO, which is not a shim.  Four `with-eval-after-load
;; \='diogenes\=' forms ask whether the Diogenes commands are available -- one
;; in `diogenes-presets.el\=' and three in the tei-browser repository -- and
;; that question means exactly what it always meant, because the commands
;; keep their names.  `classicist\=' is for anything that wants the suite;
;; `diogenes\=' goes on meaning what it meant.
(provide 'diogenes)

;;; classicist.el ends here
