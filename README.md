# SUPER CIWS

Retro arcade roguelike. You are a stationary CIWS battery in the desert. The gun never
stops firing; you aim with the stick, intercept drones and missiles, level up Vampire
Survivors style, and loot elite kills through a slot machine.

Built with **Godot 4.5** (GL Compatibility renderer). Renders 3D at 512x384 (4:3) with a chunky 256x192 HUD, then a post shader quantises
everything to a 128-colour SNES-style palette and applies an LCD sub-pixel mask in screen
pixels.

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
- Weapons (map to addon meshes in `player_ciws.glb`): Vulcan, AESA Radar, Quad Missiles, DEW Laser.
  The DEW Laser mounts on top of the missile pod, so it is only offered once you own Quad Missiles.
- Passives: Armor, Nanites, Hydraulics, Coolant, Optics, Scavenger, Lucky Charm, Tracers.
- Max-level weapon + the right passive = evolution, granted by the next loot crate.
- Gold / purple elites and UFO bosses drop a parachuted crate that spins a 3-reel slot
  machine: 1 reward, triple (3) or jackpot (5).
- Difficulty ramps with run time and level: enemy HP (shown as THREAT in the HUD), speed,
  contact damage, spawn rate and elite odds all climb.
- Level-up and loot screens freeze the world.
- 3 lives per credit, continue countdown, combo multiplier scoring, persistent top-10
  high score table with initials entry, attract mode.

## Building

Exports for Linux and Windows are produced by `.github/workflows/build.yml` on every push
(artifacts) and attached to a GitHub release on `v*` tags.

Locally, with Godot 4.5 and its export templates installed:

```
godot --headless --path . --import
godot --headless --path . --export-release "Linux"   build/linux/superciws.x86_64
godot --headless --path . --export-release "Windows" build/windows/superciws.exe
```

Debug launch flags (after `--`): `--autostart`, `--fast-forward=120`, `--autoaim`,
`--state=levelup|slot|scores|continue|nameentry|destroyed`.

## Credits

Explosion sprites from `verdictzero/galvarius`. Models and branding by verdictzero.
