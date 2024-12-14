{ seed
, basePackageSet
}:

{ name
, packageSource
, hash
}:

let
  genericBuilder = import ./generic.nix { inherit seed; };
in

genericBuilder {
  name = "${name}-source";
  inherit
    basePackageSet
  ;

  derivationAttributes = {
    inherit
      packageSource
    ;

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = hash;
  };

  buildPhase = ''
    _banner "Copying network configuration from sandbox"

    (
    set -x
    # https://github.com/NixOS/nix/blob/f1187cb696584739884687d788a6fbb4dd36c61c/src/libstore/unix/build/local-derivation-goal.cc#L1900-L1921
    for path in "/etc/nsswitch.conf" "/etc/resolv.conf" "/etc/services" "/etc/hosts"; do
      cat "$path" > root/"$path"
    done
    )

    _banner "Building source package $name"

    # TODO: find a solution not requiring this workaround...
    echo "Applying a workaround in makepkg..."
    (
    set -x
    sed -i "s;\bEUID\b;1;" root/usr/bin/makepkg

    # TODO: contribute reproducible source tarball changes upstream
    cd root
    patch -p1 -i ${../patches/pacman/reproducible-sources.patch}
    )

    echo ""
    (
    set -x
    mkdir -p root/
    cp -r $packageSource root/package
    chmod -R +w root/package
    (
    cd root/package
    find | xargs touch -d "@$SOURCE_DATE_EPOCH" -h
    )
    CHROOTED_INITDIR="/package"
    set +x
    _chrooted_sh 'makepkg --allsource --skippgpcheck'
    )

    cp -v root/package/*.src.tar* $out
  '';
}
