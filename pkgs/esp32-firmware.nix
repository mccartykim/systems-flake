# ESPHome firmware build for ESP32-CAM-01
{
  stdenv,
  lib,
  esphome,
}:
stdenv.mkDerivation {
  name = "esp32-cam-01-firmware";
  src = ../esphome-configs;

  nativeBuildInputs = [esphome];

  buildPhase = ''
    # Copy config and secrets
    mkdir -p build
    cp esp32-cam-01.yaml build/

    # Check if secrets exist, otherwise create dummy
    if [ -f secrets.yaml ]; then
      cp secrets.yaml build/
    else
      echo "Warning: secrets.yaml not found, using dummy values"
      cat > build/secrets.yaml <<EOF
    wifi_ssid: "dummy"
    wifi_password: "dummy"
    api_encryption_key: "dummy=="
    ota_password: "dummy"
    ap_password: "dummy"
    EOF
    fi

    cd build
    esphome compile esp32-cam-01.yaml
  '';

  installPhase = ''
    mkdir -p $out
    cp -r esp32-cam-01 $out/
  '';
}
