{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  gtk3,
  glib,
  pango,
  cairo,
  atk,
  gdk-pixbuf,
  harfbuzz,
  libepoxy,
  fontconfig,
  libGL,
  jdk11,
}: let
  release = builtins.fromJSON (builtins.readFile ./release.json);
in
  stdenv.mkDerivation {
    pname = "haqor";
    inherit (release) version;
    src = fetchurl {inherit (release) url hash;};
    sourceRoot = ".";

    nativeBuildInputs = [autoPatchelfHook wrapGAppsHook3 makeWrapper copyDesktopItems];
    buildInputs = [gtk3 glib pango cairo atk gdk-pixbuf harfbuzz libepoxy fontconfig stdenv.cc.cc.lib jdk11];
    dontBuild = true;
    dontWrapGApps = true;

    desktopItems = [
      (makeDesktopItem {
        name = "haqor";
        desktopName = "Haqor";
        comment = "Study the Bible in its original languages";
        exec = "haqor";
        icon = "haqor";
        categories = ["Education"];
      })
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/libexec/haqor" "$out/bin"
      cp -r haqor lib data "$out/libexec/haqor/"
      install -Dm644 ${../../assets/icon/icon.png} "$out/share/icons/hicolor/1024x1024/apps/haqor.png"
      runHook postInstall
    '';

    preFixup = ''
      addAutoPatchelfSearchPath "$out/libexec/haqor/lib"
      # The release includes Dart's JNI plugin, linked against Java 11.
      addAutoPatchelfSearchPath "${jdk11}/lib/openjdk/lib/server"
      makeWrapper "$out/libexec/haqor/haqor" "$out/bin/haqor" \
        "''${gappsWrapperArgs[@]}" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [libGL]}"
    '';

    passthru.updateScript = ["bash" "tool/update-nix-package.sh"];
    meta = {
      description = "Bible study app with original language tools";
      homepage = "https://github.com/machshev/haqor";
      changelog = "https://github.com/machshev/haqor/releases/tag/v${release.version}";
      license = lib.licenses.agpl3Plus;
      platforms = ["x86_64-linux"];
      mainProgram = "haqor";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
