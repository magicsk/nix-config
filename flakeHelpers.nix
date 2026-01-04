inputs:
let
  homeManagerCfg = userPackages: extraImports: {
    home-manager.useGlobalPkgs = false;
    home-manager.extraSpecialArgs = {
      inherit inputs;
    };
    home-manager.users.magic_sk.imports = [
      inputs.agenix.homeManagerModules.default
      inputs.nix-index-database.homeModules.nix-index
      ./users/magic_sk/dots.nix
      ./users/magic_sk/age.nix
    ] ++ extraImports;
    home-manager.backupFileExtension = "bak";
    home-manager.useUserPackages = userPackages;
  };
in
{
  mkNixos = machineHostname: nixpkgsVersion: extraModules: rec {
    deploy.nodes.${machineHostname} = {
      hostname = machineHostname;
      profiles.system = {
        user = "root";
        sshUser = "magic_sk";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos nixosConfigurations.${machineHostname};
      };
    };
    nixosConfigurations.${machineHostname} = nixpkgsVersion.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        redlib-pkg = inputs.redlib-flake.packages.x86_64-linux.default;
      };
      modules = [
        ./homelab
        ./machines/nixos/_common
        ./machines/nixos/${machineHostname}
        ./modules/auto-aspm
        ./modules/qbittorrent
        inputs.agenix.nixosModules.default
        ./users/magic_sk
        (homeManagerCfg false [ ])
        inputs.impermanence.nixosModules.impermanence
      ] ++ extraModules;
    };
  };
  mkMerge = inputs.nixpkgs.lib.lists.foldl' (
    a: b: inputs.nixpkgs.lib.attrsets.recursiveUpdate a b
  ) { };
}

