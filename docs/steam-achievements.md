# Steam achievements integration

## Implemented

The game has **21 public and 5 secret achievements**. The original nine save IDs are unchanged. F6 opens three pages; the mouse wheel and arrow buttons change pages. Locked secret cards hide both their name and condition. Local progress lives in `user://achievements.cfg`; existing unrelated sections are preserved.

`scripts/achievement_catalog.gd` is the stable ID registry. German and English text is stored in the central locale files. Mining and crafting counters persist between sessions. Host-earned co-op unlocks use the existing authenticated achievement replication path.

**This project does not include or initialize a Steam SDK/plugin.** Local unlocks work without Steam. The optional delivery queue is implemented and tested against a fake asynchronous provider; a real Steam backend has not been tested.

## Provider contract

Attach an initialized adapter with:

```gdscript
game.combat_events.set_achievement_provider(adapter)
```

The adapter must expose:

- `achievement_ready() -> bool`: true only when the correct application and local account have valid Steam achievement state.
- `store_achievements(api_names: Array[String], token: int) -> bool`: submit the supplied batch, retaining its token for the callback.
- Signal `achievements_stored(token: int, success: bool)`: emit only after the matching server storage callback. A request being accepted is insufficient.

The adapter should call Steam's `SetAchievement` for every name and then `StoreStats`. Verify the callback application/account before acknowledging. Steam separates setting local state from storing it remotely. [Official ISteamUserStats documentation](https://partner.steamgames.com/doc/api/ISteamUserStats#SetAchievement)

The queue deduplicates IDs, retains offline awards, waits for readiness, ignores stale callback tokens, and times out missing acknowledgements after 25 seconds. Retries wait 60 seconds. It persists pending and confirmed IDs separately. Store requests can be rate limited; batching and retry delays follow that constraint. [StoreStats documentation](https://partner.steamgames.com/doc/api/ISteamUserStats#StoreStats)

Before a Steam release:

1. Choose and package a compatible Godot Steam extension for both Ubuntu and Windows, with your own application ID.
2. Implement the adapter above and initialize it only after the Steam client/login/stat callbacks succeed.
3. Use an account-specific achievement save path before loading records. Define how an existing offline profile is migrated; the development default is one local profile.
4. Create all API names below in Steamworks, set the secret flags, add DE/EN display text and locked/unlocked icons, and publish the backend configuration.
5. Test offline earning, reconnect, restart, account switching, callback rejection, and both native packages against that application.

## Stable mapping

| Save ID | Steam API name | Visibility | Trigger |
|---|---|---|---|
| `first_kill` | `LS_FIRST_KILL` | Public | Destroy an enemy with a personal weapon or trap. |
| `combo_five` | `LS_COMBO_FIVE` | Public | Score five kills with no more than five seconds between them. |
| `level_five` | `LS_LEVEL_FIVE` | Public | Reach level 5 with a character. |
| `armor` | `LS_ARMOR` | Public | Craft personal armor. |
| `trap` | `LS_TRAP` | Public | Deploy a crafted trap outside the bunker. |
| `turret` | `LS_TURRET` | Public | Deploy a crafted field turret. |
| `wave_five` | `LS_WAVE_FIVE` | Public | Survive wave 5 and open the lower levels. |
| `boss` | `LS_BOSS` | Public | Defeat the final boss in wave twenty. |
| `victory` | `LS_VICTORY` | Public | Win all twenty waves. |
| `research_first` | `LS_RESEARCH_FIRST` | Public | Research the first shared technology. |
| `base_engineer` | `LS_BASE_ENGINEER` | Public | Research three different base technologies in one bunker. |
| `field_medic` | `LS_FIELD_MEDIC` | Public | Successfully revive another character. |
| `miner_50` | `LS_MINER_50` | Public | Mine a total of 50 resource units. |
| `craft_five` | `LS_CRAFT_FIVE` | Public | Craft five equipment items in total. |
| `cargo_full` | `LS_CARGO_FULL` | Public | Fill every slot in the convoy cargo hold. |
| `convoy_route` | `LS_CONVOY_ROUTE` | Public | Complete a convoy journey to the next bunker. |
| `base_capture` | `LS_BASE_CAPTURE` | Public | Defeat a new bunker's garrison and take control. |
| `roadside` | `LS_ROADSIDE` | Public | Secure a guarded roadside stop. |
| `epic_weapon` | `LS_EPIC_WEAPON` | Public | Recover a rare weapon from a roadside depot. |
| `convoy_upgrade` | `LS_CONVOY_UPGRADE` | Public | Research the first vehicle upgrade. |
| `all_dance_moves` | `LS_ALL_DANCE_MOVES` | Public | Learn all thirty personal dance moves across the six characters. |
| `solo_victory` | `LS_SOLO_VICTORY` | Secret | Win all twenty waves in solo play. |
| `pristine_core` | `LS_PRISTINE_CORE` | Secret | Win all twenty waves without any bunker core damage. |
| `last_drop` | `LS_LAST_DROP` | Secret | Finish a convoy journey with less than one litre left. |
| `loaded_arrival` | `LS_LOADED_ARRIVAL` | Secret | Capture a new bunker with at least 18 resource units aboard. |
| `all_routes` | `LS_ALL_ROUTES` | Secret | Secure all eight bunkers on the main route. |

## Gameplay hooks and checks

`CombatEvents.record_mined(amount)` receives the actual depleted ore-cell yield. Completed player medical aid unlocks revival; completed workshop recipes update crafting. Research is observed from actual owned technologies. The core records any real damage, so later repairs cannot grant the pristine-core secret.

ExpeditionController calls `record_campaign_event(kind, data)` for `route_complete` (`fuel`), `occupation_complete` (`cargo_count`), `roadside_complete` (`weapon`), and `campaign_complete`. The vehicle awards a full hold only after an accepted cargo transfer.

Dance moves unlock at character levels 2, 4, 6, 8 and 10. `CombatEvents.record_character_dance_level(character_id, level)` records the highest actual level reached by each character in the `dance_levels` save section. Reaching level 10 with all six characters unlocks `all_dance_moves`. The music laboratory previews locked moves without granting levels, moves or achievements.

Validation:

```bash
godot --headless --path . --script tests/achievement_catalog_test.gd -- --no-profile-save
godot --headless --path . --script tests/combat_rewards_test.gd -- --no-profile-save
godot --headless --path . --script tests/dance_unlock_test.gd -- --no-profile-save
```

The dedicated suite covers the 26 IDs, secret redaction/reveal, legacy migration, saved counters, gameplay thresholds, damage history, and delivery failures/acknowledgements. Dance checks cover character-specific locks, permanent unlocks, the personnel panel and preview isolation. It does not simulate a real Steam account.
