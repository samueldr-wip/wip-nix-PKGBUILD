> [!NOTE]
> This is a work-in-progress, and a proof of concept.
> With that said, *it works*.

To do a test drive, run:

```
nix-build -A packages.hello -A packages.grep
```

* * *

This is currently using an arbitrary `core` and `extra` repository db, from the
time I published this.

* * *

The API currently used in `default.nix` is far from final. This initial proof
of concept is about making the build tooling work, rather than working out the
best developer experience.

* * *

FAQ
---

### Does this use on Nixpkgs or NixOS?

Not really.

Currently, as an implementation detail, it relies on Nixpkgs to provide a bootstrap static seed of `busybox`, `bubblewrap`, `libarchive` and `strace`.

They could be provided by some other means too.

Otherwise, once the bootstrap seed is built, everything is done without involving Nixpkgs.

