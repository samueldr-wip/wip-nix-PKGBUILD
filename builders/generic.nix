{ seed }:

{ name
, basePackageSet
, buildPhase
, derivationAttributes ? {}
}:

derivation ({
  inherit name;
  system = "x86_64-linux";
  builder = "${seed}/bin/ash";
  PATH = "${seed}/bin/";

  archiveUnpacker =
    ''
      set -e
    '' + (
    builtins.concatStringsSep "\n"
    (
      builtins.map (
        { filename, file }:
          ''
            echo ":: Unpacking ${filename}..."
            bsdtar -x -f ${file}
            cat ${file} > var/cache/pacman/pkg/${filename}
          ''
        ) basePackageSet
      )
    )
  ;

  passAsFile = [ "archiveUnpacker" ];

  args =
    [
      (builtins.toFile "builder.sh" ''
        set -e
        set -u
        PS4=" $ "

        _banner() {
          printf "\n:: %s\n\n" "$*"
          # See `handleJSONLogMessage` in the Nix source.
          printf "@nix { \"action\": \"setPhase\", \"phase\": \"%s\" }\n" "$@" >&"$NIX_LOG_FD"
        }

        _banner "Extracting packages"

        (
        set -x
        mkdir -p root/var/cache/pacman/pkg
        cd root
        sh "''$archiveUnpackerPath"
        )

        __bwrap() {
          ARGS=""
          ARGS="$ARGS --unshare-all"
          ARGS="$ARGS --chdir ''${CHROOTED_INITDIR:-/}"

          ARGS="$ARGS --bind     $PWD/root    /"
          ARGS="$ARGS --proc                  /proc"
          ARGS="$ARGS --dev-bind /dev         /dev"
          ARGS="$ARGS --tmpfs                 /build"
          # Prevent leaks...
          ARGS="$ARGS --tmpfs                 /nix"
          ARGS="$ARGS ''${BWRAP_ADDITIONAL_ARGS:-}"

          # Use strace's injection mechanisms to pretend all chown operations work.
          SYSCALL_INTERCEPT=""
          SYSCALL_INTERCEPT="$SYSCALL_INTERCEPT strace"
          SYSCALL_INTERCEPT="$SYSCALL_INTERCEPT -o /dev/null"
          SYSCALL_INTERCEPT="$SYSCALL_INTERCEPT --quiet=all"
          SYSCALL_INTERCEPT="$SYSCALL_INTERCEPT --trace=/chown"
          SYSCALL_INTERCEPT="$SYSCALL_INTERCEPT --inject=/chown:retval=0"
          SYSCALL_INTERCEPT="$SYSCALL_INTERCEPT -f"

          (
          set -x
          $SYSCALL_INTERCEPT bwrap $ARGS "$@"
          )
        }

        _bwrap_user() {
            __bwrap -- /usr/bin/env -i PATH="/usr/bin/" "$@"
        }
        _bwrap_root() {
            __bwrap --uid 0 --gid 0 -- /usr/bin/env -i PATH="/usr/bin/" "$@"
        }

        # Runs a command in the chrooted environment.
        # Safely(?) handles arguments.
        _chrooted() {
          _bwrap_root "$@"
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
          # FIXME: sh-flavoured command execution needed to expand file list arguments.
          _chrooted_sh \
            pacman --disable-sandbox --noprogressbar --nodeps --nodeps --noconfirm --overwrite '\*' "$@"
        }

        _banner "Fixing-up temp root"

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
        archbld:x:1000:1000:Builder user:/builder:/usr/bin/bash
        alpm:x:0:0:Arch Linux Package Management:/:/usr/bin/nologin
        EOF
        cat <<EOF >> root/etc/shadow
        archbld:!*:3652::::::
        alpm:!*:3652::::::
        EOF
        cat <<EOF >> root/etc/group
        users:x:100:
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

        _banner "Rehydrating pacman database"

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

        ${buildPhase}

      '')
    ]
  ;
} // derivationAttributes)
