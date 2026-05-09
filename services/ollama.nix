services.ollama = {
  enable = true;
  extraConfig = ''
    -host 0.0.0.0
    -port 9100
  '';
};