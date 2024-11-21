rec {
  seed = import ./seed.nix { };

  basePackageSet = 
    with import ./archlinux.lib.tests.nix {};
    reverse (builtins.map (desc: repo.fetchPackage { inherit desc; }) basePackageAndDeps)
  ;

  test = import ./test.nix {
    inherit seed;
    inherit basePackageSet;
  };
}
