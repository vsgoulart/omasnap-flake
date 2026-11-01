{
  description = "Omasnap screenshot editor, repackaged from upstream release artifacts";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # Pinned upstream artifacts; maintained by scripts/update.sh.
      source = lib.importJSON ./sources.json;

      systems = [ "x86_64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkPackages = pkgs: {
        omasnap = pkgs.callPackage ./nix/package.nix { inherit source; };

        omasnap-niri = pkgs.callPackage ./nix/package.nix {
          inherit source;
          niriCompat = true;
        };
      };
    in
    {
      overlays.default = final: _prev: mkPackages final;

      packages = forAllSystems (
        pkgs:
        let
          packages = mkPackages pkgs;
        in
        packages // { default = packages.omasnap; }
      );

      checks = forAllSystems (pkgs: mkPackages pkgs);

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
