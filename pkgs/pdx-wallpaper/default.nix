{ runCommand, librsvg
# Tile size in pixels — the SVG is authored at 490×490 and tiles
# seamlessly, so the output PNG is square at `scale × 490`.
# 1 = native (490px), 2 = 980px, etc. Bumping this just changes how
# many tiles fit on screen — there's no resolution gain since the SVG
# vector renders at any size.
, scale ? 1
}:

let
  size = toString (scale * 490);
in
runCommand "pdx-carpet-${toString scale}x.png"
  {
    nativeBuildInputs = [ librsvg ];
    src = ./pdx-carpet.svg;
  } ''
    rsvg-convert -w ${size} -h ${size} -o $out $src
  ''
