# Changelog

New, changed, fixed or removed features, one line each, brief and direct. The section for a release becomes the release notes.

## 1.1.1

- Changed: Hide stowed support weapon is off by default.
- Fixed: In an exosuit or a mannable turret, the crosshair shows while firing again. The pilot counted as a driver with no gun.
- Fixed: An arc weapon fires the way the weapon points only while Weapon ergonomics is on, never along a way left over from an earlier frame.

## 1.1.0

- New: Weapon ergonomics option under Aiming, on by default. Every shot, laser beam and arc leaves along the way the weapon points, the weapon swings onto the crosshair while aiming or firing, and the crosshair shows where the weapon points until it gets there. Off, shots go straight to the crosshair, and the weapon tilts up and down no faster than the Helldiver turns.
- New: Camera sideways distance option, the meters between the camera and the shoulder.
- New: Aiming a support weapon over the right shoulder moves the camera farther to the side.
- New: Hide stowed support weapon option, on by default. A support weapon on the back, such as the Dum-Dum, no longer blocks the view while another weapon is in hand.
- New: The in-game settings open one page per group, so the list no longer runs off the screen. Needs Obsidian API 1.58.1 or later.
- Changed: A laser swings onto the crosshair more slowly while firing.
- Changed: Camera shake while firing a laser is 75 percent weaker.
- Changed: The ammo bar is 20 percent thinner, 10 percent more transparent, and has no lines between rounds.
- Changed: In a vehicle, the driver no longer gets the aiming crosshair, and a seat with a gun shows the crosshair only while firing.
- Removed: The blocked shot mark, the red X where something close would stop the shots, and the option for it.
- Fixed: An Illuminate confusion turns the camera controls around too, not only movement and stratagems.
- Fixed: The Helldiver no longer bends backward while holding a throw or switching weapons with the aim button held.
- Fixed: The crosshair hides while the Helldiver sits in a Hellpod on the Super Destroyer, and comes back on climbing out.

## 1.1.0-beta.2

- Removed: The blocked shot mark, the red X where something close would stop the shots, and the option for it.
- Fixed: The crosshair hides while the Helldiver sits in a Hellpod on the Super Destroyer, and comes back on climbing out.

## 1.1.0-beta.1

- New: Camera sideways distance option, the meters between the camera and the shoulder.
- New: Hide stowed support weapon option, on by default. A support weapon on the back, such as the Dum-Dum, no longer blocks the view while another weapon is in hand.
- New: The in-game settings open one page per group, so the list no longer runs off the screen. Needs Obsidian API 1.58.0 or later.
- Changed: Every shot, laser beam and arc leaves along the way the weapon points. While aiming or firing, the weapon swings onto the crosshair, and the crosshair shows where the weapon points until it gets there.
- Changed: A laser swings onto the crosshair more slowly while firing.
- New: Weapon ergonomics option under Aiming, on by default. Off, shots go straight to the crosshair as before, and the weapon tilts up and down no faster than the Helldiver turns.
- Changed: The ammo bar is 20 percent thinner and 10 percent more transparent.
- Changed: Camera shake while firing a laser is 75 percent weaker.
- Fixed: An Illuminate confusion turns the camera controls around too, not only movement and stratagems.
- Fixed: The Helldiver no longer bends backward while holding a throw or switching weapons with the aim button held.

## 1.0.1

- Fixed: The top-down view kept the longer throws and weapon range of the third-person view.
- Fixed: A gamepad turns the view while another window is in front, so split-screen tools such as Nucleus Co-op work for every player.

## 1.0.0

- Changed: Eyes of Liberty leaves Early Access.
- New: Releases also go to the Nexus Mods page.

## 0.16.0

- New: Pings on ammo boxes, blue with the Resupply icon, and on research samples, white with the sample icon.
- New: An enemy ping also plays one of the stratagem arrow sounds.
- Changed: A ping goes to an objective only within 5 m of it, down from 12 m.
- Changed: Ping markers out of view keep to the screen edges as the markers of allies do.
- Changed: The ping diamond is 15 percent smaller, and the line has a thin outline. The pulse up the line is gone, and markers no longer fade while the crosshair is on them.
- Fixed: Weapon follows aim no longer snaps back to the plain pose when looking far down.

## 0.15.1

- Fixed: Weapon follows aim bends the Helldiver on screen. In 0.15.0 the bend came after the frame was drawn, so the weapon stayed level.
- Changed: The ammo bar shows a line between rounds for weapons of up to 50 rounds, up from 40.

