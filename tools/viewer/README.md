# A treebank viewer of one's own

`w` in the tree editor opens a tree in a viewer that draws it as the printed
diagrams do. This is that viewer: one HTML page, Arethusa's own prebuilt
files, and any static server.

## Which library, and why this one

Two exist and they are not alternatives.

**`treebank-react`** displays a tree and does not edit it, and it is a React
library: using it means a React application and a webpack build, since it
ships no browser bundle. For looking at a tree you already have drawn in
Emacs, that is a great deal of machinery for a second opinion about layout.

**`arethusa-widget`** embeds the whole Arethusa annotation environment —
the tree, the morphology panel, dragging arcs, the relation menus. And its
`ArethusaWrapper` turns out to be a thin shim over a global that its own
prebuilt loader installs:

```javascript
new Arethusa().on(id).from(url).with(config).start({ doc: doc, chunk: chunk })
```

So **no React and no build are needed**: `index.html` beside this file is that
shim, written out, with the widget's own default config inlined and pointed at
the Greek morphology service rather than the Latin one.

## Installing it

Node is wanted once, to fetch the prebuilt files; nothing is compiled.

```fish
cd ~/diogenes-folder/tei-browser/tools/viewer
npm install arethusa-widget
ln -s node_modules/arethusa-widget/dist/arethusa ./arethusa
```

`dist/arethusa` is Arethusa itself, built: some megabytes of JavaScript, CSS
and templates. If `npm install` brings no `dist` — the package has shipped it
for every published version so far, but a future one might not — the widget's
own `build.sh` builds it in Docker, which clones Arethusa and takes a while.

## Running it

```fish
cd ~/diogenes-folder/tei-browser/tools/viewer
python3 serve.py --trees ~/org/trees
```

`serve.py` serves this page and Arethusa's files, answers `/trees/NAME.xml`
from wherever `--trees` points, **answers Arethusa's page-relative paths**,
and **accepts a write**: `PUT` or `POST` to
`/trees/NAME.xml` replaces that tree, keeping the old one beside it as
`NAME.xml~`. It binds to 127.0.0.1, refuses anything that is not a `.xml`
under `/trees`, and logs each request on one line.

No symlink is wanted: `--trees` is the directory, and it should be the same as
`tei-diorisis-treebank-directory` in Emacs.

**On the page-relative paths.** Most of Arethusa's templates are compiled into
its JavaScript, but a few are fetched at run time — and fetched relative to the
*page*, as `./js/arethusa.core/templates/…`, rather than to the base its loader
was given. They therefore arrive as `/js/…` while the files sit under
`/arethusa/js/…`, and Angular reports a template it cannot load, which stops
whatever was being rendered. `serve.py` answers `/js/`, `/css/`, `/configs/`,
`/vendor/`, `/fonts/`, `/i18n/`, `/dist/` and `/templates/` from the Arethusa
directory as well, when the viewer's own directory has nothing there. Which is
why `python3 -m http.server` is no longer enough.

## Editing in both

The point of the write endpoint is that one file can be open in both editors:

- **Emacs writes** with `s`, and the viewer shows the new tree when its page
  is reloaded.
- **Emacs rereads** by itself when something else writes the file —
  `tei-diorisis-tree-watch`, which is on by default and uses `file-notify`, so
  a save elsewhere appears in the table and the drawing at once. Where the
  buffer has unsaved edits of its own it asks first, two editors on one file
  being reconcilable only by somebody who knows which edit was meant. `g`
  rereads by hand.
- **Arethusa writes** once its save is pointed at this endpoint, which is the
  one piece not yet wired: see below.

## Arethusa's own save, wired

`TreebankPersister` is the service that writes a treebank back, and it is
configured now: a `treebankSave` resource whose route is **this tree's own
URL**, and `main.persisters` naming the persister. Arethusa posts the document
as `text/xml`, `serve.py` writes it and keeps the old version as `NAME.xml~`,
and the Emacs editor — which watches the file — rereads it at once.

So all three ways at a tree write the same file: the table in Emacs, the
drawing beside it, and Arethusa.

The route carries no `:doc` parameter on purpose. One would leave Arethusa to
fill it from its own idea of the document's name; the page already knows which
file it opened.

## How that was found

The installed build has the machinery — `saver`, `persister` and
`exitHandler` are all in `arethusa.min.js` — but the names it expects in a
configuration are not documented anywhere I can find. These two commands say
what they are:

```fish
grep -o '"[A-Za-z]*Persister"' arethusa/arethusa.min.js | sort -u
python3 -c "import json; d = json.load(open('arethusa/configs/aldt2grc.json')); print(json.dumps(d.get('main', {}), indent=1))"
```

With those, the page gains a `persister` resource pointing at
`/trees/:doc` on this server and Arethusa's save button writes the file.
Until then: edit in Emacs, look in Arethusa, and reload its page after a save.

## The trees may also be symlinked

The page fetches the tree by URL, so the browser will refuse a `file://` path
or another host's. Serve the trees from the same place as the page:

