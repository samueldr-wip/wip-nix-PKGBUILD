#
# Library for parsing Arch Linux formats using Nix.
#
rec
{
  #
  # Generic helpers
  #

  # Identity function (it is the identity function).
  identity = x: x;

  # Strips the given chars from the start and end of the string.
  strip = char: builtins.match "^${char}*(.*[^${char}])?${char}+$";

  # Flattens one level of lists
  flatten = builtins.foldl' (fin: attr: fin ++ attr) [];

  # Reverses a list
  reverse = builtins.foldl' (coll: item: [item] ++ coll) [];

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

  firstChar = str: builtins.head (builtins.match "^(.).*" str);

  mergeDeep' = mergeOperations: first: second:
    first // second //
    (
      let
        common = builtins.intersectAttrs first second;
      in
      builtins.mapAttrs (
        name: value:
        let
          first' = first."${name}";
          second' = second."${name}";
          mergeOp = "${builtins.typeOf first'}+${builtins.typeOf second'}";
        in
        if mergeOperations ? "${mergeOp}"
        then (mergeOperations."${mergeOp}" mergeOperations first' second')
        else second'
      ) common
    )
  ;

  mergeOps' = {
    deep = {
      "set+set" =
        selfOps: mergeDeep' selfOps
      ;
    };
    shallow = {
      "set+set" =
        _: a: b: (a // b)
      ;
      # Shallow list+list
      "list+list" =
        _: a: b: a ++ b
      ;
    };
  };

  mergeAttrsDeep = mergeDeep' {
    "set+set" = mergeOps'.deep."set+set";
  };

  mergeAttrsDeepAndListsShallow = mergeDeep' {
    "set+set" = mergeOps'.deep."set+set";
    "list+list" = mergeOps'.shallow."list+list";
  };

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

    # db.all {
    #   path = ./path/to/unpacked/reponame;
    #   /* defaults to the basename of the target path */ repo = "reponame";
    # }
    all = { path, repo ? builtins.unsafeDiscardStringContext (builtins.baseNameOf path) }:
      let
        packagesAttrs =
          builtins.listToAttrs (builtins.attrValues (
            builtins.mapAttrs (packagePath: _type:
              let
                value = db.parse (builtins.readFile (path + "/${packagePath}/desc"));
              in
              {
                value = value // {
                  "$repo" = repo;
                };
                name = builtins.head value."NAME";
              }
            )
            (builtins.readDir path)
          ))
        ;
        packages = builtins.attrValues packagesAttrs;
      in
      {
        # This lets us attach a bit more data.
        "$db" = {
          "provides" =
            let
              nameOnly = entry: builtins.head (builtins.match "([^=]+).*" entry);
              # NOTE: This is losing the versioning information...
              #       This is *okay* since the use-case is to automatically cast
              #       a wide net around packages to fetch for using in the sandbox.
              list =
                flatten
                (builtins.map (package:
                  if !(package ? PROVIDES) then [] else
                  builtins.map
                  (provider: { name = nameOnly provider; value = builtins.head package.NAME; })
                  package.PROVIDES
                ) packages)
              ;
            in
            builtins.mapAttrs
            (provide: entries: builtins.map (entry: entry.value) entries)
            (builtins.groupBy (entry:
              entry.name
            ) list)
          ;
        };
      } // packagesAttrs
    ;

    # Given a list of `db.all` output, merge them appropriately.
    merge =
      builtins.foldl'
      (coll: curr:
        # We do NOT want to merge those deep.
        # Any repository defined after has priority for a same-name package.
        # TODO: verify this assumption is correct.
        coll //
        curr //
        {
          "$db" = mergeAttrsDeepAndListsShallow coll."$db" curr."$db";
        }
      )
      {
        "$db".provides = {};
      }
    ;

    # Given a package set, and a package description, returns a list of package descriptions it directly depends on.
    depsForPackage =
      { packages # Output from e.g. `db.all`
      , package  # A single package desc
      , _seen ? [] # Used internally to prevent infrec by keeping a tally of seen packages
      }:

      # From: PKGBUILD(5)
      # > depends (array)
      # >     An array of packages this package depends on to run. 
      # >     Entries in this list should be surrounded with single 
      # >     quotes and contain at least the package name. Entries can 
      # >     also include a version requirement of the form 
      # >     name<>version, where <> is one of five comparisons: >= 
      # >     (greater than or equal to), <= (less than or equal to), = 
      # >     (equal to), > (greater than), or < (less than).
      # >
      # >     If the dependency name appears to be a library (ends with 
      # >     .so), makepkg will try to find a binary that depends on the 
      # >     library in the built package and append the version needed 
      # >     by the binary. Appending the version yourself disables 
      # >     automatic detection.
      # >
      # >     Additional architecture-specific depends can be added by 
      # >     appending an underscore and the architecture name e.g., 
      # >     depends_x86_64=().
      let
        compOperators = [
          ">="  # (greater than or equal to)
          "<="  # (less than or equal to)
          "="   # (equal to)
          ">"   # (greater than)
          "<"   # (less than)
        ];
        parseDep = builtins.match "^([^><=]+)[><=]*(.*)$";
      in
      compact (
        builtins.map (depName:
          let
            parsed = parseDep depName;
            parsedDepName = builtins.head parsed;
            parsedDepPayload = builtins.tail parsed;
          in
          # Skips over packages already handled
          if builtins.elem parsedDepName _seen then null else

          # NOTE: This is losing the versioning information...
          #       This is *okay* since the use-case is to automatically cast
          #       a wide net around packages to fetch for using in the sandbox.

          # Is that dep in the packages set?
          if packages ? "${parsedDepName}"
          then packages."${parsedDepName}"
          else

          # Is that dep in the provides set?
          if packages."$db"."provides" ? ${parsedDepName}
          then (/* NOTE: incomplete semantics. Only picks whatever is first in the list. */
            let
              name = builtins.head packages."$db"."provides"."${parsedDepName}";
            in
            packages."${name}"
          )
          else
          (builtins.trace "WARNING: missing dep ${parsedDepName}... skipping it even though we shouldn't!" null)
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
    repos = { arch, name }: {
      #core = "https://geo.mirror.pkgbuild.com/core/os/${arch}/";
      #extra = "https://geo.mirror.pkgbuild.com/extra/os/${arch}/";
      # Relying on the archlinux packages archive, otherwise it's hard to
      # reproduce the builds, since inputs disappear eagerly.
      core  = "https://archive.archlinux.org/packages/${firstChar name}/${name}/";
      extra = "https://archive.archlinux.org/packages/${firstChar name}/${name}/";
    };
    fetchPackage =
      let _repos = repo.repos; in # Keep the right `repos` ref around to break infrec...
      { desc
      , repos ? _repos
      , repo ? desc."$repo"
      , arch ? builtins.head (builtins.match "^([^-]+)-.*" builtins.currentSystem)
      }:

      let
        h = builtins.head;
        name = h desc.NAME;
        filename = h desc.FILENAME;
        sha256 = h desc.SHA256SUM;
        storeEscape = builtins.replaceStrings [":"] ["__COLON__"];
      in
      {
        inherit filename;
        file = (builtins.fetchurl {
          name = storeEscape filename;
          url = (repos { inherit arch name; })."${repo}" + filename;
          inherit sha256;
        });
      }
    ;
  };
}
