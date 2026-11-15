# Rules for this repository

**Name and id.** The mod is Unleashed Camera (repo `Alomare/HD1-UnleashedCamera`, formerly Integrated Third Person, renamed 2026-11-15). The id stays `alomare.integratedthirdperson`: Obsidian refuses an update whose id differs from the installed one (`core/src/updates.rs` stage), and Custom Crosshair, Better HUD and Enhanced Visuals import or order by that id. Never change it.

**Every release has a changelog.** Before tagging, add a section for the version to `CHANGELOG.md`, headed `## <version>`. Each change is one list item, starting `- New:`, `- Changed:`, `- Fixed:` or `- Removed:`, and describes the change briefly and directly. The shared Release workflow publishes that section as the release notes on GitHub, and stops if the section is missing or breaks the rules for public text.
