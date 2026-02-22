{ stdenv, nixpkgs, backend ? null, nextpnr-xilinx, prjxray, pypy310, coreutils
, findutils, gnused, gnugrep, lib, chipdbFootprints ? null, ... }:

stdenv.mkDerivation rec {
  pname = "nextpnr-xilinx-chipdb";
  version = nextpnr-xilinx.version;
  inherit backend;

  src = "${nextpnr-xilinx.outPath}/share/nextpnr/external/prjxray-db";
  # Don't try to unpack src, it already exists
  dontUnpack = true;
  chipdbFootprintsText = if chipdbFootprints == null then "" else lib.concatStringsSep "\n" chipdbFootprints;
  inferredBackend =
    if chipdbFootprints == null || (builtins.length chipdbFootprints) != 1 then null
    else
      let footprint = builtins.head chipdbFootprints; in
      if lib.hasPrefix "xc7a" footprint then "artix7"
      else if lib.hasPrefix "xc7k" footprint then "kintex7"
      else if lib.hasPrefix "xc7s" footprint then "spartan7"
      else if lib.hasPrefix "xc7z" footprint then "zynq7"
      else null;
  effectiveBackend = if backend != null then backend else inferredBackend;
  shellBackend = if effectiveBackend == null then "" else effectiveBackend;
  scriptBackend = if backend == null then "custom" else backend;
  displayBackend = if shellBackend == "" then "inferred" else shellBackend;

  buildInputs =
    [ prjxray nextpnr-xilinx pypy310 coreutils findutils gnused gnugrep ];
  buildPhase = ''
    mkdir -p $out
    if [ -n "${chipdbFootprintsText}" ]; then
      cat <<'EOF' > $out/footprints.txt
${chipdbFootprintsText}
EOF
    else
      find ${src}/ -type d -name "*-*" -mindepth 1 -maxdepth 2 |\
        sed -e 's,.*/\(.*\)-.*$,\1,g' -e 's,\./,,g' |\
        sort |\
        uniq >\
      $out/footprints.txt
    fi
    
    touch $out/built-footprints.txt

    cat "$out/footprints.txt"
    for i in `cat $out/footprints.txt`
    do
        if   [[ $i = xc7a* ]]; then ARCH=artix7 
        elif [[ $i = xc7k* ]]; then ARCH=kintex7
        elif [[ $i = xc7s* ]]; then ARCH=spartan7
        elif [[ $i = xc7z* ]]; then ARCH=zynq7
        else 
          echo "unsupported architecture for footprint $i"
          exit 1
        fi

        if [[ -n "${shellBackend}" ]] && [[ $ARCH != "${shellBackend}" ]]; then
          continue
        fi

        FIRST_SPEEDGRADE_DIR=`find ${src}/$ARCH -mindepth 1 -maxdepth 1 -type d \( -name "$i-*" -o -name "$i" \) | sort -V | head -1`
        if [ -z "$FIRST_SPEEDGRADE_DIR" ]; then
          echo "unsupported device/footprint for backend=${displayBackend}: $i"
          exit 1
        fi
        FIRST_SPEEDGRADE=`basename $FIRST_SPEEDGRADE_DIR`
        echo "Using footprint $i -> $FIRST_SPEEDGRADE"
        pypy3.10 ${nextpnr-xilinx}/share/nextpnr/python/bbaexport.py --device $FIRST_SPEEDGRADE --bba $i.bba 2>&1
        bbasm -l $i.bba $out/$i.bin
        echo $i >> $out/built-footprints.txt
    done

    mv -f $out/built-footprints.txt $out/footprints.txt

    # make the chipdb directory available
    mkdir -p $out/bin
    cat > $out/bin/get_chipdb_${scriptBackend}.sh <<EOF
    #!${nixpkgs.runtimeShell}
    echo -n $out
    EOF
    chmod 755 $out/bin/get_chipdb_${scriptBackend}.sh
  '';
 
  # TODO(jleightcap): the above buildPhase is adapated from a `builder`; which combines the process of
  # compiling assets along with installing those assets to `$out`.
  # These steps should be untangled, ideally - for now just use the buildPhase and disable the (empty)
  # installPhase.
  dontInstall = true;
}
