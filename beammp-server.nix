{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.services.beammp-server;

  careermp = import ./careermp.nix {
    inherit pkgs lib;
    version = cfg.careerMPVersion;
  };

  rlsMods = import ./rls-mods.nix {
    inherit pkgs lib;
    rlsCompatReleaseVersion = cfg.rlsCompatPatchVersion;
    enableRiverHighway = cfg.enableRiverHighway;
  };

  beamcomp = import ./beamcomp.nix {
    inherit pkgs lib;
    version = cfg.beamCompVersion;
  };

  userServerOverrides = cfg.careerMPConfig.server or {};
  userClientOverrides = cfg.careerMPConfig.client or {};

  mergedConfig = {
    server = lib.recursiveUpdate (lib.recursiveUpdate careermp.defaultConfig.server userServerOverrides) {
      autoUpdate = false;
      autoExit = false;
    };
    client = lib.recursiveUpdate careermp.defaultConfig.client userClientOverrides;
  };

  careermpConfigFile = pkgs.writeText "careermp-config.json" (builtins.toJSON mergedConfig);

  discordNotify = pkgs.writeShellScript "discord-notify" ''
    WEBHOOK_URL="$1"
    MESSAGE="$2"
    ${pkgs.curl}/bin/curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$MESSAGE" > /dev/null 2>&1 || true
  '';

  beammp-server-bin = pkgs.stdenv.mkDerivation {
    pname = "beammp-server";
    version = cfg.serverVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/BeamMP/BeamMP-Server/releases/download/${cfg.serverVersion}/BeamMP-Server.debian.12.x86_64";
      sha256 = "1wfnw8kxrnywpfl7149hl70si2hn3j5baplcwg8f3qibaiix894d";
    };
    nativeBuildInputs = [pkgs.autoPatchelfHook];
    buildInputs = [pkgs.lua5_3 pkgs.curl pkgs.stdenv.cc.cc.lib];
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/BeamMP-Server
      chmod +x $out/bin/BeamMP-Server
    '';
    meta.mainProgram = "BeamMP-Server";
  };

  serverConfigFile = pkgs.writeText "ServerConfig.toml" ''
    [General]
    Port = ${toString cfg.port}
    AuthKey = ""
    Name = "${cfg.name}"
    Description = "${cfg.description}"
    Tags = "${cfg.tags}"
    MaxPlayers = ${toString cfg.maxPlayers}
    MaxCars = ${toString cfg.maxCars}
    Map = "${cfg.map}"
    Private = ${
      if cfg.isPrivate
      then "true"
      else "false"
    }
    AllowGuests = ${
      if cfg.allowGuests
      then "true"
      else "false"
    }
    LogChat = ${
      if cfg.logChat
      then "true"
      else "false"
    }
    Debug = ${
      if cfg.debug
      then "true"
      else "false"
    }
    IP = "::"
    InformationPacket = true
    ResourceFolder = "Resources"
    ${cfg.extraConfig}
  '';
