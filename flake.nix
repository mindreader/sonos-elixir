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
      program =
        let script = pkgs.writeShellApplication {
          name = "sonos-start";
          # needed for file watching.
          runtimeInputs = [ pkgs.inotify-tools ];
          text = ''
            ${pkgs.elixir}/bin/mix deps.get
            ${pkgs.elixir}/bin/iex -S ${pkgs.elixir}/bin/mix phx.server
          '';
        };

        in "${script}/bin/sonos-start";
      };
  in with pkgs; {

    # nix run .#start (or just nix run)
    apps.x86_64-linux.default = start;
    apps.x86_64-linux.start = start;

    # nix develop
    devShells.x86_64-linux.default = pkgs.mkShell {
      name = "ts-shell";
      packages = with pkgs; [ elixir elixir-ls inotify-tools ];
    };
  };
}
