{}:

let
  seed' = import ./binary-seed.nix {};
  checkTarballRoundtrip = false;
  
  seed =
    if checkTarballRoundtrip then
      #
      # Round-trip the binary seed into a tarball to properly show we could
      # publish the tarball independent from Nixpkgs.
      #
      # NOTE: archive needs to be built in advance for the `file://` to resolve.
      #       fetchTarball can't depend on Nix-built inputs.
      #
      # ```
      # nix-build ./binary-seed.nix -A archive
      # ```
      builtins.fetchTarball {
        url = builtins.unsafeDiscardStringContext "file://${toString seed'.archive}";
      }
    else
      # For development purpose, depend directly on the seed before packing into an archive.
      seed'
  ;
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
