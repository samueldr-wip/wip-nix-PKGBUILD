{ seed
, basePackageSet
}:

derivation {
  name = "test";
  system = "x86_64-linux";
  builder = "${seed}/bin/ash";
  PATH = "${seed}/bin/";

  archiveUnpacker =
    builtins.concatStringsSep "\n"
    (
      builtins.map (
        { filename, file }:
        ''
          zstdcat ${file} | tar -x
          cat ${file} > var/cache/pacman/pkg/${filename}
        ''
      ) basePackageSet
    )
  ;

  passAsFile = [ "archiveUnpacker" ];

  args =
    [
      (builtins.toFile "test.sh" ''
        set -e
        set -u
        PS4=" $ "

        _banner() {
          printf "\n:: %s\n\n" "$*"
        }

        _banner "Extracting archives..."

        (
        set -x
        mkdir -p root/var/cache/pacman/pkg
        cd root
        sh "''$archiveUnpackerPath"
        )

        # Runs a command in the chrooted environment.
        # Safely(?) handles arguments.
        _chrooted() {
          unshare \
            --user \
            --map-root-user \
            --mount \
            env -i $(which chroot) "$(pwd)/root" \
              "$@"
        }

        # Helper that runs the passed arguments *hapazardly* through `sh`.
        # This can be used to force globs to happen within the chrooted environment.
        _chrooted_sh() {
          # NOTE: NOT SAFE regarding expansion. Mind your escapes.
          printf "PS4='[chrooted] # '; set -x; %s" "$*" | \
            _chrooted "sh"
        }

        # Helper that handles calling args for pacman
        _pacman() {
          ARGS="/usr/bin/pacman"
          # NOTE: not sufficient, the sandbox user was still used...
          ARGS="$ARGS --disable-sandbox "
          ARGS="$ARGS --noprogressbar "
          ARGS="$ARGS --nodeps "
          ARGS="$ARGS --nodeps "
          ARGS="$ARGS --noconfirm "
          ARGS="$ARGS "'--overwrite \*'
          _chrooted_sh \
            $ARGS "$@"
        }



        _banner "Applying some minor fixups"

        (
        set -x
        #
        # We're giving the root user UID to the alpm user...
        # Otherwise (even with sandbox disabled, and not fetching) we're hitting
        # a “failed to commit transaction (unexpected error)” error, which is
        # AFAICT related to sandboxuser and sandboxing.
        # `strace`-ing I see:
        # chown("/var/cache/pacman/pkg/download-XXXXXX", 973, 973) = -1 EINVAL (Invalid argument)
        #
        cat <<EOF >> root/etc/passwd
        alpm:x:0:0:Arch Linux Package Management:/:/usr/bin/nologin
        EOF
        cat <<EOF >> root/etc/shadow
        alpm:!*:3652::::::
        EOF
        rm root/etc/mtab
        # Prevents pacman from pretending there's not enough free space...
        cat /proc/mounts > root/etc/mtab

        # prevents gnupg "installation" from hanging...
        # ... by just not gnupg.
        mkdir -p root/tmp/packages-only-registered
        mv -v root/var/cache/pacman/pkg/gnupg-* root/tmp/packages-only-registered
        mkdir -p root/root/.gnupg
        )

        # Make pacman happy enough (but with empty DBs!)
        mkdir -p root/var/lib/pacman/sync/
        _chrooted repo-add "/var/lib/pacman/sync/core.db.tar.gz"
        _chrooted repo-add "/var/lib/pacman/sync/extra.db.tar.gz"

        _banner "Refreshing the pacman database..."

        (
        echo "Rehydration!"
        _pacman -U /var/cache/pacman/pkg/*.pkg.tar*
        echo ""
        echo "Workaround for packages with bad install hooks..."
        _pacman -U --dbonly /tmp/packages-only-registered/*.pkg.tar*
        echo ""
        )

        if ! grep ^nobody: root/etc/passwd 2>&1 > /dev/null; then
          1>&2 echo ""
          1>&2 echo "error: user nobody not found in chrooted environment."
          1>&2 echo "       installation probably failed in an unexpected manner... bailing!"
          1>&2 echo ""
          exit 2
        fi

        (
        echo "Package list:"
        _chrooted pacman -Q
        echo ""
        cat root/etc/passwd
        ) > $out
      '')
    ]
  ;
}
