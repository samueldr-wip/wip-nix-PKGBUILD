rec {
  seed = import ./seed.nix { };
  test = import ./test.nix {
    inherit seed;
  };
}
