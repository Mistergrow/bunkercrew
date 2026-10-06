# Path-neutral native publication builds

This rebuild uses the unchanged C++ files recorded in
`assets/audio/live/native.source.json`, the Godot 4.7.2 API dump and godot-cpp
revision `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`. Tessel keeps its adjacent
Bunkercrew-only license. No audio, ABI or GDScript behavior is changed.

Toolchain used: CMake 3.28.3; Linux GCC 13.3.0 (Ubuntu
13.3.0-6ubuntu2~24.04.1); Windows MinGW GCC 13-posix. Both targets are x86_64.

Copy the explicit native source file allowlist to an empty neutral work tree
with the same layout: `native/`, `build-linux/` and `build-windows/`. Keep source
metadata/licenses. Select the pinned existing godot-cpp checkout and MinGW
root; do not silently download a different dependency version.

```sh
# Set these to the actual neutral work tree and verified dependency locations.
native_work=/tmp/bunkercrew-native-public
bindings=/path/to/pinned-godot-cpp
mingw_root=/path/to/mingw
flags="-g0"
for kind in file debug macro; do
  flags="$flags -f${kind}-prefix-map=${native_work}=."
  flags="$flags -f${kind}-prefix-map=${bindings}=deps/godot-cpp"
  flags="$flags -f${kind}-prefix-map=${mingw_root}=toolchain/mingw"
done
cmake -S "$native_work/native" -B "$native_work/build-linux"   -DCMAKE_BUILD_TYPE=Release -DBUNKERCREW_EXTENSION=ON   -DGODOT_CPP_PATH="$bindings" -DCMAKE_CXX_FLAGS="$flags"
cmake -S "$native_work/native" -B "$native_work/build-windows"   -DCMAKE_BUILD_TYPE=Release -DBUNKERCREW_EXTENSION=ON   -DGODOT_CPP_PATH="$bindings" -DCMAKE_CXX_FLAGS="$flags"   -DCMAKE_TOOLCHAIN_FILE="$native_work/native/mingw-toolchain.cmake"   -DMINGW_ROOT="$mingw_root"   -DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-insert-timestamp   -DCMAKE_EXE_LINKER_FLAGS=-Wl,--no-insert-timestamp
cmake --build "$native_work/build-linux" --parallel 4
cmake --build "$native_work/build-windows" --parallel 4
```

The existing CMake targets retain `-O3 -ffp-contract=off` for DSP code and static
Windows compiler runtimes. Prefix maps apply to project, generated bindings,
upstream binding sources and the cross-toolchain. Release output has no debug
sections requiring retention. Dynamic runtime symbols remain available.

Before installing a library, scan all binary bytes/printable strings for private
paths, inspect ELF/PE architecture and dependencies, compare exported symbols
with the preserved original, and run native C++ and Godot playback tests.
Use a disposable Wine prefix for Windows; this does not establish native Windows
acceptance. Preserve original libraries outside the publication allowlist.

The publication rebuild retained all 4,499 Linux exports and the single Windows
export `bunkercrew_audio_init`. Both platforms rebuilt bit-identically in a
second neutral directory. Current exact binary sizes and SHA-256 values are in
`assets/audio/live/native.source.json`. Prior hashes remain in its history.
