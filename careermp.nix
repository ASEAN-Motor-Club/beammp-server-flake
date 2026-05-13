{
  pkgs,
  lib,
  version ? "v0.0.37",
}: let
  src = pkgs.fetchFromGitHub {
    owner = "StanleyDudek";
    repo = "CareerMP";
    rev = version;
    hash = "sha256-dKzIAqWTEPS7BEQ58y6xMtUZbciwNlm4z14bWNImrFE=";
  };
in {
  inherit src;
  serverFiles = "${src}/Resources/Server/CareerMP";
  clientFiles = "${src}/Resources/Client";
  clientZip = "${src}/Resources/Client/CareerMP.zip";

  defaultConfig = {
    server = {
      autoUpdate = true;
      autoExit = true;
      longWindowMax = 10000;
      shortWindowMax = 1000;
      longWindowSeconds = 300;
      shortWindowSeconds = 30;
      allowTransactions = true;
      sessionSendingMax = 100000;
      sessionReceiveMax = 200000;
    };
    client = {
      localUnicycleGhost = false;
      remoteUnicycleGhost = true;
      remoteVehicleGhost = false;
      serverSaveName = "";
      serverSaveSuffix = "";
      serverSaveNameEnabled = false;
      roadTrafficAmount = 0;
      extraTrafficAmount = 0;
      parkedTrafficAmount = 0;
      roadTrafficEnabled = false;
      extraTrafficEnabled = false;
      parkedTrafficEnabled = false;
      worldEditorEnabled = false;
      consoleEnabled = false;
      simplifyRemoteVehicles = false;
      spawnVehicleIgnitionLevel = 0;
      skipOtherPlayersVehicles = false;
      trafficSmartSelections = true;
      trafficSimpleVehicles = true;
      trafficAllowMods = false;
    };
  };
}
