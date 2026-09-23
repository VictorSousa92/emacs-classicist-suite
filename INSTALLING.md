# Installing it, and what to try first

## Use the configuration builder

**Do not write the configuration by hand.** Open the builder:

**[classicist-builder.html][builder]** — or `tools/classicist-builder.html`
from a clone, in any browser.

It asks which Emacs you run, which operating system, which features you want
and where your files are, and writes a configuration that is correct for the
answers. Nothing is uploaded; it is one HTML file with no network calls.

It exists because there is more to get right than there looks. It knows which
of the three distributions takes `:vc`, which takes a straight recipe and which
takes a list you edit; it normalises Windows paths, where a hand-typed
backslash is eaten silently by Emacs and produces an error naming a directory
that looks almost right; it puts the settings that must precede the
`use-package` forms before them; and it emits the four extra settings Windows
needs. Every symbol it writes is checked against the source by `make check`,
so it cannot emit a name that no longer exists.

Then read the section below for your platform, and keep this file for when
something does not work. The [README][readme] is what the suite does and how to
configure it once installed.

## Contents

- [Use the configuration builder](#use-the-configuration-builder)
- [What to run first, whichever Emacs](#what-to-run-first-whichever-emacs)
- [Which Emacs](#which-emacs)
  - [Plain Emacs](#plain-emacs)
  - [Doom](#doom)
  - [Spacemacs](#spacemacs)
- [Linux](#linux)
- [macOS](#macos)
- [Windows](#windows)
  - [1. MSYS2, Emacs, and the tools](#1-msys2-emacs-and-the-tools)
  - [2. Diogenes, and its bundled Perl](#2-diogenes-and-its-bundled-perl)
  - [3. Forward slashes, always](#3-forward-slashes-always)
  - [4. The four settings](#4-the-four-settings)
  - [5. The trap: two homes](#5-the-trap-two-homes)
  - [6. Shortcuts](#6-shortcuts)
  - [What the five unknowns turned out to be](#what-the-five-unknowns-turned-out-to-be)
  - [Known limitations](#known-limitations)
- [What a Podman container is good for, and is not](#what-a-podman-container-is-good-for-and-is-not)

Three Emacs distributions on three operating systems, all of them tried.

## What to run first, whichever Emacs

```
M-x classicist-check-base      ; are the nine patches there
M-x classicist-check-features  ; does every awake feature have what it wants
M-x diogenes-browse-tlg        ; does Perl answer
```

The first two answer without touching the corpora. The third is the first
thing that runs a subprocess, so it is where a missing Perl shows.

## Which Emacs

### Plain Emacs

`:vc` in `use-package` wants Emacs 30. On 29, `M-x package-vc-install` and
then a plain `use-package` with no `:vc`; on 28, clone the two repositories
and use `:load-path`.

### Doom

The block the builder writes is in two parts and says which file each belongs
to. `doom sync -u` after editing `packages.el`, and `doom doctor` if something
does not load.

Doom turns evil on unless `:editor evil` is removed from `init.el`, so the
evil key matters here where it does not elsewhere.

### Spacemacs

The layer entry is commented in the block the builder writes, because
`dotspacemacs-additional-packages` is a list a reader edits rather than a form
to paste. Uncomment it into the list.

Spacemacs asks at first start whether you want vim, emacs or hybrid, so
nothing here can presume the answer.

## Linux

The straightforward case, and where the suite was developed.

Emacs from your distribution's packages, or a build of your own; 30 or later
for `:vc`. `git`, `python3` and `sqlite` are wanted, and all three are
ordinarily present already.

For the scanned dictionaries, `poppler` for pdf-tools or `ghostscript` for
`doc-view`; your package manager has both.

Nothing else is platform-specific. Paths are ordinary POSIX paths, `~` means
what you expect, and a GUI Emacs started from a desktop launcher inherits
enough environment for `git` and `python3` to be found.

## macOS

As Linux, with two things to know.

**Emacs**: Homebrew (`brew install --cask emacs`), MacPorts, or the
Emacs-for-Mac-OS-X builds. A GUI Emacs launched from `/Applications` inherits
almost no shell environment, so if `git` or `python3` are not found,
`exec-path-from-shell` is the usual remedy.

**Diogenes** installs as an application bundle, and `diogenes-path` is the
`Contents/` directory inside it, not the `.app`:

```elisp
(setq diogenes-path "/Users/you/Downloads/Diogenes.app/Contents/")
```

Several Emacsen can share one binary through small wrapper applications that
differ only in `--init-directory`, which is a tidy way to keep plain Emacs,
Doom and Spacemacs side by side. If you use one, the real binary is named
inside `YourEmacs.app/Contents/MacOS/`, and that is the path to pass
`--debug-init` to.

## Windows

Windows works. It needs more setting up than Linux or macOS, and one trap that
has nothing to do with this suite. Established on a clean machine: MSYS2's
mingw64 Emacs 30.2, Diogenes from its own installer.

### 1. MSYS2, Emacs, and the tools

Install [MSYS2](https://www.msys2.org/). Then, in the **MINGW64** shell — not
the plain MSYS one; the prompt must read `MINGW64`:

```
pacman -S mingw-w64-x86_64-emacs
pacman -S git
pacman -S mingw-w64-x86_64-python
```

The native MinGW build is the one to use. It understands `C:/` paths, and
unlike the official FSF build it can be given poppler, so pdf-tools is
buildable — which decides more than half the printed dictionaries, nine of
them being scans:

```
pacman -S mingw-w64-ucrt-x86_64-ghostscript      # doc-view
pacman -S mingw-w64-x86_64-poppler               # pdf-tools
```

**`git` comes from MSYS2's own `usr/bin`**, there being no mingw64 package for
it. That works, but do not put that directory on Emacs' `exec-path` — see
step 4.

Some packages have been dropped from the `mingw64` environment in favour of
`ucrt64`. `pacman -Ss NAME` says which prefixes a package has; ripgrep and fd,
which Doom wants, are `mingw-w64-ucrt-x86_64-*` and work fine from there since
they are standalone binaries.

### 2. Diogenes, and its bundled Perl

Install [Diogenes][diogenes] with its own Windows installer. It
bundles a **Strawberry Portable Perl** inside its own directory:

```
C:\Program Files (x86)\Diogenes\strawberry\perl\bin\perl.exe
```

That is the Perl that must be used. MSYS2's own Perl has none of Diogenes'
modules, and `diogenes-perl-executable` defaults to `"perl"` — whatever is on
`PATH`, which on Windows is the wrong one or none at all.

Diogenes' own modules are at `Diogenes/server/` and the CPAN modules it needs
at `Diogenes/dependencies/CPAN/`. Both belong on `PERL5LIB`.

### 3. Forward slashes, always

Emacs reads a string before it ever sees a file name, and `\P` and `\D` are not
escapes it knows, so it drops them silently:

```
"c:/Program Files (x86)\Diogenes\dependencies"
    becomes  c:/Program Files (x86)Diogenesependencies
```

and the error names a directory that looks almost right. Write every path with
forward slashes, UNC shares included — `//host/share/path`, not
`\\host\share\path`. The builder normalises this; typing a path into your init
file by hand does not.

### 4. The four settings

A GUI Emacs on Windows inherits no shell environment. Nothing is on `PATH` that
was not put there deliberately — not Diogenes' Perl, and not `git`, which
`:vc` shells out to, which fails as

```
File is missing: Searching for program, No such file or directory, git
```

Tick the Windows box in the builder and it writes all four. By hand, they are:

```elisp
(setq diogenes-path "c:/Program Files (x86)/Diogenes/")
(setq diogenes-perl-executable
      "c:/Program Files (x86)/Diogenes/strawberry/perl/bin/perl.exe")
(dolist (d '("c:/Program Files (x86)/Diogenes/strawberry/perl/bin"
             "c:/Program Files (x86)/Diogenes/strawberry/perl/site/bin"
             "c:/Program Files (x86)/Diogenes/strawberry/c/bin"))
  (add-to-list 'exec-path d)
  (setenv "PATH" (concat d ";" (getenv "PATH"))))
(setenv "PERL5LIB"
        (concat "c:/Program Files (x86)/Diogenes/server;"
                "c:/Program Files (x86)/Diogenes/dependencies/CPAN"))
```

**All of it above the `use-package` forms.** `:vc` loads the base while
installing it, before any `:init` has run, and the base raises at load if
`diogenes-path` is unset.

**`PERL5LIB` is the one that is easy to miss.** Without it Perl starts, fails
to find `Diogenes/Base.pm`, and the base reports only

```
Perl exited with errors, no data received!
```

which names nothing useful. To see the real error:

```
perl -e "use Diogenes::Base; print 'ok'"
```

with `PERL5LIB` set in the shell.

**For `git`, prefer `c:/msys64/mingw64/bin` and `c:/msys64/ucrt64/bin`**, or
install Git for Windows so it is on the system `PATH`. Do **not** add
`c:/msys64/usr/bin`: those are Cygwin-style binaries that do not know `c:`
names a drive. `gpg` handed a path from there prefixes its own POSIX home to
it —

```
gpg: keyblock resource '/home/You/c:/Users/You/.config/.../pubring.kbx'
```

— and every signature check fails.

### 5. The trap: two homes

MSYS2's `$HOME` is `C:\msys64\home\YourName`. A native Windows Emacs resolves
`~` to your Windows profile, `C:\Users\YourName`. **They are different
directories**, and this is the single largest source of confusion here.

Plain Emacs is unaffected, because its init directory is passed explicitly and
its paths are absolute. **Doom and Spacemacs are not**: both compute their own
directories from `~`, so an install under the MSYS2 home is invisible to them.
Doom then fails during startup and Emacs carries on with defaults — which looks
exactly like a plain Emacs, with no error in sight.

So:

- Clone Doom and Spacemacs under `C:/Users/YourName/.config/`.
- Doom looks for its private config at `$DOOMDIR`, then `~/.config/doom`, then
  `~/.doom.d`, and on Windows also `AppData/Roaming/.doom.d`. Set `DOOMDIR`
  identically for the shell **and** for the shortcut, or put the config where
  Doom already looks — otherwise `doom sync` builds one configuration while
  Emacs reads another, and the modeline reports three modules where you
  configured twenty-three.
- `doom` itself is not on `PATH`; it is `.config/emacs-doom/bin/doom`.

### 6. Shortcuts

One binary, three init directories:

```
C:\msys64\mingw64\bin\runemacs.exe --init-directory=C:/Users/YourName/.config/emacs-vanilla
```

`runemacs.exe` rather than `emacs.exe`, so no console window lingers. Set
**Start in** to your home: an Emacs launched from a directory that no longer
exists dies in `normal-top-level` with `void-variable
auto-save-list-file-prefix`, which looks like a broken installation and is not.

To make all three at once, in PowerShell:

```powershell
$e = "C:\msys64\mingw64\bin\runemacs.exe"
$w = New-Object -ComObject WScript.Shell
foreach ($n in "vanilla","doom","spacemacs") {
  $s = $w.CreateShortcut("$env:USERPROFILE\Desktop\Emacs $n.lnk")
  $s.TargetPath = $e
  $s.Arguments = "--init-directory=C:/Users/YourName/.config/emacs-$n"
  $s.WorkingDirectory = "C:\Users\YourName"
  $s.Save()
}
```

### What the five unknowns turned out to be

This section used to be a list of things to find out. The answers:

| | |
|---|---|
| Where the bundled Perl is | `Diogenes/strawberry/perl/bin/perl.exe`, with modules at `server/` and `dependencies/CPAN/` |
| Whether Emacs reads SQLite | yes — `(sqlite-available-p)` is `t` on the MSYS2 build, so Diorisis works |
| Whether Perl is found | not without the four settings above; with them, `diogenes-browse-tlg` answers |
| What renders a PDF | Ghostscript is not installed by default and `doc-view` needs it; poppler and pdf-tools are buildable under MSYS2, unlike the FSF build |
| The two symlinks in `tools/viewer` | there are none. `serve.py` answers `/trees/NAME.xml` from wherever `--trees` points; the viewer's own README says no symlink is wanted |

### Known limitations

Windows-specific. Morpheus is not among them: it ships no binary and is built
from source on every platform, and the README says how.

- **Descriptor limits** are lower than on Unix, and a first-time package sync
  of a large distribution can exhaust them — `Creating process pipe, Too many
  open files`. Restarting resumes; run one distribution's sync at a time.
- **Reading a corpus over a network share is slow**, and over an RDP redirected
  drive it is unusable: the TLG index is thousands of small reads. A redirected
  drive also disappears with the session, so paths pointing at one are dead
  after a restart. Keep the corpora on a local disk.

## What a Podman container is good for, and is not

Podman on Windows runs LINUX containers through WSL2, so a container says
nothing about Windows paths, `system-type`, or where a bundled Perl lives.

It is the right instrument for a different and useful question: **does this
work on a clean machine?** A Fedora container with Emacs 29, no dotfiles, and
the two packages installed from GitHub would say whether the recipes work and
whether anything quietly depends on a reader's own configuration.

[builder]: https://victorsousa92.github.io/emacs-classicist-suite/tools/classicist-builder.html
[diogenes]: https://d.iogen.es/
[readme]: README.md
