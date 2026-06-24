# In-repo replacement for the divnix/hive + std + paisano stack
# (all upstream-dormant since 2024/2025, and the source of recurring
# GC-reaped `builtins.path` store-copy failures in downstream flakes
# that consume this one). Vendors the ~10% this repo actually used.
{ inputs, systems }:
let
  inherit (inputs.nixpkgs) lib;
in
{
  grow = import ./grow.nix { inherit lib; };
  # per-system mkShell/mkNixago injected into the cell import signature
  vendor = import ./shell.nix { inherit inputs systems; };
}
