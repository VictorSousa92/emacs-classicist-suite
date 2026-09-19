#!/usr/bin/env python3
"""serve.py -- the viewer, and a way for Arethusa to write the tree back.

WHY THIS EXISTS.  `python3 -m http.server' serves the viewer page and the
trees, and that is enough to LOOK at a tree.  Arethusa can also edit one --
it is the whole annotation environment, not a picture -- but it saves through
a backend, and without one every edit dies with the tab.

So this is that backend, and nothing more than that: it serves the same files
and accepts a PUT or a POST for a tree, which it writes into the trees
directory.  Then the same file is open in Emacs and in Arethusa, either may
write it, and the Emacs editor rereads it when it changes -- see
`tei-diorisis-tree-watch'.

    python3 serve.py                      # port 8080, ./trees
    python3 serve.py --port 9000 --trees ~/org/trees

WHAT IT WILL NOT DO, on purpose.  It writes only into the trees directory,
only files whose names it would have served from there, and only `.xml'.  A
server that accepts writes is a server to be careful with: this one binds to
localhost unless told otherwise, and there is no authentication because there
is nothing to authenticate on a socket only this machine can reach.

A COPY IS KEPT of whatever a write replaces -- `NAME.xml~' beside it -- because
two editors on one file will sooner or later both be right, and the loser of
that race should be recoverable.
"""

import argparse
import http.server
import os
import shutil
import sys
import urllib.parse


