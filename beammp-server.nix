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
      sha256 = "0dfri0xqrc9nyf3jdcrxppzb6jcdpfxbyj3l3lqwrni9xbig7a0c";
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
    assertions = lib.optionals cfg.enableCareerMP [
      {
        assertion = cfg.maxCars >= 100;
        message = "CareerMP requires maxCars >= 100, but maxCars is ${toString cfg.maxCars}";
      }
      {
        assertion = cfg.map == "/levels/west_coast_usa/info.json";
        message = "CareerMP requires map = /levels/west_coast_usa/info.json, but map is ${cfg.map}";
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
        MemoryHigh = "384M";
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
          cp --no-preserve=mode,ownership ${careermp.serverFiles}/careerMP.lua Resources/Server/CareerMP/
          cp --no-preserve=mode,ownership ${careermp.serverFiles}/versions/* Resources/Server/CareerMP/versions/ 2>/dev/null || true

          # Deploy CareerMP client mod
          cp --no-preserve=mode,ownership ${careermp.clientZip} Resources/Client/CareerMP.zip

          # Write merged config (Nix-managed, autoUpdate/autoExit forced off)
          cp --no-preserve=mode,ownership ${careermpConfigFile} Resources/Server/CareerMP/config/config.json
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
