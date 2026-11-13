#!/bin/zsh
# Times the aim hint and the physics step, in an optimized build and in a Debug-style build.
# Run from the project folder:  Tools/Bench/run.sh
set -e
out=$(mktemp -d)
src=("Tiny Pool/Engine/Geometry.swift" "Tiny Pool/Engine/Table.swift" "Tiny Pool/Engine/Simulation.swift" "Tiny Pool/Engine/Rules.swift" "Tiny Pool/Engine/ShotPreview.swift" "Tools/Bench/main.swift")
echo "== optimized (what players get) =="
swiftc -O -wmo -module-name bench -Xfrontend -strict-concurrency=minimal $src -o $out/bench && $out/bench
echo; echo "== unoptimized (an Xcode Debug run) =="
swiftc -Onone -module-name bench -Xfrontend -strict-concurrency=minimal $src -o $out/bench_debug && $out/bench_debug
