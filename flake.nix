{
  description = "Haqor development environment";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          android_sdk.accept_license = true;
          allowUnfree = true;
        };
      };
      buildToolsVersion = "35.0.0";
      androidComposition = pkgs.androidenv.composeAndroidPackages {
        buildToolsVersions = [buildToolsVersion "35.0.0"];
        platformVersions = ["35"];
        abiVersions = ["x86_64" "armeabi-v7a" "arm64-v8a"];
        useGoogleAPIs = false;
        extraLicenses = [
          "android-googletv-license"
          "android-sdk-arm-dbt-license"
          "android-sdk-license"
          "android-sdk-preview-license"
          "google-gdk-license"
          "intel-android-extra-license"
          "intel-android-sysimage-license"
          "mips-android-sysimage-license"
        ];
      };
      androidSdk = androidComposition.androidsdk;

      # Rust via rustup (flutter rinf uses rustup rust-overlay doesn't work)
      # Might be able to modify the plugin to not require rustup?
      overrides = builtins.fromTOML (builtins.readFile (self + "/rust-toolchain.toml"));
    in {
      devShells = {
        default = pkgs.mkShell rec {
          nativeBuildInputs = [pkgs.pkg-config];
          buildInputs = with pkgs; [
            sqlitebrowser

            # Flutter deps
            flutter
            jdk
            gtk3
            androidSdk
            google-chrome

            # rinf
            rustup # required by dart rinf plugin which uses it to interrogate the rust toolchain
            clang
            llvmPackages.bintools

            # Linux target build deps
            libsysprof-capture
            gtk3
            pcre2.dev
            util-linux.dev
            libselinux
            libsepol
            libthai
            libdatrie
            xorg.libXdmcp
            xorg.libXtst
            lerc.dev
            libxkbcommon
            libepoxy

            # If the dependencies need system libs, you usually need pkg-config + the lib
            openssl
            sqlite
          ];

          # Flutter and Android SDK
          ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
          CHROME_EXECUTABLE = "google-chrome-stable";
          DART_ROOT = "${pkgs.flutter}/bin/cache/dart-sdk";
          FLUTTER_ROOT = pkgs.flutter;
          JAVA_HOME = pkgs.jdk.home;

          # Rust config
          RUSTC_VERSION = overrides.toolchain.channel;

          # https://github.com/rust-lang/rust-bindgen#environment-variables
          LIBCLANG_PATH = pkgs.lib.makeLibraryPath [pkgs.llvmPackages_latest.libclang.lib];

          shellHook = ''
            export PATH=$PATH:''${CARGO_HOME:-~/.cargo}/bin
            export PATH=$PATH:''${RUSTUP_HOME:-~/.rustup}/toolchains/$RUSTC_VERSION-x86_64-unknown-linux-gnu/bin/
          '';

          # Add precompiled library to rustc search path
          RUSTFLAGS = builtins.map (a: ''-L ${a}/lib'') [
            # add libraries here (e.g. pkgs.libvmi)
          ];

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs);

          # Add glibc, clang, glib, and other headers to bindgen search path
          BINDGEN_EXTRA_CLANG_ARGS =
            # Includes normal include path
            (builtins.map (a: ''-I"${a}/include"'') [
              # add dev libraries here (e.g. pkgs.libvmi.dev)
              pkgs.glibc.dev
            ])
            # Includes with special directory paths
            ++ [
              ''-I"${pkgs.llvmPackages_latest.libclang.lib}/lib/clang/${pkgs.llvmPackages_latest.libclang.version}/include"''
              ''-I"${pkgs.glib.dev}/include/glib-2.0"''
              ''-I${pkgs.glib.out}/lib/glib-2.0/include/''
            ];
        };
      };
      formatter = nixpkgs.legacyPackages.${system}.alejandra;
    });
}
