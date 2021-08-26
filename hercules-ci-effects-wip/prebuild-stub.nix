{
  defaults = { lib, ... }:
    let
      inherit (lib) types;
      inherit (types) attrsOf unspecified;
    in {
      config = {
        boot.loader.grub.enable = lib.mkForce false;
        fileSystems."/".device = lib.mkDefault "/no-root-fs-for-prebuild";
      };
      options = {
        # TODO: import nixos contrib
        deployment.autoLuks = lib.mkOption { default = {}; type = attrsOf (attrsOf unspecified); };
      };
    };
}
