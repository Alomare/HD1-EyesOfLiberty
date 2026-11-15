# Rules for this repository

**Name and id.** The mod is Unleashed Camera, id `alomare.unleashedcamera` since 0.8.0 (repo `Alomare/HD1-UnleashedCamera`). Until 0.7.0 it was Integrated Third Person, id `alomare.integratedthirdperson`. Obsidian refuses an update whose id differs from the installed one (`core/src/updates.rs` stage), so old installs stay on 0.7.0 until the player removes them; while the old id is loaded, this mod stays off (`env.off`). Custom Crosshair and Better HUD import the new id first and the old one after; Enhanced Visuals loads after both.

**Every release has a changelog.** Before tagging, add a section for the version to `CHANGELOG.md`, headed `## <version>`. Each change is one list item, starting `- New:`, `- Changed:`, `- Fixed:` or `- Removed:`, and describes the change briefly and directly. The shared Release workflow publishes that section as the release notes on GitHub, and stops if the section is missing or breaks the rules for public text.
