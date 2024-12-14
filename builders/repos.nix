{ seed }:

{ date, repos }:

let
  # Break infrec
  repos' = repos;
in
let
  dbURL = repo: "https://archive.archlinux.org/repos/${date}/${repo}/os/x86_64/${repo}.db.tar.gz";
  repos = builtins.mapAttrs
    (name: hash: builtins.fetchurl { url = dbURL name; sha256 = hash; })
    repos'
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