## 0.15.0

- New: Weapon follows aim option, on by default. While aiming or firing on foot, the Helldiver bends up or down so the weapon points where the crosshair is.
- New: With a mouse and no other mod drawing the crosshair, the crosshair is the aiming cursor of the game, held in the middle of the screen, with the change the game shows when aiming starts and stops.
- New: Compass options for width, background opacity and the view angle line and heading.
- New: Pings while down, and after death until the camera moves to an ally.
- Changed: Settings are grouped by what they change, and every setting that applies at once is also in the pause menu.
- Changed: F is the default ping key.
- Changed: The explosion kick is five times stronger. Hellpod landings no longer kick.
- Changed: When another pod of the squad comes down first, the Hellpod camera waits high above it, then moves over to the pod of the Helldiver.
- Changed: The glide from the Hellpod into the shoulder view starts 0.4 seconds sooner.
- Changed: On a throw, the throw arc stays in place and fades out over a second.
- Changed: Compass icons show over the compass letters.
- Changed: Enemy indicators show only while the Helldiver is alive or down.
- Changed: The ammo bar of a laser fills from the bottom, in a brighter yellow.
- Changed: Patrols stay in view also keeps patrol enemies chasing a Helldiver out to 200 m, and enemies of alarms and objective waves out to 100 m, where the game removed them at 40 m.
- Fixed: The Helldiver no longer shakes against the camera when frame times change, as with many effects on screen.
- Fixed: Lasers fire up and down. A beam that hit nothing was drawn level.
- Fixed: An arc weapon bolt that finds no target flies toward the crosshair.
- Fixed: The Hellpod camera no longer follows the pods of bots.

## 0.14.0

- New: Ammo bar. A short arc by the crosshair shows the magazine, laser heat or arc charge and the reload, in the style of the Better HUD ammo and reload circles, with options for position, shape and scale. With Better HUD 1.18.0 or later, both circles stay hidden while the bar is on.
- New: Explosion kick. A blast nearby knocks the camera: it rolls away, tips up and rises, then springs back. Bigger blasts kick harder and from farther; blasts in a row kick less each time.
- New: Alarm effect. During an alarm, the screen edges pulse red once, and broad red stripes flash up both sides of the screen and settle to a faint glow. It replaces the red overlay of the game, which often showed shrunk in third person. An option turns it off.
- New: Map markers show on the compass and in the level as pings, one per player, with the map marker icon in the colour of that player, for as long as the marker is on the map.
- New: Blocked shot mark. A small red X marks where shots would land when something within 6 m of the weapon, between it and the crosshair, would stop them.
- New: Scroll camera distance option, off by default. The mouse wheel moves the camera closer or farther on foot instead of switching weapons.
- New: The Helldiver is hidden while the camera is pressed against it, by a wall or in a tight corner.
- Changed: The crosshair shows only while the Helldiver can shoot: not while dead, dropping in the Hellpod, putting in a stratagem or looking at the map.
- Changed: Compass icons slide out at the ends of the compass instead of waiting there, and a small white triangle outside each end points to anything past it.
- Changed: Enemy pings and map marker pings show without the vertical line.
- Changed: Pings on dropped weapons and packs sit lower, with a larger icon.
- Changed: While the crosshair is near a ping, the line and marker fade to half, so the words and what lies behind stay readable.
- Changed: A new icon.
- Fixed: Reduce fog now thins the fog as set. The fog of the level was read before it settled, and low settings still left much of the fog.
- Fixed: Pinging a dropped support weapon or pack marks it again. Needs Obsidian API 1.55.1.
- Fixed: The Helldiver no longer disappears high in a jump pack flight while the backpack and weapons stay.

## 0.13.1

- Changed: Reduce fog goes down to 0, which removes the fog.
- Fixed: Fog facing the sun no longer shows as a bright, near solid wall. Below 1, Reduce fog also thins the sunlit side of the fog and keeps it close to the brightness of the rest.

## 0.13.0

