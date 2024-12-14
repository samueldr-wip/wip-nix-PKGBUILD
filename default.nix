rec {
  seed = import ./seed.nix { };

  buildPKGBUILD = import ./builders/buildPKGBUILD.nix {
      inherit seed;
  };

  fetchSourcePackage = import ./builders/fetchSourcePackage.nix {
      inherit seed;
      basePackageSet = withPackages [ "base" "base-devel" ];
  };

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

  sources = {
    hello = fetchSourcePackage {
      name = "hello";
      packageSource = builtins.fetchGit {
        url = "https://aur.archlinux.org/hello.git/";
        rev = "51cec6333515471681ec8aa00943145d420311fa";
        allRefs = true;
      };
      hash = "sha256-cBbqxEWqPbbfpxCyweLw4ykTSbw1czG7HBi9LGfYg/w=";
    };
    grep = fetchSourcePackage {
      name = "grep";
      packageSource = builtins.fetchGit {
        url = "https://gitlab.archlinux.org/archlinux/packaging/packages/grep";
        rev = "985c5491d2b33e0f38543133e89171a804e56fc3";
        allRefs = true;
      };
      hash = "sha256-AbR7yMiAB4G6/mUos6W+uIbGnHG+WHFl3ISlMuk+yf0=";
    };
  };

  packages = {
    hello = buildPKGBUILD {
      name = "hello";
      basePackageSet = withPackages [ "base" "base-devel" ];
      packageSource = ./hello-2.12.1-2.src.tar.gz;
    };
    grep = buildPKGBUILD {
      name = "grep";
      basePackageSet = withPackages [ "base" "base-devel" ];
      packageSource = ./grep-3.11-1.src.tar.gz;
    };
  };
}
