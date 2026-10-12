============================================================
        ROKUMENU v0.5  (GON 1.3 / UE5 in-game menu)
============================================================

An in-game menu for the same cheats as GONTrainer, plus
camera tools and saved mouse/volume settings.
==This could break with an update and I may not update this==

Compatible with UE4SS Latest Experimental.
Do NOT run this and GONTrainer at the same time. Both would
load and the hotkeys would fire twice. Use RokuMenu instead
of GONTrainer when you want the menu.

------------------------------------------------------------
PACKAGE CONTENTS
------------------------------------------------------------
Copy the CONTENTS of this folder into ue4ss\Mods.

  shared\ModMenu\ModMenu.lua     menu framework (v1.4.0)
  RokuMenu\enabled.txt           turns the mod on
  RokuMenu\Scripts\main.lua      menu and hotkeys
  RokuMenu\Scripts\core.lua      game reads and writes

You do NOT edit mods.txt. enabled.txt is what turns it on.

NumLock MUST be ON for the number-pad keys. If those keys
do nothing, tap NumLock and try again. The number row above
the letters is a different set of keys.

------------------------------------------------------------
FEATURES
------------------------------------------------------------
* Menu on Tab. Dock it from the header (left, right, top,
  bottom). That choice is remembered.
* Player cheats: god mode, infinite stamina, crouch.
* Difficulty tab, saved on this PC, no hotkeys. Not part of
  Keep cheats between loads. Roku damage is Normal, Half, or
  Quarter. Half gives back half the hit. Quarter leaves one
  quarter of it. God mode still blocks the hit completely.
  Apple count stays as it is. Look for "Damage hook installed"
  in UE4SS.log, then one line per Half or Quarter hit.
* Stamina 0.5x to 3x of your current bar. Stamina cubes still
  add 0.2 seconds each. Infinite Stamina fills that bar.
* Empty stamina penalty On keeps the tired speed at 150.
  Off matches current walk speed, including crouch.
* Sprint speed 0.8x to 1.2x of your current sprint. Cubes
  still add 2 speed each. Walk stays 240. Crouch pauses the
  sprint choice and uses 70% of the cube sprint, not both.
* Roku chase speed 0.7x to 1.1x of 480. Freeze still stops
  her, then puts the chosen speed back.
* Crouch lowers the view, cuts your speed to 70%, and
  shrinks Roku's head vision box to 10%.
* Roku: ghost, freeze, 5% slo-mo, max drunk, follow.
* Cowbell stays on the Cheats tab and is greyed out. GON 1.3
  uses the bell for the Cowmeat unlock, so this cheat does not
  press it.
* Spankable stays on. It is set again every 5 seconds so
  another spank can start after the animation finishes.
* Follow sets her approach distance very short and turns
  off the chase boxes and the close-range swat capsules, so
  she walks toward you without swinging or slapping.
* Item buttons show the hidden prop on her, then play the
  effect: apple, carrot, wine, beer, glowstick, flashlight.
  Default keys are 5 6 7 8 9 0 on the number row.
* Space is a stronger hop. It does nothing while sprinting.
  It also does nothing while noclip or freecam is on,
  because Space is up for those.
* Ghost and Follow are one or the other. Turning one on
  turns the other off.
* Ghost drops a chase once and leaves her senses off.
  Drunk and spank still work.
* Apples 65/66 and notes complete.
* 15 outfits. Cowmeat and Dark are at the end of the list.
  Bunny 1 includes the bunny bra. Sailor 1 uses the Sailor1 row.
* Camera: hide HUD, freecam, noclip. Hide HUD also hides
  the circles that appear over nearby items. WASD, Space up,
  X down. [ and ] change fly speed from 10% to 300% of walk speed.
* Noclip turns collision off while you fly. Turning it off in
  open air drops you. Turning it off inside a wall leaves it
  on and does not move you. Crouch is blocked while it is on.
* Bunny 1 and Bunny 2 no longer paint the bunny material
  over her eyes and teeth.
* Settings: mouse, music, and effects. Type a number.
  A pause applies it. Closing the menu saves it again.
  Music and effects use the game sound mix. 0 is mute, 1 is full.
