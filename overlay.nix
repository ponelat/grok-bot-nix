final: prev: {
  grok-bot = final.callPackage ./package.nix { };
  grok-bot-latest = final.callPackage ./latest.nix { inherit (final) grok-bot; };
}
