{
  pkgs,
  lib,
  careermp,
  rlsCompatPatch,
  rlsCompatReleaseVersion ? "v1.0.0-beta.16",
  enableRiverHighway ? false,
}: let
  readyToUse = pkgs.fetchzip {
    url = "https://github.com/ChiarelloB/RLS-CareerMP-Compatibility-Patch---Online-Career-Mode/releases/download/${rlsCompatReleaseVersion}/rls-careermp-ready-to-use-${rlsCompatReleaseVersion}.zip";
    hash = "sha256-2DMAXe0PNDylmTbybhWedOVjuuYmwWrj5mbrJAbt+vM=";
    stripRoot = false;
  };

  riverHighwayCore =
    if enableRiverHighway
    then
      pkgs.fetchzip {
        url = "https://github.com/ChiarelloB/RLS-CareerMP-Compatibility-Patch---Online-Career-Mode/releases/download/river-highway-beta-0.0.6/rls-careermp-river-ready-to-use-v0.0.6-core.zip";
        hash = "sha256-75H/qqXSQWmve2zPa82NTWloLwPYlbLpAjRh2DgNaWM=";
        stripRoot = false;
      }
    else null;

  riverHighwayMap =
    if enableRiverHighway
    then
      pkgs.fetchzip {
        url = "https://github.com/ChiarelloB/RLS-CareerMP-Compatibility-Patch---Online-Career-Mode/releases/download/river-highway-beta-0.0.6/rls-careermp-river-ready-to-use-v0.0.6-map.zip";
        hash = "sha256-BTMVC3I2P0ptvjl6afSBJV01b3GliegYq1oyrmVCVY8=";
        stripRoot = false;
      }
    else null;

  activeClientDir =
    if enableRiverHighway && riverHighwayCore != null
    then "${riverHighwayCore}/Resources/Client"
    else "${readyToUse}/Resources/Client";

  activeServerDir =
    if enableRiverHighway && riverHighwayCore != null
    then "${riverHighwayCore}/Resources/Server"
    else "${readyToUse}/Resources/Server";

  patchedCareerMPLua =
    pkgs.runCommand "careermp-hotfixed-lua" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      mkdir -p $out
      mkdir -p workdir/Resources/Server/CareerMP
      cp ${careermp.serverFiles}/careerMP.lua workdir/Resources/Server/CareerMP/careerMP.lua
      cp ${rlsCompatPatch.serverHotfixScript} apply_server_hotfix.py
      python apply_server_hotfix.py --server-root workdir --no-backup
      cp workdir/Resources/Server/CareerMP/careerMP.lua $out/careerMP.lua
    '';
in {
  patchedCareerMPZip = "${activeClientDir}/CareerMP.zip";
  patchedCareerMPBankingZip = "${activeClientDir}/CareerMPBanking.zip";
  patchedCareerMPPartySharedZip = "${activeClientDir}/CareerMPPartySharedVehicles.zip";
  patchedRLSZip =
    if enableRiverHighway && riverHighwayCore != null
    then "${activeClientDir}/rls_career_overhaul_2.6.5.2_careermp_compatible.zip"
    else "${activeClientDir}/rls_career_overhaul_2.6.5.4_careermp_compatible.zip";
  patchedRLSZipName =
    if enableRiverHighway && riverHighwayCore != null
    then "rls_career_overhaul_2.6.5.2_careermp_compatible.zip"
    else "rls_career_overhaul_2.6.5.4_careermp_compatible.zip";
  patchedServerLua = "${patchedCareerMPLua}/careerMP.lua";
  activeServerDir = activeServerDir;
  activeClientDir = activeClientDir;
  riverHighwayDeltaZip =
    if riverHighwayCore != null
    then "${riverHighwayCore}/Resources/Client/rls_career_overhaul_river_highway_beta_0.0.6_careermp_delta.zip"
    else null;
  riverHighwayDeltaZipName = "rls_career_overhaul_river_highway_beta_0.0.6_careermp_delta.zip";
  riverHighwayMapZip =
    if riverHighwayMap != null
    then "${riverHighwayMap}/Resources/Client/River_Highway_Rework_PHI.zip"
    else null;
}
