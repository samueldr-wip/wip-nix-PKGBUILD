{ archlinuxLib ? import ./archlinux.lib.nix
, reposDir ? ../repos
}:

with archlinuxLib; # approximates inheriting the whole set as `rec`.
archlinuxLib // (rec {
  _tests = rec {
    packages = path: repos:
    db.merge (
      builtins.map
      (repoName: (db.all { path = (path + "/${repoName}"); }))
      repos
    )
    ;
    basePackageSet =
      packages:
      db.allDepsForPackageNames { inherit packages; names = [ "base" ]; }
    ;
  };
  basePackageAndDeps =
    # With the repos already cloned at `../repos` ...
    #  $ nix-instantiate --strict --eval --json ./archlinux.lib.tests.nix  --attr basePackageAndDeps | jq .[].NAME.[0] | less
    # This should list all the packages wanting `base` brings in.
    _tests.basePackageSet (_tests.packages reposDir [ "core" "extra" ])
  ;
  # In what should be the proper order to extract, "deepest" dependencies first.
  fetchBasePackageAndDeps =
    reverse (builtins.map (desc: repo.fetchPackage { inherit desc; }) basePackageAndDeps)
  ;
})
