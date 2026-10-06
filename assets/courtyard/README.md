# Bunkercrew courtyard modules

`modules_v1.png` is an original generated transparent sprite atlas. It supplies
matching intact and torn rear mesh, a service paving/drain strip, mesh rubble,
a shielded work lamp and utility bollards. The existing mechanical gate atlas
is the palette/material reference; existing gameplay gate silhouettes stay
attached to their actual collision shapes.

The saved PNG is unchanged from the built-in image generator. The adjacent
source JSON records the full prompt, original saved path, measured crop bounds,
SHA-256 and intended use. Its transparent holes remain alpha; nothing is baked
over a dark background. The runtime uses nearest filtering and one shared
coverage material. Only the small lamp glass varies slowly in a shared GPU
shader; the court itself has no process callback, collisions or network state.

At runtime the intact field and shared posts form a continuous 62px rear
fence, connected directly to the bunker and the outer gate heel. Only the last
field is cropped to the measured court width; pixels retain their pitch. The
standard rear boundary uses intact mesh. Existing compact service-case art and
the new cable bollards sit near the shielded work light. The actual front gate
retains its existing collision-aligned moving leaf and firing slit.

These assets may be distributed only together with Bunkercrew. Preserve this
notice and the adjacent provenance when distributing sources. This notice does
not replace any license or author notice elsewhere in the project.
