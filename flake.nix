{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.zig-overlay.url = "github:mitchellh/zig-overlay";
  inputs.zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, zig-overlay, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ zig-overlay.packages.${system}."0.17.1" ] ++ (with pkgs; [ pkg-config gdb lldb ]);
      };
    };
}