* Graphics, under Settings. Each row is Low, Medium, High,
  Epic, or Cinematic and applies when you pick it. The rows
  follow the game if the Quality menu changes them.
  Force these on map load starts off and has no hotkey.
  It saves the rows and puts them back about 2 seconds
  after a map loads. The game settings screen can still
  overwrite them until that next map. Fog high/low still
  follows the overall Quality choice until the next map.
* Keep cheats between loads is on the Cheats tab. It has
  no hotkey and starts off. While it is on, cheats are saved
  when Roku unloads, turned off, then put back the next time
  a level Roku is found. That saved list is kept after you
  quit the game. Apples, notes, max drunk, and item events
  are not restored. Noclip and freecam come back on at the
  new spawn, not the old spot.
* Bindings tab: Assign, then press a key. Esc cancels.
  Tab cannot be reassigned. Hotkeys do nothing while the
  menu is open, so you can type numbers.

------------------------------------------------------------
CONTROLS (DEFAULTS)
------------------------------------------------------------
NumLock must be ON or the NUM keys will do nothing.

MENU:
[Tab]   - Open / close the menu

PLAYER:
[NUM 1] - God Mode
[NUM 2] - Infinite Stamina
[C]     - Crouch (10% vision box, 70% speed)
[Space] - Jump (not while sprinting)

ITEMS (number row, not the numpad):
[5] - Apple
[6] - Carrot
[7] - Wine
[8] - Beer
[9] - Glowstick
[0] - Flashlight

ROKU:
[NUM 3] - Ghost Mode
[NUM 0] - Freeze Roku
[NUM .] - Slo-Mo (5%)
[NUM 7] - Max Drunk
[NUM 8] - Force Spankable

OBJECTIVE:
[NUM 4] - Apples 65/66

OUTFITS:
[NUM 5] - Next outfit
[NUM 6] - Base outfit

CAMERA:
[NUM 9] - Hide HUD
[End]   - Freecam
[\]     - Noclip
[ key   - Fly slower
] key   - Fly faster

------------------------------------------------------------
OUTFIT LIST
------------------------------------------------------------
1. Base Roku (Top + Pants)
2. Shirt-Off Roku
3. Bottomless Roku
4. Bikini Roku
5. Source Roku
6. Bunny Roku (1)
7. Bunny Roku (2)
8. Sailor Roku (1)
9. Sailor Roku (2)
10. Shibari Roku
11. Uncensored Full Bare
12. Uncensored Shirtless
13. Uncensored Bottomless
14. Cowmeat Roku
15. Dark Roku

------------------------------------------------------------
INSTALLATION
------------------------------------------------------------
Two steps. UE4SS first, then drop this mod into Mods.

Stable UE4SS 3.0.1 from GitHub "latest" will NOT work on this
game (Unreal 5.7). Use Experimental.


STEP 1 — EXPERIMENTAL UE4SS
---------------------------
1. Steam: Library -> GON: God of Nothing -> gear / right-click
   -> Manage -> Browse local files. You will see GON.exe.
   That is the game root. Do not put UE4SS here.

2. Open:  Roku3 -> Binaries -> Win64
   You must see Roku3-Win64-Shipping.exe.

3. Download Experimental UE4SS (newest date on the page):
   https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest

   Use ONE of these (numbers change every build):
     UE4SS_v3.0.1-XXXX-g........zip      quiet player install
     zDEV-UE4SS_v3.0.1-XXXX-g........zip optional debug console

   Skip "Source code" zips. Skip old xinput zips.

4. Open the zip until you see dwmapi.dll and a ue4ss folder
   together. Copy BOTH into that Win64 folder, next to
   Roku3-Win64-Shipping.exe.

   Win64 should now look like:
     Roku3-Win64-Shipping.exe
     dwmapi.dll
     ue4ss\
       UE4SS.dll
       Mods\


STEP 2 — DROP ROKUMENU INTO MODS
--------------------------------
Copy the contents of this archive into:

  ...\GON God Of Nothing\Roku3\Binaries\Win64\ue4ss\Mods\

You should end up with:
  ...\ue4ss\Mods\shared\ModMenu\ModMenu.lua
  ...\ue4ss\Mods\RokuMenu\enabled.txt
  ...\ue4ss\Mods\RokuMenu\Scripts\main.lua
  ...\ue4ss\Mods\RokuMenu\Scripts\core.lua

