{
  description = "Open RTL synthesis framework and tools";
  nixConfig.bash-prompt = "[nix(openXC7)] ";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils, ... }:
    let

      # to work with older version of flakes
      lastModifiedDate =
        self.lastModifiedDate or self.lastModified or "19700101";

      # Generate a user-friendly version number.
      version = builtins.substring 0 8 lastModifiedDate;

      # System types to support.
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in {
      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          inherit (pkgs) lib callPackage stdenv fetchgit fetchFromGitHub;
        in rec {
          nextpnr-xilinx = callPackage ./nix/nextpnr-xilinx.nix { };

          prjxray = callPackage ./nix/prjxray.nix { };

          mkChipdb = { backend, chipdbFootprints ? null }:
            callPackage ./nix/nextpnr-xilinx-chipdb.nix {
              backend = backend;
              nixpkgs = pkgs;
              inherit nextpnr-xilinx;
              inherit prjxray;
              inherit chipdbFootprints;
            };

          fasm = with pkgs;
            with python3Packages;
            callPackage ./nix/fasm {
              # NOTE(jleightcap): calling this package here is clucky.
              # contorted structure here to make the `nix/fasm` directory be
              # drop-in to upstream python-modules in nixpkgs.
              inherit buildPythonPackage pythonOlder textx cython fetchpatch;
            };

          nextpnr-xilinx-chipdb = {
            artix7 = mkChipdb { backend = "artix7"; };
            kintex7 = mkChipdb { backend = "kintex7"; };
            spartan7 = mkChipdb { backend = "spartan7"; };
            zynq7 = mkChipdb { backend = "zynq7"; };
            fromFootprints = { chipdbFootprints, backend ? null }:
              mkChipdb { inherit backend chipdbFootprints; };
            single = {
              "xc7k480tffg1156" = mkChipdb {
                backend = "kintex7";
                chipdbFootprints = [ "xc7k480tffg1156" ];
              };
            };
          };

          fpga-assembler = (builtins.getFlake "github:lromor/fpga-assembler/6ff89a2d53edc9d74a402c28096450473b67de13").packages.${system}.default;

          # disable yosys-synlig for now: synlig is not very good and it does not compile with recent yosys
          # yosys-synlig = callPackage ./nix/yosys-synlig.nix { };
        });

      apps = forAllSystems (system: {
        build-chipdb = {
          type = "app";
          program =
            let
              pkgs = nixpkgsFor.${system};
              script = pkgs.writeShellScriptBin "build-chipdb" ''
                set -euo pipefail

                if [ "$#" -eq 0 ]; then
                  echo "usage: build-chipdb <footprint> [footprint...]" >&2
                  exit 1
                fi

                if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
                  echo "usage: build-chipdb <footprint> [footprint...]"
                  echo
                  echo "Build chipdb images for one or more Xilinx 7-Series footprints."
                  echo "Examples:"
                  echo "  build-chipdb xc7a100tcsg324"
                  echo "  build-chipdb xc7a100tcsg324 xc7k480tffg1156"
                  exit 0
                fi

                footprints=""
                for fp in "$@"; do
                  footprints="$footprints \"$fp\""
                done

                expr_file="$(mktemp)"
                trap 'rm -f "$expr_file"' EXIT

                cat > "$expr_file" <<EOF
let
  flake = builtins.getFlake "${builtins.toString self}";
  system = "${system}";
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
in
  (flake.packages.${system}.nextpnr-xilinx-chipdb.fromFootprints {
    chipdbFootprints = [ $footprints ];
  })
EOF

                ${pkgs.nix}/bin/nix build -L -f "$expr_file"
              '';
            in "${script}/bin/build-chipdb";
        };
      });

      # contains a mutually consistent set of packages for a full toolchain using nextpnr-xilinx.
      devShell = forAllSystems (system:
        nixpkgsFor.${system}.mkShell {
          buildInputs = (with self.packages.${system}; [
            fasm
            fpga-assembler
            prjxray
            nextpnr-xilinx
            # disabled, see above
            # yosys-synlig
          ]) ++ (with nixpkgsFor.${system}; [
            yosys
            ghdl
            yosys-ghdl
            openfpgaloader
            pypy310
            python312Packages.pyyaml
            python312Packages.textx
            python312Packages.simplejson
            python312Packages.intervaltree
          ]);

          shellHook =
            let mypkgs  = self.packages.${system};
                nixpkgs = nixpkgsFor.${system};
                pyPkgPath = "/lib/python3.12/site-packages/:";
            in nixpkgs.lib.concatStrings [
              "export NEXTPNR_XILINX_DIR=" mypkgs.nextpnr-xilinx.outPath "\n"
              "export NEXTPNR_XILINX_PYTHON_DIR=" mypkgs.nextpnr-xilinx.outPath "/share/nextpnr/python/\n"
              "export PRJXRAY_DB_DIR=" mypkgs.nextpnr-xilinx.outPath "/share/nextpnr/external/prjxray-db\n"
              "export PRJXRAY_PYTHON_DIR=" mypkgs.prjxray.outPath "/usr/share/python3/\n"
              ''export PYTHONPATH=''$PYTHONPATH:''$PRJXRAY_PYTHON_DIR:'' 
                mypkgs.fasm.outPath pyPkgPath
                nixpkgs.python312Packages.textx.outPath pyPkgPath
                nixpkgs.python312Packages.arpeggio.outPath pyPkgPath
                nixpkgs.python312Packages.pyyaml.outPath pyPkgPath
                nixpkgs.python312Packages.simplejson.outPath pyPkgPath
                nixpkgs.python312Packages.intervaltree.outPath pyPkgPath
                nixpkgs.python312Packages.sortedcontainers.outPath pyPkgPath
                "\n"
              "export PYPY3=" nixpkgs.pypy310.outPath "/bin/pypy3.10"
            ];
        }
      );

      dockerImage = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          mypkgs = self.packages.${system};
          chipdb = mypkgs.nextpnr-xilinx-chipdb;
          pyPkgPath = "/lib/python3.10/site-packages/:";
        in
        pkgs.dockerTools.buildImage {
          name = "openxc7-docker";
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = self.devShell.${system}.buildInputs ++ (with pkgs; [
              bashInteractive
              findutils
              gnused
              gnugrep
              coreutils
              gnumake
              python312
            ]) ++ (with chipdb; [
              spartan7
              artix7
              kintex7
              zynq7
            ]);
            pathsToLink = [ "/bin" ] ++ (with pkgs.dockerTools; [
              usrBinEnv
              binSh
            ]);
          };

          runAsRoot = pkgs.lib.concatStrings [ ''
            #!${pkgs.runtimeShell}
            mkdir -p /work
            cat > /bin/devshell <<EOF
            #!${pkgs.runtimeShell}
            '' self.devShell.${system}.shellHook "\n"
            "export NEXTPNR_XILINX_PYTHON_DIR=" mypkgs.nextpnr-xilinx.outPath "/share/nextpnr/python/\n"
            "export PRJXRAY_DB_DIR=" mypkgs.nextpnr-xilinx.outPath "/share/nextpnr/external/prjxray-db\n"
            "export PRJXRAY_PYTHON_DIR=" mypkgs.prjxray.outPath "/usr/share/python3/\n"
            ''export PYTHONPATH=\''$PYTHONPATH:\''$PRJXRAY_PYTHON_DIR:''
              pkgs.python312Packages.textx.outPath pyPkgPath
              pkgs.python312Packages.pyyaml.outPath pyPkgPath
              pkgs.python312Packages.simplejson.outPath pyPkgPath
              pkgs.python312Packages.intervaltree.outPath pyPkgPath
              pkgs.python312Packages.arpeggio.outPath pyPkgPath
              pkgs.python312Packages.setuptools.outPath pyPkgPath
              pkgs.python312Packages.future.outPath pyPkgPath
              pkgs.python312Packages.sortedcontainers.outPath pyPkgPath
              mypkgs.fasm.outPath "/lib/python3.12/site-packages/"
              "\n"
            "export NEXTPNR_XILINX_DIR=" mypkgs.nextpnr-xilinx.outPath "\n"
            "export SPARTAN7_CHIPDB="    chipdb.spartan7.outPath "\n"
            "export ARTIX7_CHIPDB="      chipdb.artix7.outPath "\n"
            "export KINTEX7_CHIPDB="     chipdb.kintex7.outPath "\n"
            "export ZYNQ7_CHIPDB="       chipdb.zynq7.outPath "\n"
            "\nexec ${pkgs.bashInteractive}/bin/bash\n"
            ''EOF
            chmod 755 /bin/devshell
          ''];

          config = {
            Cmd = [ "/bin/devshell" ];
            WorkingDir = "/work";
            Volumes = { "/work" = { }; };
          };
        }
      );
    };
}
