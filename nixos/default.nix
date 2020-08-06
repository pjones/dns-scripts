{ pkgs, lib, config, ... }:
let
  cfg = config.dns-scripts;
  package = pkgs.callPackage ../. { };
in
{
  ###### Interface
  options.dns-scripts = {
    dynamic = {
      dns-made-easy = {
        enable = lib.mkEnableOption "Update DNS Made Easy Records";

        domain = lib.mkOption {
          type = lib.types.str;
          example = "host.example.com";
          description = ''
            The host and domain to update.
          '';
        };

        keys = {
          api = lib.mkOption {
            type = lib.types.path;
            description = ''
              A file that contains the API key to use.
            '';
          };

          secret = lib.mkOption {
            type = lib.types.path;
            description = ''
              A file that contains the secret key to use.
            '';
          };
        };

        url = lib.mkOption {
          type = lib.types.str;
          default = "https://api.dnsmadeeasy.com/V2.0";
          description = ''
            The base URL to the DME API.
          '';
        };
      };
    };
  };

  ###### Implementation
  config = lib.mkMerge
    [
      (lib.mkIf cfg.dynamic.dns-made-easy.enable {
        systemd.services.dns-made-easy-update = {
          description = "Update DNS Made Easy Records";
          after = [ "network-online.target" ];
          serviceConfig.Type = "simple";
          serviceConfig.ExecStart =
            let
              script = "${package}/bin/update-dyndns.sh";
              args =
                [
                  "-d ${cfg.dynamic.dns-made-easy.domain}"
                  "-a ${cfg.dynamic.dns-made-easy.keys.api}"
                  "-s ${cfg.dynamic.dns-made-easy.keys.secret}"
                  "-A ${cfg.dynamic.dns-made-easy.url}"
                ];
            in
            "${script} " + lib.concatStringsSep " " args;
        };

        systemd.timers.dns-made-easy-update = {
          description = "Update DNS Made Easy Records";
          wantedBy = [ "timers.target" ];
          timerConfig.OnBootSec = "10min";
          timerConfig.OnUnitInactiveSec = "10min";
          timerConfig.Unit = "dns-made-easy-update.service";
        };
      })
    ];
}