If GONTrainer is installed, rename or delete:
  ...\ue4ss\Mods\GONTrainer\enabled.txt

Do not copy a second "RokuMenu_v0.5" folder into Mods.


WRONG (will not load)
---------------------
  Next to GON.exe
  ...\Win64\RokuMenu\
  ...\ue4ss\Mods\RokuMenu\RokuMenu\
  ...\ue4ss\Mods\RokuMenu_v0.5\...


LAUNCH
------
Start the game from Steam. Tab opens the menu in the main
menu and in a level.

If nothing happens, open:
  ...\Roku3\Binaries\Win64\ue4ss\UE4SS.log

  No log file          = UE4SS is not loading
  Log, no RokuMenu     = the folder is not inside ue4ss\Mods\
  You want this line   = Mod 'RokuMenu' has enabled.txt, starting mod.
  Keys do nothing      = NumLock is off, or the menu is open

LINUX / STEAM DECK (PROTON)
---------------------------
If UE4SS fails to start under Proton, add this to the game's
Steam Launch Options:

  WINEDLLOVERRIDES="dwmapi=n,b" %command%


------------------------------------------------------------
UNINSTALLATION
------------------------------------------------------------
Delete:
  ...\ue4ss\Mods\RokuMenu\
  ...\ue4ss\Mods\shared\ModMenu\

Only delete shared\ModMenu if no other mod is using it.

------------------------------------------------------------
CHANGELOG
------------------------------------------------------------
v0.5:
* Tabs size to their names so they no longer crowd each other.
* Menu is a bit wider.
* Music and effects apply through the game sound mix.
  Music no longer depends on a settings object that was not loaded.
* Graphics section on Settings. Per-group quality, applied live.
* Graphics rows follow the game Quality menu and update
  when that menu changes them.
* Force these on map load. Off by default, no hotkey.
  Saves the graphics rows and puts them back after a map loads.
* Hide HUD also hides the item circles. Turning it off
  fades those circles back in. It does not set their
  visibility, which crashed the game.
* Freecam starts where the player is looking. It no longer
  opens at the world origin.
* Freecam turns Ghost on so Roku does not chase. Turning
  freecam off turns that Ghost off. A Ghost that was already
  on stays on. Ghost cannot be turned off during freecam.

v0.4 (GON 1.3):
* Released. Same build as the v0.4_b playtest, beta tag removed.
* Built for the v1.3 outfits and the live hit trace.
* Damage hook retries until the player blueprint is loaded.
* Roku damage is Normal, Half, or Quarter. Quarter replaced Off.
* Follow also turns off the close-range swat capsules.
* Stamina and sprint scales sit on top of stamina cubes.
* Follow restores the v1.3 distances.
* Cowmeat and Dark outfits. Sailor 1 uses the Sailor1 row.
* Menu panel is 15% wider.
* Stock difficulty rows do not write the game. A speed is
  written only when the number actually changed.

v0.4 beta:
* Difficulty tab. Roku damage (Normal / Half / Off) is the
  beta piece. Stamina, empty-stamina penalty, sprint speed,
  and chase speed are in the same build for testing.
* Each hit logs one line in UE4SS.log when damage is Half or Off.

v0.3:
* Keep cheats between loads. Checkbox on the Cheats tab, no hotkey.
  Off until you turn it on. Cheats are saved when Roku unloads,
  turned off, then put back on the next level.
* That saved list is kept after you quit and start the game again.
* Cowbell is greyed out. GON 1.26 removed it for performance.
  The row stays for when that feature comes back.

v0.2.1:
* Added pdf install guide.

v0.2:
* Bunny eyes and teeth keep their own materials.
* Cowbell toggle.
* Item event buttons show the hidden prop, then the effect.
* Spankable holds and refreshes every 5 seconds.
* Follow: short approach distance, attack boxes off.
* Noclip is back. Exit in open air only. Inside a wall it stays on.
* Item keys default to 5 6 7 8 9 0. Space jumps. Not while sprinting.

v0.1:
* First menu release. Replaces GONTrainer when you want a panel.
* Cheats, 13 outfits, ghost, crouch, freecam, hide HUD.
* Mouse, music, and effects saved when the menu closes.
* Bindings tab. NumLock required for NUM keys.
* Noclip is not included. It was crashing inside level geometry.
