# MiniResourceDisplay bot reference

Addon: MiniResourceDisplay, version 2.8.7, by Verz.
Supported interface versions (from the .toc): 120100, 50504, 40402, 38002, 38000, 30405, 30300, 20506, 11509. This covers retail (12.1.0) and the Classic clients (Mists Classic, Cataclysm Classic, Wrath Classic, TBC Classic, Classic Era).
Saved variables: MiniResourceDisplayDB (account wide). Bundled libraries: LibStub, CallbackHandler-1.0, LibSharedMedia-3.0, LibUIDropDownMenu, MiniFramework.

## What it does

A simple personal-resource-style display: a movable health bar and power (mana/energy/etc.) bar for your character, with optional text, absorb shield and incoming heal indicators, an optional pet health bar, and on Classic clients a power tick marker that shows when the next mana/energy regen tick lands.

## Slash commands

- `/mrd` (also `/minird`, `/miniresourcedisplay`): opens the settings panel (Options -> AddOns -> MiniResourceDisplay).
- `/mrd reset`: resets all settings to defaults.
- `/mrd tick`: Classic clients only; prints power tick diagnostics (current power type, whether it ticks, polling state, time to next tick, five second rule remaining, and the recent gain history).
- Any other argument prints the command list.

## Features and behaviour

- Player bars: a health bar with a power bar below it, in a shared container. Either bar can be hidden. Bar fill animates smoothly on clients that support status bar interpolation.
- Visibility: by default the display only shows in combat, fading in when combat starts and out when it ends (1 second each way). "Always show" keeps it visible; out of combat it then uses the "Out of combat opacity" value.
- Moving: drag the bars with the left mouse button; position is saved. The "Locked" checkbox locks all bars (a locked frame also ignores the mouse). The player display defaults to screen centre, 140 pixels down; the pet bar to 165 pixels down.
- Text: current/max values on each bar, abbreviated for large numbers (e.g. "1.2K"). "Percentages" switches to percent. "Hide text suffix" drops the "%" and abbreviation suffixes and shows raw numbers.
- Health colour: green by default, or your class colour with "Class color health".
- Power colour: follows the standard Blizzard colour for your current power type (mana blue, rage red, energy yellow, and so on) by default.
- Shields (absorbs): a shield overlay fills the empty part of the health bar for absorbs; when absorbs exceed missing health, an overshield overlay fills backwards from the right edge of the bar. Colour and opacity are configurable; the whole indicator can be turned off.
- Incoming heals: a prediction bar in the empty part of the health bar for heals in flight, colour configurable (green by default).
- Pet bar: a separate health-only bar for your pet (no pet power bar). Off by default; only shows while a pet exists, and follows the same combat show/hide rules as the player bars. It has its own size and position but shares texture, text, colour and other appearance settings.
- Bar texture: chosen from LibSharedMedia "statusbar" textures. The default "Blizzard" is the stock UI status bar texture. Textures registered by other addons (e.g. SharedMedia) appear in the dropdown automatically, each row previewing its own texture next to the name; the list refreshes when the panel is opened. If a texture pack registers after login, the bars pick up the change automatically without a reload.
- Power tick (Classic clients only): a vertical marker sweeps across the power bar and restarts on every server regen tick (2 second cadence). Mana and energy only. The marker hides at full power, and for mana it hides while the five second rule is active and until the next real tick reveals the cadence. Energy ticks are recognised by the 20-energy tick amount (40 with Adrenaline Rush), so procs and refunds are ignored.

The display loads after you first enter the world, so it appears shortly after the loading screen, not at the login screen.

## Settings

All settings apply immediately. "Reset to defaults" (button at the top right of the main panel, with a confirmation popup) or `/mrd reset` restores everything.

### Main panel (MiniResourceDisplay)

Settings section:

| Option | Default | What it does |
|---|---|---|
| Locked | Off | Locks the position of all bars |
| Always show | Off | Show always instead of only in combat |
| Show text | On | Show hp and power text inside the bars |
| Percentages | Off | Show health and power as percentages |
| Show pet bar | Off | Separate health bar for your pet |
| Show health bar | On | |
| Show power bar | On | |
| Class color health | Off | Use your class colour for the health bar |

Size section:

| Option | Default | Range |
|---|---|---|
| Width | 150 | 100-400, step 10 |
| Height | 15 | 8-50, step 1 (per bar) |
| Text Size | 11 | 8-32, step 1 |

Pet Bar section:

