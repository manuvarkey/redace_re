# Red Ace decompilation reference

Research reference for "Master of the Skies - The Red Ace" (Small Rockets, 2001).
The game is still under copyright. Do not redistribute the game data or the decompiled output.

The decompiler output, saved Ghidra analysis and source-path index are kept in this Git
repository for future reference. Paths and shell commands below are relative to the
repository root. The CD image and extracted game remain local inputs in its parent directory;
they are not included in Git. See the [remake README](../README.md) for the playable project.

## Layout

| Path | Contents |
| --- | --- |
| `../REDACE.BIN`, `../REDACE.CUE` | Local original CD image (track 1 data, tracks 2-5 Redbook audio music) |
| `../extract/redace_track1.iso` | Local track 1 converted to a plain ISO 9660 image |
| `../extract/cd/` | Local files from the CD (autorun front end, DirectX 6 redist, InstallShield setup) |
| `../extract/game/` | Local installed game tree, extracted from `../extract/cd/apps/data*.cab` |
| `tools/isextract.py` | Pure-Python InstallShield 5/6 cabinet extractor |
| `tools/ghidra_scripts/ExportAll.java` | Ghidra headless script: full C export + function index |
| `ghidra_proj/` | Ghidra project with the analysed `RedAce.exe` (open it in Ghidra or REA) |
| `decomp/` | Decompiler output: `RedAce.c`, `RedAce.h`, `functions.tsv`, `dive5_guids.tsv`, `headless.log` |
| `tools/ghidra_scripts/ImproveAnalysis.java` | Pass 2: functions from vtable/callback pointers and code gaps |
| `tools/ghidra_scripts/ApplyGuids.java` | Pass 3: names every copy of the 299 Dive5 IID/CLSID/CATID GUIDs |
| `tools/rw2gltf.py` | RenderWare 3.1 `.dff`/`.bsp` to glTF 2.0 converter |
| `tools/build_assets.py` | Builds `redace/game_data` from the extracted game |
| `redace/` | Godot 4 remake project (see `README.md`) |
| `decomp_source_paths.txt` | Original engine header paths leaked by assert strings |

## Toolchain

- JDK 21: `~/tools/jdk-21.0.13+9`
- Ghidra 12.1.4: `~/tools/ghidra_12.1.4_PUBLIC`
- REA MCP server env (`~/.claude.json`): `GHIDRA_INSTALL_DIR` and `JAVA_HOME` point at the paths above.
  Backup of the previous config: `~/.claude.json.bak-rea`.

## Reproduce

```sh
python3 tools/isextract.py ../extract/cd/apps ../extract/game

export JAVA_HOME=~/tools/jdk-21.0.13+9 PATH=~/tools/jdk-21.0.13+9/bin:$PATH
~/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless ghidra_proj RedAce \
  -import ../extract/game/RedAce.exe -overwrite \
  -scriptPath tools/ghidra_scripts -postScript ImproveAnalysis.java \
  -postScript ApplyGuids.java decomp/dive5_guids.tsv -postScript ExportAll.java decomp
```

To inspect the saved analysis, open `ghidra_proj/RedAce.gpr` in Ghidra; the analysed
program is `RedAce.exe`. Keep the `.gpr` file and the entire `RedAce.rep/` directory
together. Close Ghidra before committing database changes. Temporary project locks
are ignored by Git.

`decomp/headless.log` is the original analysis log, preserved unchanged; its absolute
paths describe the workspace before these files were moved into the repository.

`decomp/dive5_guids.tsv` comes from the interface table in `.data`
(entries of `{0, char *name, char *header_path, GUID}`, 28 bytes each, from 0x52922c).

## Results

- 4399 functions covering 96% of `.text`; 3 functions fail to decompile ("Overlapping input varnodes").
- `RedAce.c` is about 249k lines of Ghidra pseudocode. It is not compilable source.
- Most names are still `FUN_xxxxxxxx`. Library/CRT functions and GUID constants are named.
- `FUN_004b44c0(clsid, outer, ctx, iid, &out)` is the Dive5 equivalent of `CoCreateInstance`.
  Interface calls look like `(**(code **)(*obj + 0xc))(obj, ...)`: slot 0 QueryInterface, 1 AddRef, 2 Release.

## What the binary is

- 32-bit x86 PE, MSVC, built 2000-12-04, no RTTI, no PDB.
- In-house "Dive5" engine (COM-style interfaces, `dip*` = interface, `dcp*` = portable class,
  `dcw*` = Win32 class) plus statically linked RenderWare 3 (`_rwcseg`/`_rwdseg` sections).
- Platform layer to replace for a Linux port (all in `dcw*` classes):
  DirectDraw/Direct3D renderer (`dcw5ren`, `dcw5dis`), DirectInput (`dcwdirectxkeyboard`, `dcwdirectxmouse`),
  DirectSound / DirectMusic (`dcwdxsnd`, `dcwdx7dmusic`), Redbook CD audio via MCI (`dcwcdar`),
  registry and licence (`dcpencryptregistry`, `dcpeclicense`), Win32 window/message loop (`dcwwin32`, `dcwwindo`).
- Assets are portable as is: JPG/PNG/BMP textures, WAV and `.l3` sounds, INI configuration, HTML menus.
