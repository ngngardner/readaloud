{ nixpkgs, l }:
{
  nixfmt = {
    command = l.getExe nixpkgs.nixfmt;
    includes = [ "*.nix" ];
  };
  biome = {
    command = l.getExe nixpkgs.biome;
    options = [
      "format"
      "--write"
    ];
    includes = [
      "*.js"
      "*.ts"
    ];
  };
}