| Option | Default | Range |
|---|---|---|
| Width | 150 | 100-400, step 10 |
| Height | 15 | 8-50, step 1 |

Look & Feel section:

| Option | Default | Notes |
|---|---|---|
| Texture | Blizzard | Dropdown of LibSharedMedia statusbar textures |

### Shield subpanel

| Option | Default | What it does |
|---|---|---|
| Show shields | On | Show the absorb/shield indicator on the health bar |
| Colour (swatch) | White, opacity 1 | Colour and opacity of both shield overlays |

### Incoming Heals subpanel

| Option | Default | What it does |
|---|---|---|
| Colour (swatch) | Green | Colour of the incoming heal prediction bar (no opacity control) |

### Power Tick subpanel (Classic clients only; panel does not exist on retail)

| Option | Default | Range / notes |
|---|---|---|
| Show power tick | On | Marker sweeping across the power bar, restarting on every regen tick |
| Thickness | 2 | 1-10, step 1 |
| Colour (swatch) | White, opacity 1 | Marker colour and opacity |

### Misc subpanel

| Option | Default | Range / notes |
|---|---|---|
| Hide text suffix | Off | Hides "%" and abbreviation suffixes such as "K" |
| Out of combat opacity | 1 | 0-1, step 0.05; only applies while "Always show" is on |

## Hidden settings (saved variables only, no UI)

These exist in MiniResourceDisplayDB but have no options widget:

| Key | Default | Effect |
|---|---|---|
| Font | Fonts\FRIZQT__.TTF | Bar text font |
| FontFlags | OUTLINE | Font outline flags |
| FontShadow | true | Drop shadow on bar text |
| Border | true | 1px black outline around each bar |
| Gap | 0 | Vertical gap between health and power bars |
| Padding | 2 | Container padding around the bars |
| HealthColor | 0,1,0 (green) | Health bar colour when class colour is off |
| PowerColor | 0.2,0.6,1.0 | Power bar colour when PowerUseTypeColor is off |
| PowerUseTypeColor | true | Colour the power bar by power type |
| FadeInDuration / FadeOutDuration | 1 / 1 | Combat fade times in seconds |
| HealthTextFormat / PowerTextFormat | %s/%s | Text format for current/max |

## Version-gated behaviour

- Power tick: only on Classic-lineage clients (Classic Era, TBC Classic, Wrath Classic, Cataclysm Classic, Mists Classic). On retail the Power Tick panel, the `/mrd tick` command, and the marker do not exist, because retail regen is continuous.
- On Midnight clients the addon uses the game's heal prediction calculator for absorbs and incoming heals instead of direct arithmetic; behaviour is the same for the user.
- Percent text uses the game's own percentage APIs where available, with a manual calculation as fallback on older clients.

## Troubleshooting by symptom

- Bars are not showing: by default they only show in combat. Turn on "Always show" to see them all the time. The display also only appears after entering the world.
- Bars are invisible out of combat even with Always show: check "Out of combat opacity" on the Misc panel; 0 makes them fully transparent.
- I cannot move the bars: untick "Locked" on the main panel, then drag with the left mouse button.
- Bars are stuck in the wrong place / off screen: use "Reset to defaults" or `/mrd reset`; positions are part of the settings. Bars are clamped to the screen while dragging.
- Pet bar not showing: "Show pet bar" must be on and you must currently have a pet. It also follows the combat visibility rules. The pet bar has no power bar by design.
- No power tick marker: it exists on Classic clients only. It also hides at full power, and for mana it hides during the five second rule after spending mana and stays hidden until the next real regen tick is observed. Rage, focus and runic power never tick. `/mrd tick` prints what the detector currently sees.
- Power tick marker seems out of sync: the cadence is inferred from observed regen gains, so it needs a tick or two to lock on after zoning or switching forms/power type. `/mrd tick` shows the recent gain intervals.
- Texture I want is not in the dropdown: only LibSharedMedia "statusbar" textures appear. Install an addon that registers them (e.g. SharedMedia) and reopen the settings panel; the list refreshes on open.
- No shield/absorb overlay: "Show shields" on the Shield panel must be on, and the unit must actually have an absorb.
- Text shows numbers instead of percent (or the reverse): toggle "Percentages" on the main panel. "Hide text suffix" removes the "%" sign and abbreviation letters.
- The bars have no text: "Show text" on the main panel, and note text only appears on bars that are shown.
- One bar missing: "Show health bar" / "Show power bar" hide individual bars; with both off the whole display hides.
