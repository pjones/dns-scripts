{ pkgs ? import <nixpkgs> { }
}:

with pkgs.lib;

pkgs.stdenvNoCC.mkDerivation rec {
  name = "dns-scripts";
  meta.description = "Peter's DNS scripts";
  phases = [ "installPhase" "fixupPhase" ];
  src = ./.;

  buildInputs = with pkgs; [
    coreutils
    curl
    gawk
    jq
    net_snmp
    nettools
    openssl
    iproute
  ];

  installPhase = ''
    mkdir -p $out/bin
    export extra_path="${concatMapStringsSep ":" (x: "${x}/bin") buildInputs}"

    substituteAll ${./bin/update-dyndns.sh} $out/bin/update-dyndns.sh
    substituteAll ${./bin/dnsme-letsencrypt.sh} $out/bin/dnsme-letsencrypt.sh

    chmod 0555 $out/bin/update-dyndns.sh
    chmod 0555 $out/bin/dnsme-letsencrypt.sh
  '';
}
