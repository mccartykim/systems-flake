{ runCommand, librsvg
# Tile size knob. Accepts either an integer (1 → 490px tile, 2 → 980px, …)
# or a float (1.0/3.0 → ~163px, 0.5 → 245px, …). Fractional scales are
# floored to the nearest integer pixel because rsvg-convert wants ints.
# The SVG is authored at 490×490 and tiles seamlessly, so scaling just
# changes how many tiles fit on screen — there's no resolution gain or
# loss since it's vector-rendered.
, scale ? 1
}:

let
  rawPixels = scale * 490.0;
  intPixels =
    if builtins.typeOf scale == "int" then scale * 490
    else builtins.floor rawPixels;
  size = toString intPixels;
in
runCommand "pdx-carpet-${size}px.png"
  {
    nativeBuildInputs = [ librsvg ];
    src = ./pdx-carpet.svg;
  } ''
    rsvg-convert -w ${size} -h ${size} -o $out $src
  ''
