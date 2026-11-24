#!/bin/sh
# Push docs/ to the GitHub wiki, which is a repository of its own.
#
#     sh tools/publish-wiki.sh            # push
#     sh tools/publish-wiki.sh --check    # say what would change, push nothing
#
# WHY A SCRIPT AND NOT A WIKI EDITED BY HAND.  A GitHub wiki lives in
# <repo>.wiki.git -- a second repository, with its own history -- so a rename
# in the code and the documentation of it CANNOT be one commit.  Edited by
# hand it drifts, and nothing notices.
#
# So docs/ is the source and the wiki is generated: every page here overwrites
# its namesake there, and anybody who edits the wiki directly loses their edit
# at the next push.  The README says so, where a reader will see it.
#
# WHAT IT DOES TO THE NAMES.  A wiki page is addressed by its filename without
# the extension, and the sidebar is `_Sidebar.md'.  So `docs/searching.md'
# becomes `searching.md' at the top of the wiki, the map becomes `Home.md', and
# the links between pages -- which are `searching.md' in docs/ -- keep working,
# GitHub resolving a `.md' link to its page.
#
# `../README.md' CANNOT WORK THERE, the wiki having no README above it, so
# those links are rewritten to the repository's own README on the web.

set -eu

repo_url=$(git config --get remote.origin.url)
case "$repo_url" in
    *github.com*) : ;;
    *) echo "   remote is not github: $repo_url" >&2
       echo "   a wiki is a github thing; nothing done" >&2
       exit 1 ;;
esac

wiki_url=$(printf '%s' "$repo_url" | sed 's/\.git$//').wiki.git
web=$(printf '%s' "$repo_url" \
          | sed -e 's/\.git$//' -e 's#git@github.com:#https://github.com/#')
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "   wiki: $wiki_url"
if ! git clone --quiet "$wiki_url" "$work/wiki" 2>/dev/null; then
    echo "   cannot clone the wiki." >&2
    echo "   A wiki exists only once a first page has been made in the web" >&2
    echo "   interface: open $web/wiki and create one, then run this again." >&2
    exit 1
fi

for f in docs/*.md; do
    name=$(basename "$f")
    # THE README'S LINKS, which have nowhere to point inside a wiki.
    sed -e "s#\.\./README\.md#$web/blob/main/README.md#g" \
        "$f" > "$work/wiki/$name"
done

# THE MAP AS THE WIKI'S FRONT PAGE, taken from the README's own table so the
# two cannot say different things.
if [ -f docs/Home.md ]; then
    cp docs/Home.md "$work/wiki/Home.md"
fi

cd "$work/wiki"
if [ "${1:-}" = "--check" ]; then
    git --no-pager diff --stat
    echo "   (--check: nothing pushed)"
    exit 0
fi

if git diff --quiet; then
    echo "   the wiki is already up to date"
    exit 0
fi

git add -A
git commit --quiet -m "Generated from docs/ at $(cd - >/dev/null && git rev-parse --short HEAD)"
git push --quiet
echo "   pushed $(ls *.md | wc -l) pages"
