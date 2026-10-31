{
  pkgs,
  lib,
  version,
}:
let
  # The release tag is "v0.10.0" but the asset drops the leading "v":
  # BeamComp-0.10.0.zip. Getting this wrong fails at build time with a 404.
  assetVersion = lib.removePrefix "v" version;
  src = pkgs.fetchzip {
    url = "https://github.com/ReneKnap/BeamComp/releases/download/${version}/BeamComp-${assetVersion}.zip";
    hash = "sha256-a2+TjbdLIJzkvhd7IY7Tw0V+YmaNQRQdFEu1vrn8rFo="; # v0.10.0
  };
in {
  inherit src;
  # The mod BeamMP hands to every joining player.
  clientZip = "${src}/Resources/Client/BeamComp.zip";
  # The server-side plugin directory (main.lua + envelope.lua + data files).
  serverDir = "${src}/Resources/Server/BeamComp";
  # Club state, not shipped defaults: seeded once at first install and never
  # overwritten afterwards. BeamComp's own update notes require these three to
  # survive an update (grids and saved setups are authored in-game).
  stateFiles = [
    "beamcomp.config.ini"
    "beamcomp.grids.json"
    "beamcomp.presets.json"
  ];
}
