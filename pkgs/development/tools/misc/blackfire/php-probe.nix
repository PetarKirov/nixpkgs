{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, php
, writeShellScript
, curl
, jq
, common-updater-scripts
}:

assert lib.assertMsg (!php.ztsSupport) "blackfire only supports non zts versions of PHP";

let
  phpMajor = lib.versions.majorMinor php.version;

  version = "1.92.6";

  hashes = {
    "x86_64-linux" = {
      system = "amd64";
      hash = {
        "8.1" = "sha256-ygBgs6tGZyim69tCol+tTXV5Lt/JLuatmKAo9aomM1s=";
        "8.2" = "sha256-TrT7H2Tbu4ZrfeCUjpqlTMw9DAxS62aLvzTbpAdsZOc=";
        "8.3" = "sha256-AH/kYlpVjCwXxNa90Qe5XpzAdSyNn9jdeyYTLlXxfLI=";
      };
    };
    "i686-linux" = {
      system = "i386";
      hash = {
        "8.1" = "sha256-c1i6eq7l4LeUpuZCsYzS1N++IU4j0WydCxPokSJf6dI=";
        "8.2" = "sha256-gWhyUQ3QP13klusSv7KWdHatnjy/4k17VvHJUCtqF1g=";
        "8.3" = "sha256-kI3sVcI/bDVRMcjzPzlai1D2HvmBTXwQ3DF5zcp2GJk=";
      };
    };
    "aarch64-linux" = {
      system = "arm64";
      hash = {
        "8.1" = "sha256-1QPKTNOsJTrx+Q0MigiMBDCC7X3YlSDB33gy8DU9KBg=";
        "8.2" = "sha256-e3YUAOLWSmsiHczb44oRiOIafMSBWQaJY+m4OSUMzV8=";
        "8.3" = "sha256-h0/ZEy6IkIpAfeL0Al7a+FpPeX2KMSd7zD1i1ew5rUk=";
      };
    };
    "aarch64-darwin" = {
      system = "arm64";
      hash = {
        "8.1" = "sha256-gLCPTTCfoBgp3GgKzVisfGlxQsYa+4x2WDwvhwcf1R8=";
        "8.2" = "sha256-OtWUwkeLGfxkxjGSDMyv61UVoSwFo1puGjmwYOB51nI=";
        "8.3" = "sha256-M3lz0TnTuJVgD32RS3ffcZsKVJdyx75AjSKFkkODiSE=";
      };
    };
    "x86_64-darwin" = {
      system = "amd64";
      hash = {
        "8.1" = "sha256-dVau4kieQsj4m97Sepw1jMRtf1VCUnvZEJjVsO+hFWs=";
        "8.2" = "sha256-HRBVr4JTiZDRzIt6JfITD5N824Ivcag6DUyEhsc23co=";
        "8.3" = "sha256-nRRG42/Yhsupln4j7nWlKvfQ067fwQ17un1yXplPf14=";
      };
    };
  };

  makeSource = { system, phpMajor }:
    let
      isLinux = builtins.match ".+-linux" system != null;
    in
    assert !isLinux -> (phpMajor != null);
    fetchurl {
      url = "https://packages.blackfire.io/binaries/blackfire-php/${version}/blackfire-php-${if isLinux then "linux" else "darwin"}_${hashes.${system}.system}-php-${builtins.replaceStrings [ "." ] [ "" ] phpMajor}.so";
      hash = hashes.${system}.hash.${phpMajor};
    };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "php-blackfire";
  extensionName = "blackfire";
  inherit version;

  src = makeSource {
    system = stdenv.hostPlatform.system;
    inherit phpMajor;
  };

  nativeBuildInputs = lib.optionals stdenv.isLinux [
    autoPatchelfHook
  ];

  sourceRoot = ".";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -D ${finalAttrs.src} $out/lib/php/extensions/blackfire.so

    runHook postInstall
  '';

  passthru = {
    updateScript = writeShellScript "update-${finalAttrs.pname}" ''
      set -o errexit
      export PATH="${lib.makeBinPath [ curl jq common-updater-scripts ]}"
      NEW_VERSION=$(curl --silent https://blackfire.io/api/v1/releases | jq .probe.php --raw-output)

      if [[ "${version}" = "$NEW_VERSION" ]]; then
          echo "The new version same as the old version."
          exit 0
      fi

      for source in ${lib.concatStringsSep " " (builtins.attrNames finalAttrs.passthru.updateables)}; do
        update-source-version "$UPDATE_NIX_ATTR_PATH.updateables.$source" "0" "sha256-${lib.fakeSha256}"
        update-source-version "$UPDATE_NIX_ATTR_PATH.updateables.$source" "$NEW_VERSION"
      done
    '';

    # All sources for updating by the update script.
    updateables =
      let
        createName = path:
          builtins.replaceStrings [ "." ] [ "_" ] (lib.concatStringsSep "_" path);

        createSourceParams = path:
          let
            # The path will be either [«system» sha256], or [«system» sha256 «phpMajor» «zts»],
            # Let’s skip the sha256.
            rest = builtins.tail (builtins.tail path);
          in
          {
            system =
              builtins.head path;
            phpMajor =
              if builtins.length rest == 0
              then null
              else builtins.head rest;
          };

        createUpdateable = path: _value:
          lib.nameValuePair
            (createName path)
            (finalAttrs.finalPackage.overrideAttrs (attrs: {
              src = makeSource (createSourceParams path);
            }));

        # Filter out all attributes other than hashes.
        hashesOnly = lib.filterAttrsRecursive (name: _value: name != "system") hashes;
      in
      builtins.listToAttrs
        # Collect all leaf attributes (containing hashes).
        (lib.collect
          (attrs: attrs ? name)
          (lib.mapAttrsRecursive createUpdateable hashesOnly));
  };

  meta = {
    description = "Blackfire Profiler PHP module";
    homepage = "https://blackfire.io/";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ shyim ];
    platforms = [ "x86_64-linux" "aarch64-linux" "i686-linux" "x86_64-darwin" "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
