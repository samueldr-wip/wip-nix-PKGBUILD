{ seed }:

{ name
, basePackageSet
, packageSource
}:

let
  genericBuilder = import ./generic.nix { inherit seed; };
in

genericBuilder {
  inherit
    name
    basePackageSet
  ;

  derivationAttributes = {
    inherit
      packageSource
    ;
  };

  buildPhase = ''
    _banner "Building $name"

    # TODO: find a solution not requiring this workaround...
    echo "Applying a workaround in makepkg..."
    (
    set -x
    sed -i "s;\bEUID\b;1;" root/usr/bin/makepkg
    )

    echo ""
    (
    set -x
    mkdir -p root/package
    tar --strip-components 1 -C root/package/ -xf "$packageSource"
    CHROOTED_INITDIR="/package"
    _chrooted_sh 'export PAGER=cat; makepkg --skippgpcheck'
    )

    mkdir -p $out
    cp -v -t $out/ root/package/*.pkg.tar*
  '';
}
