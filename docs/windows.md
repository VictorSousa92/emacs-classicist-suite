# Where the windows go

A preset is a window arrangement kept in a file you load when you want it,
rather than in your init file. Four ship — `defer`, `reuse`, `split`,
`frames` — and the builder's second tab writes your own, with a simulator that
shows what each does to a frame before you commit to it.

    (setq diogenes-preset "split")

A note opened from a passage, from the index or from the list goes through the
same machinery, under the role `notes`. It appears **below the text it is
about** by default — the passage above, what you have written about it
underneath, both on the screen at once — which is
`classicist-phi-display-action`:

```elisp
(setq classicist-phi-display-action
      '((display-buffer-below-selected) (window-height . 0.4)))
```

Set that to nil and a note is placed by the behaviour and the preset like any
other buffer. That is the more consistent answer and the worse one in
practice: `reuse` then means a note takes the window it was asked from, which
is the browser showing the passage the note is about.

`classicist-display-actions` overrides it, being consulted first:

```elisp
(add-to-list 'classicist-display-actions
             '(notes . ((display-buffer-in-side-window)
                        (side . right) (window-width . 0.3))))
```

The work note shown by `C-c n s` is deliberately outside this: a sidebar is
furniture, and a reader who put it on an edge expects it to stay there rather
than be placed by a rule.
