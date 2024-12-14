{ seed }:

let
  date = "2024/11/18";
  dbURL = repo: "https://archive.archlinux.org/repos/${date}/${repo}/os/x86_64/${repo}.db.tar.gz";
  repos = builtins.mapAttrs
    (name: hash: builtins.fetchurl { url = dbURL name; sha256 = hash; })
    {
      "core" = "sha256:0vjb7ma8ydw4jcn3fkf4i63d95zik7wabvv6iakiaybripwg9agb";
      "extra" = "sha256:1ry48nd0c88qs5dnr30s0qsz92x2l02y0j0m26hf04cz5zckjh7h";
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
