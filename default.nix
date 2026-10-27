# Old-style (flake-less) entry point:
#   pkgs.callPackage ./default.nix { }            -> pinned `grok-bot`
#   (import ./default.nix { inherit pkgs; }).latest -> "always latest at launch" variant
{ pkgs ? import <nixpkgs> { } }:
let
  grok-bot = pkgs.callPackage ./package.nix { };
in
grok-bot.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    latest = pkgs.callPackage ./latest.nix { inherit grok-bot; };
  };
})
