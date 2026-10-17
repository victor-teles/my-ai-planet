# Art Bible

The rules every asset is checked against. The look: a hand-painted miniature world floating in the sky, toon-shaded with ink outlines and soft, colored shadows.

![The island](screenshots/m1-island.png)

## Shading

| Rule | Value | Where |
|---|---|---|
| Light bands | 3 steps (half-Lambert, floored) | `art/shaders/toon.gdshader` |
| Shadows | Never grey or black: the environment's ambient color (violet) fills them | `Diorama._build_environment` |
| Rim light | Thin warm rim on the lit side | toon shader `rim_*` |
| Outlines | Ink `#291a33`, inverted hull. Island 0.06, props 0.025–0.03, people a hair-thin line | `art/shaders/outline.gdshader` |
| Brush strokes | A painted stroke texture, projected from three sides, varies value ±22% and warmth ±12% on every toon surface | `art/textures/brush_strokes.png`, toon shader `stroke_*` |
| Clouds | Unlit painted gradient, bright tops to lavender bottoms, 4 steps | `art/shaders/cloud.gdshader` |
| Water | Flat color, two tones, a foam line where it meets the shore | `art/shaders/water.gdshader` |
| Camera | 32° field of view, near and far blur (tilt-shift miniature) | `game/diorama/camera_rig.gd` |

New models must have **smooth normals** (or the outline cracks) and use the shared materials from `ToonMaterials`. Don't create one-off materials.

## Era palettes

Each era has a sky, ambient (shadow) color, sun color and fog color. Only Era 3 exists so far.

| Era | Sky top / horizon / bottom | Ambient (shadows) | Sun | Fog | Mood |
|---|---|---|---|---|---|
| 3 First Fires | `#291a57` / `#fa9485` / `#7a427a` | `#805cb3` | `#ffcc9e` | `#db8f9e` | Warm dusk, campfire glow |
| 1 Primordial Soup | deep teal / cyan | teal | pale green | sea green | Bioluminescent |
| 4 Kingdoms | parchment gold / cream | warm brown | gold | sand | Old map |
| 6 Cloud Age | violet / magenta | indigo | neon pink | magenta | Neon night (the Cloud City reference) |

## Materials (Era 3)

| Thing | Color |
|---|---|
| Grass | `#57b35c` → `#8fd166` (noise blend) |
| Cliff | grass overhang → `#b88057` → `#85523d` → rock |
| Rock underside | `#855c75` → `#5c3352` |
| Pines / leafy trees | `#337a70` / `#80b857` |
| Thatch roofs | `#db9e5c`, tinted 25% toward the tribe's hue |
| People | tunic in the tribe's hue, five skin tones from `#f5c7a3` to `#6b4a38`, five hair colors from black to sand |
| Chief's headdress | band `#8c3830`, feathers `#e6543d` and `#f2bf40` |

**Drought:** green tones shift toward straw `#cca866` (the toon shader's `dryness`) and back when the rain returns. The world's state should always be readable from the colors.

## Motion

- Things appear by popping in (scale with an overshoot, 0.45 s) and leave by shrinking (0.6 s).
- People stroll to a spot, stand a while, then walk on, easing between standing and walking.
- Fires flicker in both flame height and light.
- The camera drifts slowly when nobody touches it.

## People

People are low-poly 3D figures, toon-shaded and ink-outlined like everything else, with adult proportions (about five heads tall). The base is Kenney's *Animated Characters* model and its idle and run clips (CC0, `art/characters/kenney/`). The head bone is scaled to 70% so they read as adults, not cartoon kids. Walking blends idle with a slowed run.

| Part | Where |
|---|---|
| Model and clips | `art/characters/kenney/characterMedium.fbx`, `idle.fbx`, `run.fbx` |
| Skins | `art/characters/villager_{male,female}_skin.png`, painted by `tools/paint_villager_skins.gd` |
| Masks | `art/characters/villager_{male,female}_mask.png`: red = tunic, green = hair, blue = skin |
| Shader | `art/shaders/villager.gdshader` (the toon light, plus per-figure colors) |
| Chief | A leather band with three feathers on the head bone (`VillagerArt._add_headdress`) |

**Outfit (Era 3):** a knee-length tunic in the tribe's color with a collar and leather belt `#6b4530`, bare forearms, linen leggings `#ccb894` with leather wraps, leather shoes. Each citizen keeps one of five hair colors and five skin tones for life. Don't add modern clothing details; new eras get new skins painted the same way.

## Painted textures

`tools/paint_textures.gd` paints `brush_strokes.png` from a fixed seed: red is light and dark strokes, green is warm and cool strokes. A hand-painted texture can replace it, as long as it tiles and stays centered on mid-grey (0.5 means no change).

## Placeholders left

Trees, huts, rocks and the campfire are still primitive shapes with the final shading and brush strokes. Painted assets replace them one at a time, and each replacement must keep the silhouette size and the color in the tables above.
