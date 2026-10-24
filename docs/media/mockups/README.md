# Mockups

`alts-window.html` and `alts-window.png` are design mockups of the Alts window in four states: populated, filtered by realm, empty, and on a Spanish client.

- They are not in-game screenshots. Every state carries a visible "DESIGN MOCKUP" label.
- The text in each row comes from the addon's own row builder (`Alts.Window.BuildRows` and `FooterText`) with fictional test characters, so the wording and numbers match what the addon produces. The colours, spacing and fonts are an approximation of the game's look.
- Use them for concept and planning only. Do not publish them in a CurseForge gallery as if they were screenshots. If one is ever used, its caption must say "design mockup".

Regenerate after changing any row text:

```
luajit scripts/gen-mockup.lua
```

The PNG is exported from the HTML with a headless browser.
