# Installing it, and what to try first

Four platforms to try, and the fourth is the one nothing has been written for.

## What to run first, whichever Emacs

```
M-x classicist-check-base      ; are the nine patches there
M-x classicist-check-features  ; does every awake feature have what it wants
M-x diogenes-browse-tlg        ; does Perl answer
```

The first two answer without touching the corpora. The third is the first
thing that runs a subprocess, so it is where a missing Perl shows.

## Plain Emacs

`:vc` in `use-package` wants Emacs 30. On 29, `M-x package-vc-install` and
then a plain `use-package` with no `:vc`; on 28, clone the two repositories
and use `:load-path`.

## Doom

The block the builder writes is in two parts and says which file each belongs
to. `doom sync -u` after editing `packages.el`, and `doom doctor` if something
does not load.

Doom turns evil on unless `:editor evil` is removed from `init.el`, so the
evil key matters here where it does not elsewhere.

## Spacemacs

The layer entry is commented in the block the builder writes, because
`dotspacemacs-additional-packages` is a list a reader edits rather than a form
to paste. Uncomment it into the list.

Spacemacs asks at first start whether you want vim, emacs or hybrid, so
nothing here can presume the answer.

## Windows — nothing has been written for this

**Diogenes itself runs on Windows** and has for years: Heslin ships an
installer. **`diogenes.el` has never considered it.** There is no
`system-type` anywhere in the base, and `diogenes-perl-executable` defaults
to `"perl"` — whatever is on `PATH`, where a Windows Diogenes bundles its own
Perl that is not.

### The good news, from reading rather than trying

- **No `shell-command` anywhere** in the base or the suite. Every subprocess
  is `call-process` or `make-process` with the program as its own argument, so
  there is no shell quoting to go wrong — the commonest Windows failure in
  Emacs packages, and this does not have it.
- **`file-name-concat`**, not string concatenation, where paths are built —
  so the separator is the platform's.
- **`sqlite-available-p` is checked** before the Diorisis database is opened,
  with a message saying what is wanted. The official Windows builds of Emacs
  29 and later include sqlite3, so Diorisis should work.
- **The builder turns backslashes into forward slashes**, which Emacs accepts
  on Windows and which keeps a generated configuration readable.

### What to find out, in this order

**1. Where the bundled Perl is.** Install Diogenes, then look:

```
dir "C:\Program Files\Diogenes"
```

A `perl` directory in there is what a patch would look for. This is the one
thing a guess would get wrong, and the answer decides the shape of the patch.

**2. Whether Emacs can read SQLite.**

```
M-x ielm
(sqlite-available-p)
```

Nil means no Diorisis, whatever else works.

**3. Whether Perl is found.** `M-x diogenes-browse-tlg`. If it fails, set
`diogenes-perl-executable` to the bundled `perl.exe` by hand and try again —
that tells us the patch would work before the patch exists.

**4. What renders a PDF.** `diogenes-old-pdf-viewer` is `auto`, which uses
pdf-tools where it is available and `doc-view` otherwise. pdf-tools on Windows
wants `epdfinfo` built against poppler, which is the hardest single thing
here; `doc-view` wants Ghostscript, which has a plain installer. So install
Ghostscript and expect `doc-view`.

Nine of the sixteen dictionaries are scans, so this decides more than half of
them.

**5. The two symlinks in `tools/viewer`.** `arethusa` and `trees` are symlinks
to places outside the repository. Git on Windows checks a symlink out as a
text file containing its target unless developer mode is on, so the treebank
viewer will fail confusingly. Look at what those two are after a clone.

### What will not work, and is not worth chasing

**Morpheus** is a compiled C binary and there is no Windows build.
`classicist-morpheus-directory` stays empty and the word lists carry the
parsing, which is what they are for.

### The shape of a Windows configuration

    (setq diogenes-perl-executable "C:/Program Files/Diogenes/perl/bin/perl.exe")
    (setq diogenes-old-pdf-viewer 'doc-view)
    (setq classicist-morpheus-directory nil)
    (setq treebank-serve-viewer nil)

The first is a guess until step 1 is done. The rest follow from the steps
above, and all four belong in a `Windows` button beside `Fixes only` and
`Everything` once the first is known.

## What a Podman container is good for, and is not

Podman on Windows runs LINUX containers through WSL2, so a container says
nothing about Windows paths, `system-type`, or where a bundled Perl lives.

It is the right instrument for a different and useful question: **does this
work on a clean machine?** A Fedora container with Emacs 29, no dotfiles, and
the two packages installed from GitHub would say whether the recipes work and
whether anything quietly depends on a reader's own configuration.
