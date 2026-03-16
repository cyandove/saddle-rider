# Avatar-to-Avatar Riding System
### Magnetic Follower Architecture — Second Life

---

## Files

| File | Goes in | Worn by |
|---|---|---|
| `mount_transmitter.lsl` | Saddle prim | **Mount** |
| `rider_follower.lsl` | Pose prim | **Rider** |

---

## Quick Start

### Step 1 — Mount sets up the Saddle
1. Create a small prim (box or sphere, can be invisible/transparent).
2. Drop `mount_transmitter.lsl` into the prim's Contents.
3. Attach the prim to a comfortable point (Spine, Chest, or Pelvis).

The script automatically sets the prim to **Phantom** on startup.

### Step 2 — Rider sets up the Follower
1. Create a small prim.
2. (Optional) Drop your riding animation, named exactly `riding_pose`, into the prim's Contents.
3. Drop `rider_follower.lsl` into the prim's Contents.
4. Attach the prim to **Avatar Center**.

The script automatically sets the prim to **Phantom** on startup.

### Step 3 — Pair
1. **Mount touches her saddle.** This sends a pairing signal on the discovery channel.
2. **Rider sees a dialog**: *"[MountName]'s saddle is nearby. Pair and start following?"*
3. Rider clicks **Yes**.
4. Rider may be prompted to grant **animation permissions** — accept.

That's it. No channel numbers to share or paste.

> The pairing dialog also appears automatically every 10 seconds while the saddle is worn,
> so the rider doesn't need to do anything if they attach their prim after the mount is already wearing hers.

### Step 4 — Adjust offset (optional)
Touch the Follower prim while stopped to open the offset adjustment menu:

```
[Step ][Reset][Done ]
[Y+   ][Z-   ][Z+   ]
[X-   ][X+   ][Y-   ]
```

- **X** moves the rider forward/back, **Y** left/right, **Z** up/down
- **Step** cycles the increment: 0.05 m → 0.10 m → 0.25 m → 0.05 m
- **Reset** returns the offset to `<0, 0, 0.8>`
- **Done** saves the offset and starts following (if paired)

### Step 5 — Dismount
- Rider touches their Follower prim to stop tracking (offset menu opens automatically), **or**
- Rider detaches the prim (the script stops all animations and movement cleanly).

### Re-pairing
If the mount re-attaches her saddle, touch the saddle again to send a fresh pairing signal. Clicking **Done** in the offset menu will restart following with the current paired channel.

---

## Configuration

All tuning values are at the top of `rider_follower.lsl`:

| Variable | Default | How to change |
|---|---|---|
| `gSaddleOffset` | `<0,0,0.8>` | Touch menu (X/Y/Z buttons), or edit the script |
| `FOLLOW_TAU` | `0.1` | Edit script — lower = snappier tracking, higher = smoother/floatier |
| `ROT_STRENGTH` | `0.5` | Edit script — how quickly the rider rotates to match mount's heading |
| `ROT_DAMPING` | `0.1` | Edit script — reduces spinning overshoot |
| `RIDING_ANIM` | `"riding_pose"` | Edit script — name of animation in prim inventory; `""` to skip |

### Tuning the saddle offset
The offset is in the mount's **local space**, rotated into world space before applying:
- `X` = forward/back along mount's body
- `Y` = left/right
- `Z` = up/down (height above mount's origin)

The easiest way to tune it is in-world: start following, stop, open the touch menu, and nudge X/Y/Z until the rider sits correctly. The default `<0, 0, 0.8>` places the rider 0.8 m above the mount's origin — adjust Z first, then X/Y for fore-aft and lateral position.

---

## Known Limitations

### Rubber-banding
At high speed or sharp turns, the rider will lag 1–3 frames behind the mount. This is inherent to `llMoveToTarget`. Mitigations:
- Lower `FOLLOW_TAU` (try `0.05`) for faster mounts.
- Increase the mount timer frequency (`llSetTimerEvent(0.05)`) — note this doubles script load.

### Sim Crossings
Both avatars cross region borders independently under their own movement. The rider will briefly snap/rubber-band during the crossing, then automatically re-acquire once both are in the new region. The mount should slow to a walk at sim borders.

### Multiple Mounts on the Same Region
Each saddle derives its channel from the **mount owner's avatar key**, so two different mount/rider pairs are always on different channels. If two mounts touch their saddles at the same moment, each rider's dialog will show the correct mount's name — just click the one you want.

### The Rider's AO
The follower suppresses SL's default `sit` and `stand` animations. The rider's own AO (if they wear one) will continue to run unless it detects the `riding_pose` animation and overrides it — which is the correct behaviour for a well-configured AO.

### Detaching Without Stopping
If the rider's attachment is forcibly removed without the script running (e.g. SL crash), the `riding_pose` animation may ghost. The rider can clear ghost animations by opening **Animations** in their viewer and stopping them manually, or by briefly equipping and removing the attachment again.

---

## How It Works

### Automatic Pairing (Discovery Channel)
Both scripts share a fixed private channel (`-7654321`) used only for pairing. When the mount touches her saddle (or every 10 seconds automatically), the transmitter broadcasts:

```
SADDLE_PAIR|<mount_avatar_key>|<mount_name>|<data_channel>
```

The rider's script hears this, shows an `llDialog` confirmation, and on **Yes** switches its listener to the data channel and begins following.

### Stable Channel Derivation
The data channel is derived from the **mount owner's avatar key** (not the object key):

```lsl
integer channel = -(integer)("0x" + llGetSubString((string)ownerKey, 0, 6));
```

Avatar keys never change, so the channel is identical every session. The rider only needs to re-pair if switching to a different mount.

### Position Tracking
Once paired, the mount transmitter broadcasts `<pos>|<rot>` at 10 Hz. The rider script calls `llMoveToTarget` and `llRotLookAt` each time a packet arrives, keeping the rider physically locked to the mount's back.
