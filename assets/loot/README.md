# Enemy salvage

`salvage_atlas.png` contains three scrap piles and three recovered technology
modules. The built-in Imagegen tool generated these sprites using the existing
industrial crate and machinery art as style references. The full prompts and
source rectangles are recorded in [source.json](source.json).

The atlas is 1536×1024. `scripts/pickup_art.gd` draws tight regions at 28–32 world
pixels wide with nearest filtering. Source images retain faint low-alpha pixels;
`shaders/pickup_cutout.gdshader` discards those in the world and preserves the
separately drawn contact shadows. Keep this material on world loot nodes.

Technology modules have small amber status indicators. Campaign route data uses
a cylindrical field recorder with a worn identification band. Scrap and module
icons in the HUD and research screen use the same atlas.

Only presentation changes: the internal `scrap` and `core` identifiers, values,
automatic technology collection and network state remain compatible. Common
loose resources reuse the existing carried-material sprites.

Native captures and a before/after comparison: [pickup gallery](../../artifacts/pickup-style/index.html).
