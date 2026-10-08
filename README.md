# SUPER CIWS

Retro arcade roguelike. You are a stationary CIWS battery in the desert. The gun never
stops firing; you aim with the stick, intercept drones and missiles, level up Vampire
Survivors style, and loot kills of advanced units through a slot machine.

Built with **Godot 4.5** (GL Compatibility renderer). Renders 3D at 512x384 (4:3) with a chunky 256x192 HUD, then a post shader quantises
everything to a 128-colour SNES-style palette with palette-aware 4x4 Bayer dithering and
applies an LCD sub-pixel mask in screen pixels. Lit objects use a toon shader with a
vertical colour gradient (dark at the base, bright at the top) and ink outlines, so shading,
gradients, fog and the sunset sky all break into ordered-dither patterns.

## Controls (arcade cabinet: stick + 1 button, optional 2nd button)

| Input                        | Keyboard / mouse                  | Gamepad            |
|------------------------------|-----------------------------------|--------------------|
| Aim                          | Arrows / WASD / mouse             | Left stick / D-pad |
| Button 1: confirm, hold=beam | Space / Enter / Z / Ctrl / LMB    | A / Start          |
| Button 2: missile salvo      | X / Shift / Alt / RMB             | B / X              |
| Fullscreen                   | F11                               |                    |
| Quit (exported build)        | Esc                               |                    |

The main gun fires automatically and endlessly. Button 1 is context-sensitive: it
confirms in menus, picks level-up cards, continues, enters initials, and in play it holds
the directed energy beam once you own it. Missiles auto-launch when ready.

## Progression

- Enemies attack from a cone in front of the battery: 30 degrees at level 1, 5 degrees
  wider per level, up to the full circle. Traverse is limited to that cone plus a margin.
- Kills drop XP chips that fly to the battery. Level up = pick 1 of 3 cards.
- Aim assist is on from the start: when an enemy is near the crosshair the gun drifts onto
  its lead point (strength `Game.AIM_ASSIST`; AESA Radar levels 4 and 5 make it stronger).
- Weapons (map to addon meshes in `player_ciws.glb`): Vulcan, AESA Radar, Quad Missiles, DEW Laser.
  The DEW Laser mounts on top of the missile pod, so it is only offered once you own Quad Missiles.
- Passives: Armor, Nanites, Hydraulics, Coolant, Optics, Scavenger, Lucky Charm, Tracers.
- Linked Mount (2 levels, takes no weapon or passive slot): adds a 2nd, then 3rd CIWS in a row.
  Wing mounts slave to your aim, converge on the crosshair, fire every weapon you own and
  show the same addons. The camera pulls back to keep the row in frame.
- Max-level weapon + the right passive = evolution, granted by the next loot crate.
- Gold / purple advanced units and UFO bosses drop a parachuted crate that spins a 3-reel slot
  machine: 1 reward, triple (3) or jackpot (5).
- Difficulty ramps with run time and level: enemy HP (shown as THREAT in the HUD), speed,
  contact damage, spawn rate and advanced-unit odds all climb.
- Level-up and loot screens freeze the world.
- 3 lives per credit, continue countdown, combo multiplier scoring, persistent top-10
  high score table with initials entry, attract mode.

## Touch and mobile

Touch controls appear automatically on a touchscreen (or with `--touch`):

- Left half of the screen: floating virtual stick, aims the turret.
- Right half: FIRE / BEAM button (tap, or hold for the laser). In menus it is OK.
- MSL button: fires a missile salvo early once the pod is owned.
- Menus: tap a card to select it, tap again to take it; swipe to move; tap to confirm.
- The game stays 4:3. Landscape screens get the controls in the side bars (or over the
  edges when the bars are thin). The Android build is locked to landscape (either way up,
  honouring the rotation lock); a portrait browser window on the Web build puts the game
  at the top with the controls underneath. The layout re-flows live when a foldable opens
  or closes.
- Taking damage vibrates the device.

Android (APK, arm64 + armv7, landscape locked, immersive) and Web (no-threads build, works on
plain static hosts and installs as a PWA) presets are included and built by CI.

## Building

Exports for Linux and Windows are produced by `.github/workflows/build.yml` on every push
(artifacts) and attached to a GitHub release on `v*` tags.

Locally, with Godot 4.5 and its export templates installed (Android also needs the SDK
build-tools and a debug keystore configured in the editor settings):

```
godot --headless --path . --import
godot --headless --path . --export-release "Linux"   build/linux/superciws.x86_64
godot --headless --path . --export-release "Windows" build/windows/superciws.exe
godot --headless --path . --export-release "Web"     build/web/index.html
godot --headless --path . --export-release "Android" build/android/superciws.apk
```

Debug launch flags (after `--`): `--autostart`, `--fast-forward=120`, `--autoaim`, `--touch`, `--mounts=1..3`,
`--state=levelup|slot|scores|continue|nameentry|destroyed`.

## Credits

Explosion sprites from `verdictzero/galvarius`. Models and branding by verdictzero.
Font: Press Start 2P (CodeMan38), under the SIL Open Font License, see `assets/fonts/`.
