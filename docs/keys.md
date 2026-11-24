# The keys, and evil

### Forgetting the keys

    M-x diogenes-cheatsheet

shows them in a floating panel that vanishes at the next keystroke. It is read
from the **live keymaps**, so it lists what this installation actually has —
the dictionaries you configured and nothing that would decline. The current
buffer's keys come first, then the other buffers', then the commands that get
you into one. On a terminal frame, where there are no child frames, it falls
back to an ordinary help window.

Worth binding, since it is the one command that tells you the rest:

```elisp
(with-eval-after-load 'classicist-lookup
  (keymap-set classicist-lookup-mode-map "?" #'diogenes-cheatsheet))
```

### Under evil

Doom and Spacemacs users, and anyone else with evil: the single-letter
dictionary keys collide with evil's normal state. `diogenes-evil.el` puts them
where they do not, and is loaded when evil is present.
