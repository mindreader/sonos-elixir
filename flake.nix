{
  description = "Twilight Struggle Counter";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:

  let

    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    start = {
      type = "app";
      program = (pkgs.writeShellScript "sonos-start" ''
        ${pkgs.elixir}/bin/iex -S mix phx.server
      '').outPath;
    };
  in with pkgs; {

    # nix run .#start
    apps.x86_64-linux.default = start;
    apps.x86_64-linux.start = start;

    # nix develop
    devShells.x86_64-linux.default = pkgs.mkShell {

      name = "ts-shell";
      packages = with pkgs; [ elixir elixir-ls inotify-tools ];
    };
  };
}