in {
  imports = [
    ./logger.nix
  ];
  options.services.beammp-server = mkOption {
    type = types.submodule (import ./backend-options.nix);
  };

  config = mkIf cfg.enable {
    assertions =
      lib.optionals cfg.enableCareerMP [
        {
          assertion = cfg.maxCars >= 100;
          message = "CareerMP requires maxCars >= 100, but maxCars is ${toString cfg.maxCars}";
        }
        {
          assertion =
            cfg.map
            == "/levels/west_coast_usa/info.json"
            || (cfg.enableRiverHighway && cfg.map == "/levels/river_highway/info.json");
          message = "CareerMP requires map = /levels/west_coast_usa/info.json (or /levels/river_highway/info.json with enableRiverHighway), but map is ${cfg.map}";
        }
      ]
      ++ lib.optionals cfg.enableRLS [
        {
          assertion = cfg.enableCareerMP;
          message = "enableRLS requires enableCareerMP to be true";
        }
      ]
      ++ lib.optionals cfg.enableRiverHighway [
        {
          assertion = cfg.enableRLS;
          message = "enableRiverHighway requires enableRLS to be true";
        }
        {
          assertion = cfg.map == "/levels/river_highway/info.json";
          message = "enableRiverHighway requires map = /levels/river_highway/info.json";
        }
      ]
      ++ lib.optionals cfg.enableBeamComp [
        {
          assertion = cfg.maxCars >= 64;
          message = "BeamComp needs maxCars >= 64 (1 own car + ~40 race props + 16 AI), but maxCars is ${toString cfg.maxCars}";
        }
      ];

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
      allowedUDPPorts = [cfg.port];
    };

    users.groups.${cfg.group} = {};

    users.users.${cfg.user} = {
      isNormalUser = true;
      group = cfg.group;
    };

    systemd.services.beammp-server = {
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      description = "BeamMP Dedicated Server (BeamNG.drive)";
      path = lib.optionals cfg.enableCareerMP [pkgs.wget];
      environment =
        {
          BEAMMP_PORT = toString cfg.port;
          BEAMMP_NAME = cfg.name;
          BEAMMP_MAX_PLAYERS = toString cfg.maxPlayers;
          BEAMMP_MAX_CARS = toString cfg.maxCars;
          BEAMMP_MAP = cfg.map;
          BEAMMP_PRIVATE =
            if cfg.isPrivate
            then "true"
            else "false";
          BEAMMP_ALLOW_GUESTS =
            if cfg.allowGuests
            then "true"
            else "false";
          BEAMMP_LOG_CHAT =
            if cfg.logChat
            then "true"
            else "false";
          BEAMMP_DEBUG =
            if cfg.debug
            then "true"
            else "false";
          BEAMMP_DESCRIPTION = cfg.description;
          BEAMMP_TAGS = cfg.tags;
          BEAMMP_RESOURCE_FOLDER = "Resources";
        }
        // cfg.environment;
      unitConfig = lib.mkIf (cfg.discordWebhookEnvironmentFile != null) {
        OnFailure = "beammp-server-crash-notify.service";
      };
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        RestartSec = "10s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = 300;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "770";
        WorkingDirectory = "/var/lib/${cfg.stateDirectory}";

        # Allow IPv6 — the server binds to :: for dual-stack (IPv4+IPv6) support.
        # This fixes the Boost.Asio bad_address_cast bug where the binary creates an
        # IPv6 acceptor but the IPv4 bind (0.0.0.0) causes a family mismatch.
        RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX AF_NETLINK";

        # === Resource isolation (protect Motor Town) ===
        CPUAffinity = cfg.cpuAffinity;
        CPUQuota = cfg.cpuQuota;
        MemoryMax = cfg.memoryMax;
        MemoryHigh = cfg.memoryHigh;
        MemorySwapMax = "0";
        OOMScoreAdjust = 500;
        Nice = "0";
        IOSchedulingClass = "idle";
        LimitNOFILE = "65536";
      };
      preStart = ''
        mkdir -p Resources/Client Resources/Server
        cp --no-preserve=mode,ownership ${serverConfigFile} ServerConfig.toml
        ${lib.optionalString (cfg.authKeyFile != null) ''
          if [ -s "${cfg.authKeyFile}" ]; then
            # Secret may be raw key or KEY=value format (EnvironmentFile)
            AUTH_KEY=$(sed -n 's/^BEAMMP_AUTH_KEY=//p' "${cfg.authKeyFile}")
            if [ -z "$AUTH_KEY" ]; then
              AUTH_KEY=$(tr -d '[:space:]' < "${cfg.authKeyFile}")
            fi
            sed -i "s/AuthKey = \"\"/AuthKey = \"$AUTH_KEY\"/" ServerConfig.toml
          else
            echo "WARNING: auth key file is empty or missing: ${cfg.authKeyFile}" >&2
          fi
        ''}
        ${lib.optionalString cfg.enableCareerMP ''
          # Deploy CareerMP server resources
          mkdir -p Resources/Server/CareerMP/config Resources/Server/CareerMP/versions
          ${
            if cfg.enableRLS
            then ''
              # Deploy the complete ready-to-use SERVER tree from the RLS package.
              # It carries the patched careerMP.lua, the Banking app bridge,
              # CareerMPBanking and CareerMPPartySharedVehicles. Copy the whole
              # tree instead of enumerating files: a new bundle release can add
              # modules (e.g. beta.17/18 additions) and a missed file breaks
              # client join at load.
              cp --no-preserve=mode,ownership -r ${rlsMods.activeServerDir}/. Resources/Server/
            ''
            else ''
              cp --no-preserve=mode,ownership ${careermp.serverFiles}/careerMP.lua Resources/Server/CareerMP/
            ''
          }
          cp --no-preserve=mode,ownership ${careermp.serverFiles}/versions/* Resources/Server/CareerMP/versions/ 2>/dev/null || true

          # Deploy CareerMP client mods (RLS bundle carries 6: CareerMP,
          # CareerMPBanking, PartySharedVehicles, RaceTab, CareerMP-Tablet, RLS).
          # mods.json lists every one of them by name + hash, so the whole Client
          # dir must land in Resources/Client — enumerating files here silently
          # desyncs mods.json and clients fail to fetch the missing mods.
          ${
            if cfg.enableRLS
            then ''
              cp --no-preserve=mode,ownership -r ${rlsMods.activeClientDir}/. Resources/Client/
              cp --no-preserve=mode,ownership ${rlsMods.modsJson} Resources/Client/mods.json
            ''
            else ''
              cp --no-preserve=mode,ownership ${careermp.clientZip} Resources/Client/CareerMP.zip
            ''
          }

          # Deploy River Highway mods if enabled
          # Note: The PHI map zip (1.6GB) is deployed here for server-side map loading.
          # BeamMP will try to push it to clients but it's too large for reliable transfer.
          # CareerMP also regenerates mods.json from files on disk, so filtering won't work.
          # Players may need to install PHI from the BeamNG mod repository if server transfer fails.
          ${lib.optionalString (cfg.enableRiverHighway && rlsMods.riverHighwayDeltaZip != null) ''
            cp --no-preserve=mode,ownership ${rlsMods.riverHighwayDeltaZip} "Resources/Client/${rlsMods.riverHighwayDeltaZipName}"
          ''}
          ${lib.optionalString (cfg.enableRiverHighway && rlsMods.riverHighwayMapZip != null) ''
            cp --no-preserve=mode,ownership ${rlsMods.riverHighwayMapZip} Resources/Client/River_Highway_Rework_PHI.zip
          ''}

          # Write merged config (Nix-managed, autoUpdate/autoExit forced off)
          cp --no-preserve=mode,ownership ${careermpConfigFile} Resources/Server/CareerMP/config/config.json
        ''}
        ${lib.optionalString cfg.enableBeamComp ''
          # BeamComp: client mod BeamMP hands to players, plus the server-side
          # racing plugin. config/grids/presets are club state and are seeded
          # exactly once (-n): BeamComp's own update notes require them to
          # survive updates and restarts.
          mkdir -p Resources/Client Resources/Server/BeamComp
          cp --no-preserve=mode,ownership ${beamcomp.clientZip} Resources/Client/BeamComp.zip
          cp -n --no-preserve=mode,ownership ${beamcomp.serverDir}/*.lua Resources/Server/BeamComp/ 2>/dev/null || true
          cp -n --no-preserve=mode,ownership ${beamcomp.serverDir}/COMMANDS.md ${beamcomp.serverDir}/README.md Resources/Server/BeamComp/ 2>/dev/null || true
          ${lib.concatMapStrings (f: ''
            cp -n --no-preserve=mode,ownership ${beamcomp.serverDir}/${f} Resources/Server/BeamComp/${f} 2>/dev/null || true
          '') beamcomp.stateFiles}
          chown -R beammp:beammp Resources/Server/BeamComp Resources/Client/BeamComp.zip 2>/dev/null || true
        ''}
      '';
      script = ''
        exec ${lib.getExe beammp-server-bin}
      '';
    };

    systemd.services.beammp-server-crash-notify = lib.mkIf (cfg.discordWebhookEnvironmentFile != null) {
      description = "Send beammp-server crash logs to Discord";
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.discordWebhookEnvironmentFile;
      };
      path = [pkgs.systemd pkgs.coreutils pkgs.gnused pkgs.jq];
      script = ''
        set -euo pipefail

        JOURNAL_LOGS=$(journalctl -u beammp-server.service -n 50 --no-pager --output=short 2>&1 || echo "(failed to read journal)")
        JOURNAL_LOGS=$(echo "$JOURNAL_LOGS" | tail -c 900)

        PAYLOAD=$(jq -n \
          --arg journal "$JOURNAL_LOGS" \
          '{
            embeds: [{
              title: "💥 beammp-server crashed",
              color: 14495300,
              fields: [
                { name: "📋 Server Journal (last lines)", value: ("```\n" + $journal + "\n```") }
              ]
            }]
          }')

        ${discordNotify} "$DISCORD_ERRORS_WEBHOOK" "$PAYLOAD"
      '';
    };

    systemd.services.beammp-server-restart = {
      enable = cfg.restartSchedule != null;
      description = "BeamMP Dedicated Server Restart";
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        systemctl restart beammp-server
      '';
    };

    systemd.timers.beammp-server-restart = {
      enable = cfg.restartSchedule != null;
      description = "Timer to restart BeamMP server";
      timerConfig = {
        OnCalendar = cfg.restartSchedule;
        AccuracySec = "1min";
        Unit = "beammp-server-restart.service";
      };
      wantedBy = ["timers.target"];
    };

    services.beammp-server-logger = {
      enable = cfg.enableLogStreaming;
      serverLogsPath = "/var/lib/${cfg.stateDirectory}/Server.log";
      tag = cfg.logsTag;
      inherit (cfg) relpServerHost relpServerPort;
    };
  };
}
