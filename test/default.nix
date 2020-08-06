{ sources ? import ../nix/sources.nix
, pkgs ? import sources.nixpkgs { }
}:
let
  mock-httpd = import sources.mock-httpd { inherit pkgs; };

in
pkgs.nixosTest {
  name = "dns-scripts-test";

  nodes = {
    machine = { ... }: {
      imports = [ ../nixos ];
      environment.systemPackages = with pkgs; [ jq openssl ];

      dns-scripts = {
        dynamic.dns-made-easy = {
          enable = true;
          domain = "www.exampledomain.com";
          keys.api = "/tmp/key";
          keys.secret = "/tmp/key";
          url = "http://127.0.0.1:3210";
        };
      };

      # A web server for responding to DME requests:
      systemd.services.mock-httpd = {
        description = "Mock HTTP Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig.ExecStart =
          "${mock-httpd}/bin/mock-httpd ${./http.yml}";
      };

      systemd.services.dns-made-easy-update.after =
        [ "mock-httpd.service" ];
    };
  };


  testScript = ''
    start_all()
    machine.succeed("openssl rand -hex 10 > /tmp/key")
    machine.succeed("mkdir -p /tmp/json")
    machine.copy_from_host(
        "${./json/get-dns-managed.json}",
        "/tmp/json/get-dns-managed.json",
    )
    machine.copy_from_host(
        "${./json/get-dns-managed-record.json}",
        "/tmp/json/get-dns-managed-record.json",
    )
    machine.wait_for_unit("mock-httpd.service")
    machine.start_job("dns-made-easy-update.service")
    machine.wait_for_file("/tmp/json/record-update.json")

    machine.succeed("test $(jq -r .value < /tmp/json/record-update.json) != 1.1.1.1")
    machine.succeed("test -e /tmp/dyndns-ip-cache")
    machine.succeed(
        'test "$(jq -r .value < /tmp/json/record-update.json)"'
        ' = "$(head -1 /tmp/dyndns-ip-cache)"'
    )
  '';
}
