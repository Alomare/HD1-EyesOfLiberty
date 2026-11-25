# Eyes of Liberty

A third person camera for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianLauncher) mod manager. Formerly Unleashed Camera, and before that Integrated Third Person: remove either one when installing this mod. Based on [Third Person Camera (HD2 Style)](https://github.com/yukiorsrs/third-person-camera-helldivers) by **yukiorsrs**, rebuilt with permission from the author so other mods keep working beside it.

The camera follows the Helldiver over the shoulder on foot, in vehicles and on the ship. Shots go where the weapon points, and the weapon swings onto the crosshair while aiming or firing. Until then, the crosshair shows where the weapon points. Grenades and stratagems go where the crosshair points.

The view reaches farther, and the sky over the level is filled in. On screen:

- A ring around the crosshair warns of nearby enemies.
- A bar shows where hits come from, and the screen edges flash red when the Helldiver is hurt.
- A compass at the top shows the way to objectives found on the map.
- Off-screen stratagem beacons and allies show at the screen edge. Downed allies show in red.
- A dashed line shows where a held grenade or stratagem ball would fly.

The ping key marks enemies, objectives, dropped support weapons or a spot on the ground for the squad. After a death, the camera stays on the body, then follows a living ally until the Helldiver is back. After extraction, it rides the shuttle out.

Third Person Camera replaces 28 game scripts, so mods that change the same parts of the game stop working with it. Eyes of Liberty replaces none: every change is a hook through Obsidian.

## How to use

**F8** switches between the top-down camera and third person. **H** swaps shoulders. **F** pings what the crosshair is on. The keys can be changed in Obsidian.

On gamepads, the right stick turns the camera and holding the left trigger aims. While aiming, the reload button throws grenades. Tapping the right stick swaps shoulders. While the death cam follows allies, left and right click switch between them.

## Playing with others

The camera and everything on screen work in any lobby. 5 session features change the game for the whole lobby:

- Ballistics revamp: every weapon reaches far, with damage falling off past the normal range of the weapon.
- Far enemy detection.
- Free movement.
- Increased throw range.
- Patrols stay in view.

These run only when every player runs Obsidian with the same mods, and switch off when anyone else joins. With all 5 off, the mod counts as a client mod.

Pings show only for teammates with the mod. Nothing goes to the game chat.

## Known issues

- Local co-op players share one screen, so the camera goes back to top-down while a second local player is in, and comes back after.
- The mod stays off while Third Person Camera, Unleashed Camera or Integrated Third Person is installed.

First person is in development, for separate beta versions.

Mod authors can read the camera state through `obsidian.import("alomare.eyesofliberty")`: `active()`, `mode()`, `crosshair()` and `shoulder()`.
