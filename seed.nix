{}:

let
  seed' = import ./binary-seed.nix {};
  # Round-trip the binary seed into a tarball to properly show we could
  # publish the tarball independent from Nixpkgs.
  # NOTE: archive needs to be pre-built...
  # ```
  # nix-build ./binary-seed.nix -A archive
  # ```
  # TODO: figure out a way to use IFD instead?
  seed = builtins.fetchTarball {
    url = builtins.unsafeDiscardStringContext "file://${toString seed'.archive}";
  };
in
derivation {
  inherit seed;
  name = "binary-seed";
  system = "x86_64-linux";
  builder = "/bin/sh";
  PS4 = "[bootstrap:busybox] ";
  args =
    [
      (builtins.toFile "seed-builder" ''
        set -eux

        # NOTE: we are building defensively pretending none of the busybox
        #       applet symlinks exist in any form.

        # Make the directory
        ( exec -a busybox $seed/bin/busybox mkdir -p $out/ )
        # Copy the files
        ( exec -a busybox $seed/bin/busybox cp -rf -t $out/ $seed/* )
      '')
    ]
  ;
}