```fish
cd ~/diogenes-folder/tei-browser/tools/viewer
ln -s ~/diogenes-folder/diorisis-work/trees ./trees
python3 -m http.server 8080
```

Any static server will do; that one is in Python and needs nothing installed.
Leave it running in a terminal, or make a systemd user unit of it.

## Telling Emacs

```elisp
(setq tei-diorisis-treebank-viewer
      "http://localhost:8080/?doc=%n&chunk=1")
```

`%n` is the tree's **file name and nothing more**, and that matters: Arethusa
substitutes it into a route of its own and encodes it as a single path
segment, so `?doc=/trees/x.xml` is fetched as `/%2Ftrees%2Fx.xml` and answered
with a 404. Where the trees are is the page's business — `?dir=` overrides it,
and the default is the `trees` link beside `index.html`. `%f` is the whole
`file://` URL, for a viewer that can take one. Then `w` in the editor
opens the tree in the widget, and inside Emacs where this Emacs has xwidgets —
see `tei-diorisis-tree-widget-in-emacs`.

## The whole of Arethusa, without building it

What Perseids runs is the full Arethusa application — its navbar, its menus,
every panel — and the widget package ships only the JavaScript for embedding a
panel. The application's own page is in **Arethusa's own repository**, and
between the two you have everything needed, so nothing has to be built:

```fish
cd ~/diogenes-folder
unzip ~/Downloads/arethusa-master.zip        # or git clone the repository
cd ~/diogenes-folder/tei-browser/tools/viewer
python3 serve.py --trees ~/org/trees --arethusa ~/diogenes-folder/arethusa-master
```

It prints `the app  http://localhost:8087/app/index.html`, and that is
Arethusa proper.

```elisp
(setq tei-diorisis-treebank-viewer
      "http://localhost:8087/app/index.html#/staging?doc=/trees/%n&chunk=1")
```

**What the server is doing to make that work.** Arethusa's page asks for
`../dist/arethusa.min.js` and two others, which its repository does not ship
built — the widget package does, under slightly different names, so those
three are aliased. Its configurations and translations are asked for under
`dist/`, where its own repository keeps a README and nothing else (they live
in a separate repository), so those come from the widget's copy too. Its
`app/js`, `vendor`, `static` and `images` are served from the source tree.

**And it fixes the templates properly.** A few of Arethusa's templates are
fetched at run time and are not in the built bundles —
`foreign_keys_help.html` was one, and its absence stopped a panel rendering.
They are all in `app/js/**/templates/`, so with `--arethusa` they are answered
with themselves instead of with the empty stub this server would otherwise
send.

`--arethusa` is optional: without it the embedded page still works, with
stubs for those templates.

## The editor, only a panel of it

The widget ships two layouts and this page uses the larger by default:
`main_with_sidepanel.html`, which is the tree **with Arethusa's panels beside
it** — the morphology, the relations, the search. `widget.html`, the tree
alone, is what a viewer wants; `?panel=0` asks for it.

Asking for the layout is not enough on its own: the panels are plugins, so a
sidepanel with nothing configured to sit in it is an empty sidepanel. The page
adds `text`, `morph`, `relation`, `depTree` and `search` to whatever the
configuration already lists, keeping its own — it knows its tagset better than
we do.

## The configuration is Arethusa's own

`dist/arethusa/configs` ships the real configurations, and the page loads
**`aldt2grc.json`** — the Ancient Greek Dependency Treebank's own: its relation
set, its morphology attributes, the lot. Far better than a hand-written one.
`?conf=morphgrc`, `?conf=pedalion`, `?conf=ud` and the rest of that directory
work too.

Over whichever is loaded the page puts back the few things a *panel* needs and
a full application's config gets wrong: the widget layout, no navbar, the
`Gardener` route with the directory in it, and Arethusa's own messages left
on. If the config cannot be read the page says so and falls back on a small
built-in one, which draws the same tree with a poorer relation set.

## What you get, and what to watch

Arethusa's own editor, with the tree drawn by dagre. It can **save back to the
file** only through a Perseids backend, which this has none of — so treat it
as a viewer and a second pair of eyes, and keep the editing in Emacs, which
writes the file. A tree edited in the widget and not written back is lost when
the tab closes.

The morphology panel calls out to `morph.perseids.org`, so it wants the
network; the tree itself does not.

## When it shows a blank panel

The server's own log is the first place to look — `python3 -m http.server`
prints every request and its status, so a 404 names the file that is missing.
Arethusa's own messages are left switched on in this page (the library
disables them for an embedded widget, which here would mean a blank panel and
no reason), so a document it cannot fetch or parse says so on the page.

**There is a console in the page**, because an xwidget has none —
WebKitGTK's inspector wants developer-extras turned on and Emacs offers no
dependable way to ask. Everything the page and Arethusa say is caught and
printed in a panel under the tree: `console.log` and friends, uncaught
errors, unhandled rejections, and **any request that fails**, which is how
four of the faults so far were found. It appears by itself when something goes
wrong, and `?log=1` shows it from the start.

`B` in the tree editor still opens the same URL in a real browser, where the
network tab and the element inspector are.
