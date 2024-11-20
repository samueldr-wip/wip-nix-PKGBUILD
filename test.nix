{ seed }:

derivation {
  name = "test";
  system = "x86_64-linux";
  builder = "${seed}/bin/ash";
  PATH = "${seed}/bin/";
  archive = ../pacstrap/root.tar.bz2;
  args =
    [
      (builtins.toFile "test.sh" ''
        set -e
        set -u
        PS4=" $ "

        _banner() {
          printf "\n:: %s\n\n" "$*"
        }

        _banner "Extracting archive..."

        (set -x
        # NOTE: skipping ca-certificates/extracted due to (possible?) busybox tar bug with read-only dir?
        # XXX this is a POC... the actual rootfs simulacrum will be built using the pre-built Arch Linux packages.
        # XXX prefer libarchive tar?
        tar \
          --exclude "root/etc/ca-certificates/extracted/*" \
          -xf "$archive"
        )

        _banner "Doing the cursed bit..."

        _chrooted() {
          # NOTE: NOT SAFE
          printf "%s" "$*" | \
            unshare \
              --user \
              --map-root-user \
              --mount \
              env -i $(which sh) -c \
              "$(which env) $(which chroot)"' "$(pwd)/root" sh'
        }

        (
          echo "Pacman version:"
          _chrooted pacman --version
          echo ""
          echo "Package list:"
          _chrooted pacman -Q
          echo ""
        ) > $out
      '')
    ]
  ;
}
