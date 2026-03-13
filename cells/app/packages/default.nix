{
  inputs,
  cell,
}:
let
  readaloud = import ./readaloud { inherit inputs cell; };
in
{
  inherit readaloud;
  default = readaloud;
}