- Fixed: A crash a few seconds into the second mission of a session, when the hurt flash, the throw ring or the idle cursor drew on screen.
- Fixed: The hurt flash no longer shows in the top-down view of the game.
- New: Pings. The ping key (middle mouse button) marks what the crosshair is on: the ground, an enemy, an objective, or a dropped support weapon or pack. Teammates with the mod see the marker and hear the chat sound; nothing goes to the chat of the game. Three pings in a row, then a wait of 2.5 seconds.
- New: A compass at the top of the screen in third person, with the heading in degrees, pointing to every objective found on the map with the white map icon.
- New: The screen tints red after a death and fades back over two seconds.
- Changed: Max weapon range is now Ballistics revamp: past the range of the weapon, bullets lose damage over 15 m, down to a fifth. Lasers keep their damage.
- Changed: Objectives out of view no longer show at the edge of the screen; the compass shows them.
- Changed: Weapon fire and hurt feedback shake the camera half as much.
- Changed: Remove fog is now Reduce fog, a slider from 0.1 to 1 for how fast the fog builds up with distance (0.5 by default), in place of taking it away.
- Changed: Long view distance no longer pushes the fog out; Reduce fog is the only option that changes the fog.

## 0.12.0

- Fixed: Shots go where the crosshair points at any height, close or far; aiming straight or up no longer sends them over the target.
- Changed: Grenades and stratagem balls fly to the crosshair on a low arc instead of a high lob, and the throw arc shows the same path.
- Changed: The throw arc stands out more: thicker, brighter dashes and ring, each with a soft shadow.
- Fixed: The red alarm overlay covers the whole screen again instead of a frame in the middle.
- Fixed: Starting the game while another window is in front no longer holds the mouse in the middle of the screen.

## 0.11.0

- New: Hurt feedback: the edges of the screen flash red and the camera shakes briefly when the Helldiver loses health, stronger for bigger hits.
- New: Patrols stay in view: patrols within 100 m of a Helldiver are no longer removed off the top-down screen, so they don't arrive again when they come close.
- New: The camera follows the Helldiver up during a jump pack jump.
- Changed: Hit direction is now called Hurt indicator.
- Changed: The throw arc ring is white and more opaque.
- Changed: The sprint camera sway follows the speed of the Helldiver, smaller and slower when a sprint is slowed, as in water.
- Changed: Between shots, the crosshair shows the idle cursor of the game when the game keeps the crosshair on screen, and nothing otherwise, as in the top-down view.
- Fixed: The red alarm overlay covers the whole screen in third person.

## 0.10.0

- Changed: The vehicle and mech camera sits 1.5 m higher in every view.
- Changed: The throw arc is white, with more frequent, fainter and thinner dashes.
- Fixed: The extraction camera follows the shuttle when it takes off.
- Fixed: The extraction camera no longer clips into the shuttle while turning.
- Fixed: Placing a map marker from a mech no longer fires the mech.
- Fixed: The game crosshair returns when switching from third person to the top-down view.

## 1.1.1

- Changed: Edge markers leave allies to the off-screen marker of the game, with the name. That marker now points the right way for allies behind the camera, and turns red while the ally is down.
- Fixed: edge markers at the bottom of the screen sat behind the player panels.

## 1.1.0

- New: Edge markers, on by default. In third person, allies, stratagem beacons and objectives out of view show at the edge of the screen, with the icons and colours of the map. Allies show as the player arrow in the colour of the player, red while downed.
- New: Throw arc, on by default. In third person, while a grenade or a stratagem ball is held, a dashed line shows the way it would fly if thrown now, and a ring where it first lands.
- New: Extraction camera, on by default. Once the Helldiver boards the shuttle, the camera rides with the shuttle as it takes off and flies away, until the mission ends.
- New: on a gamepad, a tap of the right stick swaps the shoulder. Holding it to talk does not.
- Fixed: on the ship, the "!" over crew members behind the camera showed mirrored on screen, as if floating in the room. Prompts and name cards behind the camera are hidden the same way.

## 1.0.2

- New: an icon in Obsidian.

## 1.0.1

- Changed: on a gamepad in third person, holding the left trigger aims, and the right stick only turns the camera. While aiming, the reload button throws grenades instead of reloading.

## 1.0.0

- Changed: Unleashed Camera is now Eyes of Liberty, under the id alomare.eyesofliberty. Remove Unleashed Camera when installing it: while Unleashed Camera or Integrated Third Person is installed, Eyes of Liberty stays off.
- New: Death cam, on by default. When the Helldiver dies, the camera stays on the body, or where the body was once the game removes it, until the Helldiver drops in again or the mission ends. With allies alive, the camera moves to one of them after 4 seconds. Left and right click switch between allies, and the mouse turns the camera.
- Changed: after a death in a squad, the Hellpod camera also rides down with the reinforced Helldiver.
- Removed: first person, which moves to separate beta versions.

## 0.9.1

- New: in first person, throwing, calling stratagems, using objectives, reviving and carrying show the arms of the Helldiver as the game animates them, in place of lowering the weapon.

