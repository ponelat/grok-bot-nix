{
  description = "Unofficial Nix packaging of the Grok Bot Linux AppImage";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      # Grok Bot is unfree; allow it for this flake's own outputs.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      overlay = import ./overlay.nix;
    in
    {
      overlays.default = overlay;

      packages = forAllSystems (
        system:
        let
          pkgs = (pkgsFor system).extend overlay;
        in
        {
          inherit (pkgs) grok-bot grok-bot-latest;
          default = pkgs.grok-bot;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.grok-bot}/bin/grok-bot";
        };
        grok-bot-latest = {
          type = "app";
          program = "${self.packages.${system}.grok-bot-latest}/bin/grok-bot-latest";
        };
      });

      # NixOS: `imports = [ grok-bot.nixosModules.default ]; programs.grok-bot.enable = true;`
      # (you still need nixpkgs.config.allowUnfree = true; or an allowUnfreePredicate)
      nixosModules.default =
        { config, lib, pkgs, ... }:
        {
          options.programs.grok-bot = {
            enable = lib.mkEnableOption "Grok Bot (unofficial AppImage package)";
            latest = lib.mkEnableOption "the always-latest-at-launch variant (grok-bot-latest) instead of the pinned build";
          };
          config = lib.mkIf config.programs.grok-bot.enable {
            nixpkgs.overlays = [ overlay ];
            environment.systemPackages = [
              (if config.programs.grok-bot.latest then pkgs.grok-bot-latest else pkgs.grok-bot)
            ];
          };
        };

      # Home Manager: `imports = [ grok-bot.homeManagerModules.default ]; programs.grok-bot.enable = true;`
      homeManagerModules.default =
        { config, lib, pkgs, ... }:
        {
          options.programs.grok-bot = {
            enable = lib.mkEnableOption "Grok Bot (unofficial AppImage package)";
            latest = lib.mkEnableOption "the always-latest-at-launch variant (grok-bot-latest)";
          };
          config = lib.mkIf config.programs.grok-bot.enable {
            nixpkgs.overlays = [ overlay ];
            home.packages = [
              (if config.programs.grok-bot.latest then pkgs.grok-bot-latest else pkgs.grok-bot)
            ];
          };
        };

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
