{
  description = "Baker - Bakery shop operations tracker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;
      in
      {
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
      });
}