class Handler(http.server.SimpleHTTPRequestHandler):
    """Serve the viewer, and write a tree where one is sent."""

    trees = None
    # ARETHUSA'S OWN SOURCE TREE, where the reader has it: `--arethusa
    # ~/src/arethusa'.  It is worth having for two quite different reasons.
    #
    # THE TEMPLATES.  Its `app/js/**/templates/*.html' are the run-time
    # templates the built bundles do not carry -- including
    # `foreign_keys_help.html', whose absence stopped a panel rendering and
    # which this server was reduced to answering with an empty div.  With the
    # source tree they are answered with themselves.
    #
    # AND THE WHOLE APPLICATION.  `app/index.html' is Arethusa proper, the
    # thing Perseids runs: the navbar, the menus, every panel.  It wants
    # `../dist/arethusa.min.js' and two others, which the repository does not
    # ship built -- but the widget package does, under other names, and
    # `renames' below maps one to the other.  So the full application can be
    # served without building anything, at `/app/'.
    arethusa = None
    # WHOLE DIRECTORIES UNDER ANOTHER NAME.  The application asks for its
    # configurations and its translations under `dist/', where its own
    # repository keeps a README and nothing else -- they live in a separate
    # repository, and the widget package ships them built.  So these two are
    # answered from the widget's copy.
    prefixes = {
        "/dist/configs/": "arethusa/configs/",
        "/dist/i18n/": "arethusa/i18n/",
    }
    renames = {
        "/dist/arethusa_packages.min.js": "arethusa/arethusa.packages.min.js",
        "/dist/arethusa.min.js": "arethusa/arethusa.min.js",
        "/dist/arethusa.min.css": "arethusa/css/arethusa.min.css",
    }
    # WHAT IS NOT LOGGED.  Arethusa asks for some two hundred files as it
    # starts and the log is where these faults have been found; the scripts
    # and the icons drown it.  The stubs and the failures are not quietened --
    # see `log_message' -- since those are the lines worth reading.
    quiet_paths = ("/arethusa/", "/favicon.ico")

    # WHAT ARETHUSA ASKS FOR RELATIVE TO THE PAGE.  Its templates are mostly
    # compiled into the JavaScript, but not all of them: a few are fetched at
    # run time, and fetched with paths like `./js/arethusa.core/templates/x.html'
    # -- relative to the PAGE and not to the base its loader was given.  They
    # therefore arrive as `/js/...' while the files are under `/arethusa/js/...',
    # and Angular reports a template it cannot load, which stops whatever was
    # being rendered.
    #
    # So these prefixes are answered from the Arethusa directory as well as
    # from the viewer's own.  Aliasing rather than redirecting: a redirect
    # would work too and would double every request.
    arethusa_paths = ("/js/", "/css/", "/configs/", "/vendor/", "/fonts/",
                      "/i18n/", "/dist/", "/templates/")

    def translate_path(self, path):
        """Where a URL's file is.

        THE TREES ARE ELSEWHERE.  They live wherever
        `tei-diorisis-treebank-directory' says, which is not under the viewer,
        so `/trees/...' is answered from there rather than from a symlink --
        one less thing to get wrong, and the symlink has been wrong twice."""
        clean = urllib.parse.urlparse(path).path
        if clean.startswith("/trees/") and self.trees:
            name = os.path.basename(clean)
            return os.path.join(self.trees, name)
        for prefix, under in self.prefixes.items():
            if clean.startswith(prefix):
                instead = os.path.join(os.getcwd(), under,
                                       clean[len(prefix):].lstrip("/"))
                if os.path.exists(instead) and os.path.isfile(instead):
                    return instead
        # THE BUNDLES UNDER THE NAMES THE APPLICATION ASKS FOR.
        if clean in self.renames:
            instead = os.path.join(os.getcwd(), self.renames[clean])
            if os.path.exists(instead):
                return instead
        # THE SAME PATHS UNDER THE WIDGET'S BASE.  Arethusa resolves an
        # `@include' against the base its loader was given -- `./arethusa' --
        # so a configuration that includes
        # `js/arethusa.relation/configs/relation/relations.json' asks for it
        # under `/arethusa/js/...', where the built bundles have no `js'
        # directory at all.  The leading `/arethusa' is dropped and the
        # source tree asked, so an include works whichever base it was
        # resolved against.
        if self.arethusa and clean.startswith("/arethusa/"):
            clean = clean[len("/arethusa"):]
        # THE APPLICATION, ITS TEMPLATES AND ITS VENDORED LIBRARIES, from the
        # source tree where one was given.
        if self.arethusa:
            for prefix, under in (("/app/", ""), ("/js/", "app/"),
                                  ("/vendor/", ""), ("/static/", "app/"),
                                  ("/images/", "app/"),
                                  ("/dist/configs/", ""),
                                  ("/dist/i18n/", "")):
                if clean.startswith(prefix):
                    inside = clean.lstrip("/")
                    if prefix == "/app/":
                        inside = inside[len("app/"):]
                        under = "app/"
                    instead = os.path.join(self.arethusa, under, inside)
                    if os.path.exists(instead) and os.path.isfile(instead):
                        return instead
        here = super().translate_path(path)
        if not os.path.exists(here):
            for prefix in self.arethusa_paths:
                if clean.startswith(prefix):
                    # `translate_path' has already made the path safe -- it
                    # strips `..' and resolves against the working directory
                    # -- so what is joined here is a path under it.
                    inside = os.path.relpath(here, os.getcwd())
                    instead = os.path.join(os.getcwd(), "arethusa", inside)
                    if os.path.exists(instead):
                        return instead
        return here

    def end_headers(self):
        """Every answer says it may be read from elsewhere.

        FOR AN ARETHUSA ON ANOTHER PORT.  The full application, built and
        served by its own `grunt server', is a different origin from this --
        `localhost:8081' against `localhost:8087' -- and a browser will not
        let it fetch a tree from here without being told it may.  Everything
        this serves is a public page and a text file; there is nothing here
        to protect from a page the reader has open themselves."""
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def do_GET(self):
        """As usual, except that a missing Arethusa template is answered empty.

        A TEMPLATE THAT IS NOT THERE STOPS THE RENDERING.  Arethusa's
        templates are compiled into its JavaScript -- there is not one HTML
        file in the whole build -- but a few are fetched at run time all the
        same, and `js/arethusa.core/templates/foreign_keys_help.html' is one
        of them.  It is not shipped.  Angular answers a template it cannot
        load with `$compile:tpload', and whatever was being rendered stops
        there: in this case, the panel the template was help for.

        HELP TEXT IS NO LOSS.  An empty template satisfies Angular and the
        rendering goes on, so the panel appears without its help.  Every such
        request is logged as `stubbed', so nothing is hidden: a template that
        matters would show up there and could be found and put in place."""
        clean = urllib.parse.urlparse(self.path).path
        if (clean.endswith(".html")
                and any(clean.startswith(one) for one in self.arethusa_paths)
                and not os.path.exists(self.translate_path(self.path))):
            self.log_message("stubbed %s", clean)
            body = (b"<!-- stubbed by serve.py: this template is not in the "
                    b"Arethusa build -->\n<div></div>\n")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        return super().do_GET()

    def do_PUT(self):
        self.write_tree()

    def do_POST(self):
        # ARETHUSA MAY USE EITHER, depending on how its persister is
        # configured, and there is no reason to care which.
        self.write_tree()

    def write_tree(self):
        clean = urllib.parse.urlparse(self.path).path
        name = os.path.basename(clean)
        if not clean.startswith("/trees/") or not name.endswith(".xml"):
            self.complain(403, "This server writes only /trees/NAME.xml")
            return
        if name != os.path.basename(name) or name.startswith("."):
            self.complain(403, "No.")
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            self.complain(411, "Nothing to write")
            return
        body = self.rfile.read(length)
        where = os.path.join(self.trees, name)
        try:
            # THE OLD ONE FIRST.  See the note at the head of this file: the
            # loser of a race between two editors should be recoverable.
            if os.path.exists(where):
                shutil.copy2(where, where + "~")
            with open(where, "wb") as handle:
                handle.write(body)
        except OSError as trouble:
            self.complain(500, "Could not write %s: %s" % (name, trouble))
            return
        self.log_message("wrote %s, %d bytes", name, len(body))
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"written\n")

    def do_OPTIONS(self):
        # ASKED BEFORE A WRITE by any browser that thinks this might be
        # another origin.  Answered rather than refused, the alternative being
        # a save that fails with nothing in the log to say why.
        self.send_response(204)
        self.send_header("Allow", "GET, HEAD, PUT, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Methods",
                         "GET, HEAD, PUT, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def complain(self, code, said):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write((said + "\n").encode("utf-8"))

    def log_message(self, form, *args):
        """Quieter than the default, and on one line.

        Arethusa asks for some two hundred files at startup and the log is
        where these faults have been diagnosed; the templates and the icons
        drown it."""
        said = form % args
        if (any(part in said for part in self.quiet_paths)
                and " 200 " in said
                and "stubbed" not in said):
            return
        sys.stderr.write("%s  %s\n" % (self.log_date_time_string(), said))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(
        description="Serve the treebank viewer, and write trees back.")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--trees", default=os.path.join(here, "trees"),
                        help="where the ALDT files are (default ./trees)")
    parser.add_argument("--host", default="127.0.0.1",
                        help="127.0.0.1 by default: this machine only")
    parser.add_argument("--arethusa", default=None,
                        help="Arethusa's source tree, for its run-time"
                             " templates and for the whole application"
                             " at /app/")
    args = parser.parse_args()

    trees = os.path.abspath(os.path.expanduser(args.trees))
    if not os.path.isdir(trees):
        raise SystemExit("No such directory: %s" % trees)
    os.chdir(here)
    Handler.trees = trees
    if args.arethusa:
        source = os.path.abspath(os.path.expanduser(args.arethusa))
        if not os.path.isdir(os.path.join(source, "app")):
            raise SystemExit("No app/ under %s: is that Arethusa's source?"
                             % source)
        Handler.arethusa = source

    print("   the viewer  http://%s:%d/" % (args.host, args.port))
    print("   the trees   %s" % trees)
    print("   writes      PUT or POST /trees/NAME.xml, with NAME.xml~ kept")
    if Handler.arethusa:
        print("   arethusa    %s" % Handler.arethusa)
        print("   the app     http://%s:%d/app/index.html"
              % (args.host, args.port))
    print()
    http.server.ThreadingHTTPServer((args.host, args.port), Handler)\
        .serve_forever()


if __name__ == "__main__":
    main()
