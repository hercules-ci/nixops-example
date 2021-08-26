{ gnused, lib, mkEffect, nixUnstable, path, system, runCommand, openssh, rsync, hci }:

let
  # This shouldn't be necessary after flakes.
  # We don't use this for the actual deployment.
  getNixFiles = nixops: runCommand "${nixops.name}-nix-files" {
    inherit (nixops) plugins;
  } ''
    mkdir $out
    echo "[" >$out/all-plugins.nix
    notnull() {
      [[ $# > 0 ]]
    }
    for plugin in $plugins; do
      # NixOps itself
      if notnull $plugin/lib/python*/site-packages/nix; then
        echo "copying nixops nix exprs from $plugin"
        cp --no-preserve=mode -r $plugin/lib/python*/site-packages/nix/* $out
      elif notnull $plugin/lib/python*/site-packages/*/nix/default.nix; then
        defaultNix=$plugin/lib/python*/site-packages/*/nix/default.nix
        name=$(basename $(dirname $(dirname $defaultNix)))
        cp --no-preserve=mode -r $plugin/lib/python*/site-packages/$name/nix $out/$name
        echo "  ./$name" >>$out/all-plugins.nix
      else
        echo "warning: don't know how to gather Nix expressions from plugin $plugin. Does it have Nix expressions?"
      fi
        # echo "copying plugin nix exprs from $plugin"
        # Plugins usually define nix/default as the only `def nixexprs()`
        # cp $plugin/lib/python3.8/site-packages/*/nix/* $out
    done
    echo "]" >>$out/all-plugins.nix

    # Fixup NIX_PATH use
    sed -e 's^<nixops\([^>]*\)>^'$out'\1^g' -i $(find $out -type f -name "*\.nix")
    sed -e 's^<nixpkgs\([^>]*\)>^${path}\1^g' -i $(find $out -type f -name "*\.nix")

    (cd $out; patch --strip 2 <${./nixops.diff})

  '';

  prebuilt = {name, networkArgs, flake, nixops, prebuildOnlyNetworkFiles}: let
    nixFiles = getNixFiles nixops;
    machineInfo = import "${nixFiles}/eval-machine-info.nix" {
      inherit system;
      networkExprs = [ ./prebuild-stub.nix ] ++ prebuildOnlyNetworkFiles;
      flakeExpr = flake.nixopsConfigurations.default;
      flakeUri = flake.outPath;
      uuid = "00000000-0000-0000-0000-000000000000";
      deploymentName = name;
      args = networkArgs;
      pluginNixExprs = import "${nixFiles}/all-plugins.nix";
    };
    inherit (machineInfo) info;
    errorIf = c: e: if c then throw e else x: x;
    withChecks = x:
      errorIf (! info?network.storage || info?network.storage.legacy)
        "Your deployment must specify a remote storage solution, such as network.storage.hercules-ci." (
        lib.warnIf
          (! info?network.lock || info.network.lock == {} || info?network.lock.noop)
          "Your deployment does not specify remote lock driver, such as network.lock.hercules-ci. Concurrent use will result in lost state, misconfigured and/or redundant cloud resources and unexpectedly high expenses."
          x
        );
  in withChecks (
    machineInfo.machines { names = lib.attrNames machineInfo.nodes; } // {
      inherit machineInfo;
      inherit (machineInfo) network nodes;
    }
  );

  # Turn a value into a string that evaluates to that value in the Nix language.
  # Not currently in normal form.
  toNixExpr = v: "builtins.fromJSON \"" + lib.replaceStrings ["\$" "\"" "\\"] ["\\\$" "\\\"" "\\\\"] (builtins.toJSON v) + "\"";
in

args@{

  # Name of the deployment
  name ? "default",

  # NixOps network expressions and other files required for the deployment
  flake,

  # Nix values to pass as NixOps network arguments. Only serializable values are
  # supported. Support for functions could be added, but they'll have to be
  # passed as strings in Nix syntax.
  networkArgs ? {},

  # Override the Hercules CI State name if so desired. The default should
  # suffice.
  stateName ? "nixops/${name}.nixops",

  # Not all NixOps backends currently maintain known_hosts.
  knownHostsName ? "nixops/${name}.known_hosts",

  # Specify which secrets are to be loaded into the Effect sandbox.
  # For example { aws = "${env}-aws"; } will make the production-aws secret
  # available when env is "production"
  secretsMap ? {},

  nixops,

  prebuild ? true,

  # Prebuild runs outside of NixOps, which means that some info may be missing.
  # Specify extra network expressions here to fill in the missing definitions.
  prebuildOnlyNetworkFiles ? [],

  # Other variables are passed to mkEffect, which is similar to mkDerivation.
  ...
}:
mkEffect (
  {
    NIX_PATH="nixpkgs=${path}";
  }
  //  lib.filterAttrs (k: v: k != "networkArgs" && k != "flake") args
    // lib.optionalAttrs prebuild {
        prebuilt = prebuilt { 
          inherit name networkArgs flake nixops prebuildOnlyNetworkFiles;
        };
      }
    // {
  name = "nixops-${name}";
  src = flake.outPath;
  inputs = [ nixUnstable nixops openssh rsync hci ];

  # Like `args // `, but also sets the defaults
  inherit stateName knownHostsName;
  NIXOPS_DEPLOYMENT = args.NIXOPS_DEPLOYMENT or name;

  effectScript = ''
    nixops deploy \
      --confirm \
      ;
  '';

  # We assume that `check` is idempotent and not required for any other operations.
  # To quote the NixOps help:
  #   check the state of the machines in the network (note that this might alter
  #   the internal nixops state to consolidate with the real state of the resource)
  effectCheckScript = ''
    nixops check
  '';

  priorCheckScript = ''
    nixops check
  '';

})
