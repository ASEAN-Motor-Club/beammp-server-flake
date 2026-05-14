{
  pkgs,
  lib,
  version ? "v1.0.0-beta.16",
}: let
  src = pkgs.fetchFromGitHub {
    owner = "ChiarelloB";
    repo = "RLS-CareerMP-Compatibility-Patch---Online-Career-Mode";
    rev = version;
    hash = "sha256-1CXYqfg7NpgLo7LglYV3N0Oqv/JLqJDWdtsNJOocsLw=";
  };
in {
  inherit src;
  scriptsDir = "${src}/scripts";
  serverHotfixScript = "${src}/scripts/apply_server_hotfix.py";
  zipUtils = "${src}/scripts/zip_utils.py";
}
