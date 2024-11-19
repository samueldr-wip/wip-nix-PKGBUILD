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
  };
}
