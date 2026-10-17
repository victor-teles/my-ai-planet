# Art Bible

The rules every asset is checked against. The look: a hand-painted miniature world floating in the sky, toon-shaded with ink outlines and soft, colored shadows.

![The island](screenshots/m1-island.png)

## Shading

| Rule | Value | Where |
|---|---|---|
| Light bands | 3 steps (half-Lambert, floored) | `art/shaders/toon.gdshader` |
| Shadows | Never grey or black: the environment's ambient color (violet) fills them | `Diorama._build_environment` |
| Rim light | Thin warm rim on the lit side | toon shader `rim_*` |
| Outlines | Ink `#291a33`, inverted hull. Island 0.06, props 0.025–0.03, people 0.015 | `art/shaders/outline.gdshader` |
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
| People | tunic in the tribe's hue, skin `#f5c79e` |

**Drought:** green tones shift toward straw `#cca866` (the toon shader's `dryness`) and back when the rain returns. The world's state should always be readable from the colors.

## Motion

- Things appear by popping in (scale with an overshoot, 0.45 s) and leave by shrinking (0.6 s).
- People hop as they walk, squashing on landing.
- Fires flicker in both flame height and light.
- The camera drifts slowly when nobody touches it.

## Placeholders

Everything is built from primitive shapes with the final shading, so the look can be judged now. Painted assets replace them one at a time, and each replacement must keep the silhouette size and the color in this table.
