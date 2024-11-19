#
# Library for parsing Arch Linux formats using Nix.
#
rec
{
  #
  # Generic helpers
  #

  # Strips the given chars from the start and end of the string.
  strip = char: builtins.match "^${char}*(.*[^${char}])?${char}+$";

  # Flattens one level of lists
  flatten = builtins.foldl' (fin: attr: fin ++ attr) [];

  # Removes nulls from a list
  compact = builtins.filter (i: i != null);

  # Keeps only unique elements from a list
  unique =
    builtins.foldl'
    (ret: curr:
      if builtins.elem curr ret
      then ret
      else (ret ++ [curr])
    )
    []
  ;

  #
  # ArchLinux formats parsing
  #

  # Transforms a "db" entry into a list of the form: `[ [ key ] value ... ]`
  dbToKVList =
    desc:
    builtins.tail (
      builtins.split "\n*%([^%]+)%\n*" (builtins.head (strip "\n" desc))
    )
  ;

  # Given a pair of ordered list keys/values, makes the matching attrset.
  KVListsToAttrs =
    elements:
    builtins.listToAttrs (
      builtins.map (i:
        {
          name  =
            builtins.head
            (builtins.elemAt elements.keys i)
          ;
          value =
            builtins.filter
            (el: (builtins.typeOf el) == "string")
            (
              builtins.split "\n"
              (builtins.elemAt elements.values i)
            )
          ;
        }
      ) (builtins.genList (x: (x + 1) - 1) (builtins.length elements.keys))
    )
  ;

  # Transforms a list of the form `[ [ key ] value ... ]` into a pair of ordered list keys/values.
  KVListToKVLists =
    list:
    let
      inherit
        (
          builtins.partition
          (el: (builtins.typeOf el) == "list")
          list
        )
        right # the keys
        wrong # the values
      ;
      in
      {
        keys = right;
        values = wrong;
      }
  ;

  #
  # Actual interfaces that should be used
  #

  db = {
    # db.parse (builtins.readFile file)
    parse = desc: KVListsToAttrs (KVListToKVLists (dbToKVList desc));

    # db.all ./path/to/unpacked/repo.db
    all =
      dir:
      builtins.listToAttrs (builtins.attrValues (
        builtins.mapAttrs (path: _type:
          let
            value = db.parse (builtins.readFile (dir + "/${path}/desc"));
          in
          {
            inherit value;
            name = builtins.head value."NAME";
          }
        )
        (builtins.readDir dir)
      ))
    ;

    # Given a package set, and a package description, returns a list of package descriptions it directly depends on.
    depsForPackage =
      { packages # Output from e.g. `db.all`
      , package  # A single package desc
      , _seen ? [] # Used internally to prevent infrec by keeping a tally of seen packages
      }:
      compact (
        builtins.map (depName:
          # Skips over packages already handled
          if builtins.elem depName _seen then null else

          # Is that dep in the packages set?
          if packages ? "${depName}"
          then packages."${depName}"
          else (builtins.trace "WARNING: missing dep ${depName}... skipping it even though we shouldn't!" null)
        ) (if package ? DEPENDS then package.DEPENDS else [])
      )
    ;

    # Given a package set, and a package description, returns a list of all package descriptions it depends on.
    allDepsForPackage =
      { packages # Output from e.g. `db.all`
      , package  # A single package desc
      , _seen ? [] # Used internally to prevent infrec by keeping a tally of seen packages
      }:
      let
        selfDeps = db.depsForPackage { inherit packages package _seen; };
        prev_seen = _seen;
      in
      let
        _seen = prev_seen ++ (flatten (builtins.map (p: p.NAME) selfDeps));
      in
        unique (
          selfDeps ++ (flatten (builtins.map (package: db.allDepsForPackage { inherit packages package _seen; }) selfDeps))
        )
    ;

    # Given a package set, and a list of package names, returns a list of package descriptions the packages depends on.
    # This is useful to describe a set of packages as a list of names
    allDepsForPackageNames =
      { packages # Output from e.g. `db.all`
      , names    # List of package names to resolved dependencies for
      }:
      db.allDepsForPackage {
        inherit packages;
        # Synthetic package desc
        package = {
          DEPENDS = names;
        };
      }
    ;
  };

  repo = {
    fetchPackage =
      { desc
      , repo
      , arch ? builtins.head (builtins.match "^([^-]+)-.*" builtins.currentSystem)
      }:

      let
        h = builtins.head;
        filename = h desc.FILENAME;
        sha256 = h desc.SHA256SUM;
      in
      builtins.fetchurl {
        url = "https://geo.mirror.pkgbuild.com/${repo}/os/${arch}/${filename}";
        inherit sha256;
      }
    ;
  };
}