## 0.9.0

- New: first person arms. The arms hold the weapon in view, with motion for walking, sprinting, aiming, firing, reloading, melee, switching weapons, throwing, calling stratagems, diving and being downed. The option Arms and weapon, under First person, is on by default.
- New: assault rifles and the standard pistol have holds of their own. Other weapons use the rifle hold, and other sidearms the pistol hold.
- Changed: with the arms on, first person hides the whole body, and looking down no longer moves the camera forward.
- Changed: new skies, drawn for each time of day: brighter toward the horizon, a sun where the light of the level comes from, clouds in perspective, and stars and a moon at night.
- Fixed: the sky was a flat dome with clouds circling overhead.

## 0.8.2

- Fixed: the sky was the day sky in every mission. It now follows the time of the mission: dawn, day, dusk or night.
- Changed: the skies are the dawn, day, dusk and night skies of Photo Mode, with clouds and stars, in place of the plain skies in the colour of the planet fog.

## 0.8.1

- Fixed: Focus on the Helldiver showed almost no blur: the sharp zone was so deep that only things far past the Helldiver blurred, and barely. It is now 2 m deep around the Helldiver, at full blur outside it. In first person it is around the crosshair point.
- Removed: the Disable bloom option. The bloom was bright mostly because of the sky, which 0.8.0 fixed.

## 0.8.0

- Changed: the mod id is now alomare.unleashedcamera. Obsidian installs it as a new mod: remove Integrated Third Person after installing it. Settings start from the defaults again.
- Changed: while Integrated Third Person is still installed, Unleashed Camera stays off and says so.
- Changed: less work every frame for the screen checks of the game, the weapon aim, the hidden helmet in first person and the depth of field that follows the Helldiver.
- New: Eye height, Eye forward and Eye side options for the first person camera.
- Changed: the options are in new groups: Camera, Third person, First person, Vehicles, Indicators and names, Picture, and Session features.
- Changed: the Hellpod camera rides down above the pod and a little ahead, looking almost straight down, so the pod stays in the middle of the picture.
- Fixed: the sky over the level was far too bright on every planet, at night too. It is now drawn at most as bright as made, the brightness Photo Mode uses, and dimmer under a darker planet fog.

## 0.7.0

- Changed: the mod is now called Unleashed Camera. Settings and installs carry over.
- Changed: in first person the body turns with the view without the aiming walk, so the Helldiver moves at full speed and can throw, call stratagems and interact.
- Changed: the first person camera sits higher and farther forward, and moves forward while looking down, so the inside of the body no longer shows.
- Changed: the camera sway while sprinting is a little stronger.
- Changed: while a flamethrower of the player fires, the Lumberer included, camera shake is 80% weaker.

## 0.6.0

- New: first person, as a prototype. The Camera mode option picks the camera at the start (Default, Third person or First person), and the camera key cycles the three. In first person the camera sits in the head of the Helldiver and the helmet is hidden. Walking backwards steps back instead of turning round, and standing still the body turns only once the view has turned far enough.
- New: First person field of view option.
- New: Overall camera height option, which raises or lowers the third-person camera everywhere.
- New: a slight camera sway while sprinting. It follows the Camera shake option.
- New: the crosshair fades out while sprinting, Custom Crosshair included.
- Changed: the downed camera sits as low as the dive camera.
- Changed: the on-foot camera distance is 3 m by default.
- Changed: the Hellpod camera sits farther from the pod, waits longer before the glide, and the view stays still until the Helldiver climbs out.
- Changed: the lobby-wide options are named Session features.
- Removed: the Footsteps option.

## 0.5.0

- New: Remove fog option, on by default. Photo Mode shows the fog while it is open.
- New: Disable bloom option, on by default. Photo Mode shows the bloom while it is open.
- New: Depth of field option: Game default, Focus on the Helldiver, or Off (the default). Photo Mode sets the depth of field while open.
- New: downed camera. While the Helldiver is down, the camera sits near the ground and 1 m farther back.
- New: Increased throw range, a lobby-wide option, on by default. Grenades and stratagem balls fly twice as far, on top of the Strong Arm perk.
- Changed: the crosshair of the game shows in third person instead of a crosshair of the mod, and Custom Crosshair replaces it when installed.
- Changed: the own name card is hidden in third person. The cards of other players stay.
- Changed: the camera on foot in a mission is 1 m farther away by default.
- Changed: the dive camera only comes down and no longer moves closer.
- Changed: the segments of the enemy indicator ring are twice as thick.
- Fixed: the hardware cursor of the game showed in third person, away from the crosshair.
- Fixed: marks over the crew and the terminals on the Super Destroyer trailed behind the camera.

