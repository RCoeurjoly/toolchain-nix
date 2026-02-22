# openXC7 toolchain

The openXC7 FPGA toolchain's integration with the Nix package manager offers precise control over software builds and dependencies, emphasizing reproducibility and configuration transparency. Conversely, the adaptation to a containerized environment using [Podman](https://podman.io/) or [Docker](https://www.docker.com/products/docker-desktop/) facilitates cross-platform operation, notably on Windows WSL and MacOS x86, and encapsulates the toolchain for consistent execution across varied systems. While Nix provides a robust, integrated environment, the container approach introduces portability and simplifies the toolchain's utilization for users less versed in Nix's specifics.

## How to use with Nix package manager

1. [Install the Nix package manager](https://nixos.org/download#download-nix) on your Linux distribution of choice
   (or [use NixOS](https://nixos.org/download.html)):
```
$ sh <(curl -L https://nixos.org/nix/install) --daemon
```

2. Enable flakes:
Add the following to `~/.config/nix/nix.conf`  or `/etc/nix/nix.conf`:
```
experimental-features = nix-command flakes
```

3. Then you will get a development shell with the complete toolchain with:
```
$ nix develop github:openxc7/toolchain-nix
```

4. Compile and load a demo project onto an FPGA:
```
$ git clone https://github.com/openXC7/demo-projects
$ cd demo-projects/blinky-qmtech
$ make
$ make program
```

Build chipdb for one device, many devices, or mixed families:
```
$ nix run .#build-chipdb -- xc7a100tcsg324
```
Examples:
```
$ nix run .#build-chipdb -- xc7a100tcsg324
$ nix run .#build-chipdb -- xc7a100tcsg324 xc7k480tffg1156 xc7s50csga324
```
When only one footprint is requested, backend is inferred from the device prefix.

For ad-hoc experiments, you can still use:
```
$ nix build -L --expr 'let flake = builtins.getFlake "<path-to-this-flake>"; system = "<system>"; pkgs = flake.inputs.nixpkgs.legacyPackages.${system}; in pkgs.callPackage <path-to-this-flake>/nix/nextpnr-xilinx-chipdb.nix { nixpkgs = pkgs; inherit (flake.packages.${system}) nextpnr-xilinx prjxray; chipdbFootprints = [ "xc7a100tcsg324" ]; }'
```

If this flake is consumed from another repo (for example `LLM2FPGA`), use:
```
openXC7Chipdb = openXC7Packages.nextpnr-xilinx-chipdb.fromFootprints {
  chipdbFootprints = [ "xc7k480tffg1156" ];
};
```
That keeps one-family, one-device, and multi-device usage on the same API path.

## How to use as a container
### `docker`
To build a docker container for `x86_64-linux`, use:
```
$ nix build -L ".#dockerImage.x86_64-linux"
```
The resulting container is then the file `./result`, which you can install
with:
```
$ docker image load --input result
a7cd1bb3e14c: Loading layer [==================================================>]   2.34GB/2.34GB
Loaded image: openxc7-docker:ifnarr8fs6vln2sbxwswrxlmwvxjmri0
```
You can then run this image with:
```
docker run -v ./demo-projects/:/work -it openxc7-docker:ifnarr8fs6vln2sbxwswrxlmwvxjmri0
```

### `podman`
To utilize the openXC7 FPGA toolchain in a Podman container, users must first ensure Podman is installed on their system. The process involves building the container image with the toolchain using a specific build command. Once the image is built, the toolchain is executed within the container through a run command. This containerized approach ensures a consistent development environment across various operating systems like Windows, MacOS (x86 only), and Linux, streamlining the deployment and usage of the toolchain.

For installation and contaienr usage, please refer to the [detailed instructions](container).
