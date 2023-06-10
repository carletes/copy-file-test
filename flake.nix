{
  description = "Experiments with https://man7.org/linux/man-pages/man2/copy_file_range.2.html";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            python311

            # Keep this line if you use bash.
            bashInteractive
          ];
        };
      });
}
