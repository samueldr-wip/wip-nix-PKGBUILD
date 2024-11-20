# The minimum (for now) needed to get going.
# Borrowed (for now) from Nixpkgs, but could come from any other provenance.
{ pkgs ? import (import ./support/npins).nixpkgs {} }:

let
  attrs = rec {
    archive = pkgs.callPackage (
      { runCommand
      , libarchive
      , seed
      }:

      runCommand "arch-nix-binary-seed.tar.bz2" {
        inherit seed;
        nativeBuildInputs = [
          libarchive
        ];
      } ''
        CMD=(
          bsdtar
          --auto-compress
          --create
          --file "$out"
          seed
        )

        (PS4=" $ "
        set -x
        cp -r "$seed" seed
        "''${CMD[@]}"
        )
      ''

    ) { inherit seed; };

    seed = pkgs.callPackage (
      { runCommand
      , pkgsStatic
      }:

      (
        runCommand "arch-nix-binary-seed" {
          seed = [
            pkgsStatic.busybox
            pkgsStatic.zstd
          ];
        } ''
          (PS4=" $ "
          set -x
          mkdir -p $out/bin
          for b in $seed; do
            cp --no-dereference -t $out/bin "$b"/bin/*
          done
          )
        ''
      )
    ) {};
  };
in
attrs.seed // {
  inherit (attrs) archive;
}
