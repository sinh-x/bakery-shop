{
  description = "Baker - Bakery shop operations tracker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
        python = pkgs.python312;

        flutterRev = "3.44.0";

        flutterPinned = pkgs.fetchgit {
          url = "https://github.com/flutter/flutter.git";
          rev = flutterRev;
          hash = "sha256-YwQpuQIgulR4dzV9KyEhBF6+GdZvGSKZyweNfUv3wA4=";
          deepClone = true;
          fetchTags = true;
          leaveDotGit = true;
        };

        # Baker Python package (CLI + web server)
        baker = python.pkgs.buildPythonApplication {
          pname = "baker";
          version = "0.1.0";
          src = self;
          pyproject = true;

          build-system = with python.pkgs; [ setuptools ];

          propagatedBuildInputs = with python.pkgs; [
            click
            rich
            pyyaml
            fastapi
            uvicorn
            python-multipart
            pillow
          ];
        };

        # Android SDK configuration (for Flutter app)
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "11.0";
          platformToolsVersion = "35.0.2";
          buildToolsVersions = [ "35.0.0" ];
          platformVersions = [ "36" "35" "34" ];
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
          cmakeVersions = [ "3.22.1" ];
          includeEmulator = false;
          includeSources = false;
          includeSystemImages = false;
        };
        androidSdk = androidComposition.androidsdk;

        # Linux desktop dependencies (for Flutter)
        linuxDeps = with pkgs; [
          gtk3
          glib
          pcre2
          libepoxy
          cairo
          pango
          gdk-pixbuf
          atk
          harfbuzz
          libx11
          libxcursor
          libxinerama
          libxrandr
          libGL
          libxkbcommon
        ];

        # Convenience scripts for Flutter app
        bakery-run = pkgs.writeShellScriptBin "bakery-run" "cd app && flutter run -d linux";
        bakery-run-android = pkgs.writeShellScriptBin "bakery-run-android" "cd app && flutter run -d android";
        bakery-build = pkgs.writeShellScriptBin "bakery-build" "cd app && flutter build linux --release";
        bakery-build-apk = pkgs.writeShellScriptBin "bakery-build-apk" "cd app && flutter build apk --release";
        bakery-test = pkgs.writeShellScriptBin "bakery-test" "cd app && flutter test";
        bakery-analyze = pkgs.writeShellScriptBin "bakery-analyze" "cd app && flutter analyze";
        bakery-clean = pkgs.writeShellScriptBin "bakery-clean" "cd app && flutter clean && flutter pub get";
      in
      {
        packages.baker = baker;
        packages.default = baker;

        # Python CLI devShell (default)
        devShells.default = pkgs.mkShell {
          packages = [
            python
            pkgs.uv
          ];

          shellHook = ''
            if [ ! -d .venv ]; then
              uv venv .venv
            fi
            source .venv/bin/activate
            uv pip install -e ".[dev]" --quiet 2>/dev/null
            echo "Baker dev shell ready"
          '';
        };

        # Flutter app devShell
        devShells.flutter = pkgs.mkShell {
          packages = [
            flutterPinned
            androidSdk
            pkgs.jdk17
            pkgs.git
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.clang
            # Dev commands
            bakery-run
            bakery-run-android
            bakery-build
            bakery-build-apk
            bakery-test
            bakery-analyze
            bakery-clean
          ] ++ linuxDeps;

          env = {
            ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
            JAVA_HOME = "${pkgs.jdk17}";
            CHROME_EXECUTABLE = "${pkgs.chromium}/bin/chromium";
            COLORFGBG = "15;0";
          };

          shellHook = ''
            FLUTTER_SDK_DIR="$PWD/.nix-flutter-sdk"
            FLUTTER_REV="${flutterRev}"

            if [ ! -f "$FLUTTER_SDK_DIR/.pinned-rev" ] || [ "$(cat "$FLUTTER_SDK_DIR/.pinned-rev" 2>/dev/null)" != "$FLUTTER_REV" ]; then
              mkdir -p "$FLUTTER_SDK_DIR"
              cp -aT "${flutterPinned}" "$FLUTTER_SDK_DIR"
              chmod -R u+w "$FLUTTER_SDK_DIR"
              printf "%s" "$FLUTTER_REV" > "$FLUTTER_SDK_DIR/.pinned-rev"
            fi

            if ! git -C "$FLUTTER_SDK_DIR" rev-parse "$FLUTTER_REV" >/dev/null 2>&1; then
              git -C "$FLUTTER_SDK_DIR" tag "$FLUTTER_REV" HEAD >/dev/null 2>&1 || true
            fi

            export FLUTTER_ROOT="$FLUTTER_SDK_DIR"
            export PATH="$FLUTTER_SDK_DIR/bin:$FLUTTER_SDK_DIR/bin/cache/dart-sdk/bin:$PATH"
            echo "Bakery App Development Environment"
            echo ""
            echo "Flutter: $(TERM=dumb flutter --version --machine </dev/null 2>/dev/null | ${pkgs.jq}/bin/jq -r '.frameworkVersion // "unknown"')"
            echo "Dart:    $(TERM=dumb dart --version </dev/null 2>&1 | head -1)"
            echo ""
            echo "Commands:"
            echo "  bakery-run           - Run on Linux desktop"
            echo "  bakery-run-android   - Run on Android device"
            echo "  bakery-build         - Build Linux release"
            echo "  bakery-build-apk     - Build Android APK"
            echo "  bakery-test          - Run tests"
            echo "  bakery-analyze       - Run analyzer"
            echo "  bakery-clean         - Clean and get deps"
            echo ""

            stty sane 2>/dev/null
          '';

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath linuxDeps;
        };
      }) // {
        # NixOS module (system-independent — exported outside eachDefaultSystem)
        nixosModules.default = import ./nix/module.nix { inherit self; };
      };
}
