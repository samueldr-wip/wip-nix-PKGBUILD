rec {
  seed = import ./seed.nix { };

  basePackageSet = 
    with import ./archlinux.lib.tests.nix {};
    reverse (builtins.map (desc: repo.fetchPackage { inherit desc; }) basePackageAndDeps)
  ;

  withPackages =
    packageNames:
    with import ./archlinux.lib.tests.nix {};
    let
      packages = (_tests.packages ../repos [ "core" "extra" ]);
      baseDevel = db.allDepsForPackageNames { inherit packages; names = packageNames; };
    in
    reverse (builtins.map (desc: repo.fetchPackage { inherit desc; }) baseDevel)
  ;

  test = import ./test.nix {
    inherit seed;
    basePackageSet = withPackages [ "base" "base-devel" ];
    packageSource = ./hello-2.12.1-2.src.tar.gz;
  };
}