## 0.4.2

- Changed: the crosshair handed to other mods also says when fire or a throw is held, so Custom Crosshair shows the aiming look while firing.

## 0.4.1

- New: a soft camera rumble while a weapon fires, stronger for vehicle guns. It follows the Camera shake option.
- Changed: the camera on foot sits a little lower, between the heights of 0.3.0 and 0.4.0.
- Changed: the shakes of the game move the shoulder camera 12 cm at the most, so a run of explosions no longer shakes it all the time.
- Fixed: the Hellpod camera did not start, because the game drops a new Helldiver in before that Helldiver belongs to the player.
- Fixed: enemy and hit indicators stayed on screen with the third person view switched off.
- Fixed: the red screen of an alarm still stopped short of the screen edges.

## 0.4.0

- New: Hellpod camera. When the Helldiver drops in, the camera rides the pod down looking at the ground, shakes on the landing, then glides into the shoulder view.
- New: Camera shake option (Off, Weak, Medium, Strong). Explosions and impacts now shake the shoulder camera too.
- Changed: enemy indicators are one ring around the crosshair in four segments. The right, back and left segments show faintly while an enemy is within 15 m on that side and stronger within 7.5 m, and the side with the closest enemy within 7.5 m shows a warning triangle. The ring hides while the game is paused.
- Changed: aiming no longer narrows the field of view; the camera comes in closer and in behind the head instead.
- Changed: the camera is 1 m farther away on foot and on the Super Destroyer, and sits higher on foot.
- Changed: beside a mech the camera sits farther to the side and about 2 m closer.
- Changed: vehicle guns always fire level, the way they point, so a mech no longer has to look up to shoot ahead.
- Fixed: the red screen of an alarm covers the whole screen instead of the middle.
- Removed: the ship walls.

## 0.3.0

- New: free movement, a lobby-wide option. In third person the Helldiver is no longer held on the shared top-down screen with the squad.
- New: a separate camera distance for the Super Destroyer, 3 m closer than in a mission by default.
- New: in a mech the camera sits beside the shoulder, on the same side as on foot. In any vehicle the swap key moves the camera from left to the middle to right.
- Changed: vehicle guns fire the way they point, at the height of the crosshair, instead of straight at the crosshair point while the gun is still turning.
- Changed: the camera on foot sits higher, while walking and while aiming.
- Changed: the dive camera also comes down toward the Helldiver.
- Changed: the on-foot camera distance is 4 m by default, and the vehicle field of view 70 degrees.
- Fixed: with the shield generator pack, grenades and stratagem balls always flew the full distance.

## 0.2.1

- Changed: enemy indicators are bigger. They scale with the hitpoints of the enemy from normal size up to one and a half times, where before they went from 0.8 to 1.2 times.

## 0.2.0

- New: dive camera. A dive brings the camera in close, and the camera eases back out once the dive ends.
- Changed: the shoulder swap, on H, glides across.
- New: a wall across the open back of the ship bridge.
- New: louder footsteps for Helldivers and enemies, with a Footsteps option.
- New: player name cards above heads instead of at the feet.
- New: a message when a second player joins on the same computer. Third person turns off and comes back once one player is left.
- Changed: enemy indicators show only enemies in sight, as fading white arcs, larger for enemies with more health.
- New: hit direction bars near the crosshair, red for health, yellow for the shield and white for vehicle hits.
- New: `shoulder()` for other mods.

## 0.1.2

- New: Obsidian offers updates from the GitHub repository.

## 0.1.1

- Fixed: the view no longer flickers to top-down while the shoulder camera draws.

## 0.1.0

- New: a shoulder camera on foot, in vehicles and on the ship, turned with the mouse or the right stick, with distance and field of view options, a shoulder swap, aim zoom and collision with rocks and walls. F8 switches between third person and the top-down camera.
- New: shots, laser sights, grenades and stratagem balls go where the crosshair points, with a plain crosshair.
- New: movement and vehicle steering follow the view.
- New: a long view with distant models kept detailed, a sky in the color of the planet fog, and walls on the open side of the ship bridge.
- New: enemy indicators, marks around the crosshair that point toward enemies in range.
- New: Max weapon range and Far enemy detection, two lobby-wide parts that switch off when a player without them joins.
- New: spawns, alarms and the squad leash still follow the top-down view, as in the game. The mod stays off with Third Person Camera installed.
