# Eyes of Liberty

A third person camera for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianLauncher) mod manager. Formerly Unleashed Camera, and before that Integrated Third Person: remove either one when installing this mod. Based on [Third Person Camera (HD2 Style)](https://github.com/yukiorsrs/third-person-camera-helldivers) by **yukiorsrs**, rebuilt with the permission of the author so that other mods keep working beside it.

The camera follows the Helldiver over the shoulder on foot, in vehicles and on the ship. Shots, grenades and stratagems go where the crosshair points. The view reaches farther, the sky over the level is filled in, a ring around the crosshair warns of enemies close by, a bar shows where hits come from, and the edges of the screen flash red when the Helldiver is hurt. A compass at the top of the screen shows the way to the objectives found on the map. Stratagem beacons out of view show at the edge of the screen, as do allies, red while down, and a dashed line shows where a held grenade or stratagem ball would fly. The ping key marks enemies, objectives, dropped support weapons or a spot on the ground for the squad. After a death the camera stays on the body, then follows a living ally until the Helldiver is back. After extraction it rides the shuttle out.

Third Person Camera replaces 28 game scripts, so mods that change the same parts of the game stop working with it. Eyes of Liberty replaces no script: every change is a hook through Obsidian.

## How to use

**F8** switches between the top-down camera of the game and third person. **H** swaps the shoulder. **F** pings what the crosshair is on. The keys can be changed in Obsidian. On a gamepad, the right stick turns the camera and holding the left trigger aims; while aiming, the reload button throws grenades. A tap of the right stick swaps the shoulder. While the death cam follows allies, left and right click switch between them.

## Playing with others

The camera and everything on screen work in any lobby. Five session features change the game for the whole lobby: Ballistics revamp (every weapon reaches far, with damage falling off past the weapon's own range), Far enemy detection, Free movement, Increased throw range and Patrols stay in view. They run only when every player runs Obsidian with the same mods, and switch off when anyone else joins. With all five off, the mod counts as a client mod.

Pings show only for teammates who run the mod; nothing goes to the game's chat.

## Known issues

- Players on one computer share a screen, so the camera goes back to top-down while a second local player is in, and comes back after.
- The mod stays off while Third Person Camera, Unleashed Camera or Integrated Third Person is installed.

First person is in development for separate beta versions.

Mod authors can read the camera state through `obsidian.import("alomare.eyesofliberty")`: `active()`, `mode()`, `crosshair()` and `shoulder()`.
