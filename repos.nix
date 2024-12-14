{ seed }:

let
  date = "2024/12/13";
  dbURL = repo: "https://archive.archlinux.org/repos/${date}/${repo}/os/x86_64/${repo}.db.tar.gz";
  repos = builtins.mapAttrs
    (name: hash: builtins.fetchurl { url = dbURL name; sha256 = hash; })
    {
      "core" = "sha256:0lrsjqm9izgflgcl6vq7f94zc5qvfwqnx67a97922qq17vqlssax";
      "extra" = "sha256:01bivs5cr9hn4xjnng5w9qzfifvk8im292ckv53hmx8bp933bcbm";
    }
  ;
in

derivation {
  name = "repositories";
  system = "x86_64-linux";
  builder = "${seed}/bin/ash";
  PATH = "${seed}/bin/";
  passAsFile = [
    "buildScript"
  ];
  args = [
    (builtins.toFile "shim.sh" ''
      exec sh "$buildScriptPath"
    '')
  ];
  buildScript = ''
    set -x
    mkdir -p $out
    cd $out
    ${builtins.concatStringsSep "\n" (
      builtins.map (repo:
      ''
        (
        mkdir -p ${repo}
        cd ${repo}
        tar xf "${repos.${repo}}"
        )
      ''
      ) (builtins.attrNames repos)
    )}
  '';
}
