# eMudhra intermediate CA compromise (Oct 2026).
#
# Shared by hosts and NixOS containers. NSS 3.131.1 removes the emSign roots
# that signed the eight compromised intermediates, but nixpkgs still ships
# cacert 3.126. NixOS containers evaluate their own `security.pki`, so they
# do not inherit the host's blacklist. Reference: CVE-2026-111943 and
# https://emudhra.we-have-a-problem.com/
{ ... }: {
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
    "emSign ECC Root CA - G3"
    "emSign Root CA - C1"
    "emSign ECC Root CA - C3"
  ];
}
