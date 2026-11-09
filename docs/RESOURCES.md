# Resources

Art and other third-party content in the game, with source, license and what the license asks.

| What | Files | Source | License | Notes |
|---|---|---|---|---|
| Quaternius Universal Animation Library (Standard) | `game/assets/quaternius/ual/UAL1.glb` (Godot file of the pack: mannequin and 45 animations) | [OpenGameArt](https://opengameart.org/content/universal-animation-library) (`universal_animation_librarystandard.zip`), also [quaternius.com](https://quaternius.com/packs/universalanimationlibrary.html) | CC0 1.0 (`LICENSE.txt` beside the files) | Credit is optional; we credit Quaternius. Imported with a humanoid bone map (`ual1_bone_map.tres`). |
| Quaternius Universal Animation Library 2 (Standard) | `game/assets/quaternius/ual/UAL2.glb` (sword combos, block, shield, zombie and more) | [OpenGameArt](https://opengameart.org/content/universal-animation-library-2) (`universal_animation_library_2standard.zip`) | CC0 1.0 | Different rig from UAL1; bone map `ual2_bone_map.tres` makes the clips play on the UAL1 mannequin. |
| Quaternius Sci-Fi Essentials Kit (Standard) | `game/assets/quaternius/robots/` (QuadShell, EyeDrone, Trilobite and their textures), `game/assets/quaternius/guns/` (revolver) | [OpenGameArt](https://opengameart.org/content/sci-fi-essentials-kit) (`sci-fi_essentials_kit_models.zip`, `sci-fi_essentials_kit_textures.zip`) | CC0 1.0 (`LICENSE.txt`) | The robots' glTF files pointed at `T_Enemies_BaseColor_png.png`; changed to the shipped `T_Enemies_BaseColor.png`. Emission maps are applied in code. |
| ambientCG materials | `game/assets/ambientcg/` (DiamondPlate008C, MetalPlates006, MetalPlates013, Rock030, Rock035; 1K JPG: color, normal GL, roughness, metalness and AO where present) | [ambientcg.com](https://ambientcg.com) | CC0 1.0 (`LICENSE.txt`) | Credit optional. |
| Rajdhani (Indian Type Foundry) | `game/assets/fonts/` (Medium, SemiBold) | [google/fonts](https://github.com/google/fonts/tree/main/ofl/rajdhani) at `5bb2873` | SIL OFL 1.1 (`OFL.txt` beside the files) | The OFL allows bundling; the font may not be sold on its own. |
| netfox | `game/addons/netfox*` (downloaded, not committed) | [GitHub](https://github.com/foxssake/netfox) at `cf5189d` | MIT | Installed by `tools/install.py`. |

Until M9 the game used KayKit Adventurers and Skeletons (CC0, Kay Lousberg); they were removed with the switch to the sci-fi look (PLAN §3.2).
