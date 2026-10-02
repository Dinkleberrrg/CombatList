# CombatList

Every mob your group is fighting, in one list — with who it is currently
attacking, and clickable to target. Built for **Octo WoW (client 1.12)**.

## The row

```
▌+ Kobold Overseer 12  82%          > Thrall
```

* health bar as the row background, colored green → red
* `+` elite, `R` rare, `R+` rare elite, `B` world boss
* mob name and level, health percent
* `>` followed by whoever it is beating on — **YOU** in red, party members in
  class color, everyone else grey
* a red stripe on the left edge marks the mobs that are on you
* greyed-out bar = the mob is out of range and the data is a moment stale

Mobs attacking you sort to the top; everything else keeps the order it was
discovered in, so rows do not jump around mid-fight.

## Clicks

| Click | Effect |
| --- | --- |
| Left | Target the mob |
| Shift + Left | Target whoever the mob is attacking |
| Right | Dismiss the row (it comes back if the mob is still active) |

Hovering a row shows the normal unit tooltip.

## Commands

| Command | Effect |
| --- | --- |
| `/cl lock` | Lock/unlock the window for dragging |
| `/cl width <n>` | Window width (120–500) |
| `/cl height <n>` | Row height (10–40) |
| `/cl rows <n>` | Maximum rows (1–40) |
| `/cl scale <n>` | Scale (0.5–2.0) |
| `/cl level` / `/cl hp` / `/cl target` | Toggle the parts of a row |
| `/cl mine` | Only show mobs attacking me |
| `/cl clear` | Empty the list |
| `/cl status` | What is tracked right now |

## How it finds the mobs

This addon leans on **SuperWoW** (`SuperWoWhook.dll`, active on this
install). SuperWoW gives `UnitExists(unit)` a second return value — the
unit's GUID — and that GUID then works as a unit token anywhere, including
`GUID.."target"`. That last part is the whole trick: it is how each mob's
current victim is read directly, rather than guessed from the combat log.

Two discovery sources feed the list:

1. **`UNIT_CASTEVENT`** — SuperWoW reports caster GUID and target GUID for
   every cast and swing. This catches mobs nobody in the group has selected.
2. **Unit token scan** — `target`, `targettarget`, `pettarget`, `mouseover`
   and every party/raid member's target, every 0.15 s (raid targets once a
   second).

Entries are keyed by GUID, so two mobs with the same name stay two rows.
They drop out when they die, when they leave combat (3 s grace), or after
8 s without a sighting.

Without SuperWoW the addon still loads but degrades to the handful of mobs
reachable through plain unit tokens, keyed by name — it says so on login.

## Files

```
core.lua     namespace, config, GUID + group helpers, colors
tracker.lua  discovery, live refresh, pruning, sorting
ui.lua       the window, rows, click handling
slash.lua    /cl
_test/       offline harness (stubs SuperWoW; not loaded by the game)
```
