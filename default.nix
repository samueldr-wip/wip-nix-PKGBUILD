rec {
  seed = import ./seed.nix { };

  reposBuilder = import ./builders/repos.nix {
    inherit seed;
  };

  repos = reposBuilder (import ./repos.nix);

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
      packages = (_tests.packages repos [ "core" "extra" ]);
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
      hash = "sha256-w7ooY4tcM1CUhGW3QgB0CiRFvuGRg46kmOBJJUQ+IW0=";
    };
    grep = fetchSourcePackage {
      name = "grep";
      packageSource = builtins.fetchGit {
        url = "https://gitlab.archlinux.org/archlinux/packaging/packages/grep";
        rev = "985c5491d2b33e0f38543133e89171a804e56fc3";
        allRefs = true;
      };
      hash = "sha256-sZ0AICPEYGZ5tf1AnXztE3fO+M/ilwGzjJzJrf3aNBM=";
    };
  };

  packages = {
    hello = buildPKGBUILD {
      name = "hello";
      basePackageSet = withPackages [ "base" "base-devel" ];
      packageSource = sources.hello;
    };
    grep = buildPKGBUILD {
      name = "grep";
      basePackageSet = withPackages [ "base" "base-devel" ];
      packageSource = sources.grep;
    };
  };
}
