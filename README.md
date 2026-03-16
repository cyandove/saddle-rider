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
2. In **Edit > Object tab**, tick **Phantom**.
3. Drop `mount_transmitter.lsl` into the prim's Contents.
4. Attach the prim to a comfortable point (Spine, Chest, or Pelvis).
5. **Touch the saddle** — it will say your channel number in local chat (owner-only). Note it down.

### Step 2 — Rider sets up the Follower
1. Create a small prim. Set it to **Phantom**.
2. Open `rider_follower.lsl` and replace the channel on this line with the number from Step 1:
   ```lsl
   integer gChannel = -88881234; // <-- paste mount's channel here
   ```
3. (Optional) Drop your riding animation, named exactly `riding_pose`, into the prim's Contents.
4. Drop the edited script into the prim's Contents.
5. Attach the prim to **Avatar Center**.

### Step 3 — Mount up
1. Mount stands still.
2. Rider touches their Follower prim → it starts tracking.
3. Rider may be prompted to grant **animation permissions** — accept.
4. Rider is pulled to the mount's back. Mount can now walk, run, and use her AO normally.

### Step 4 — Dismount
- Rider touches their Follower prim again to stop tracking, **or**
- Rider detaches the prim (the script stops all animations and movement cleanly).

---

## Configuration

All tuning values are at the top of `rider_follower.lsl`:

| Variable | Default | Effect |
|---|---|---|
| `gChannel` | `-88881234` | Must match mount's broadcast channel |
| `SADDLE_OFFSET` | `<0,0,0.8>` | Position of rider relative to mount's origin (metres, local space) |
| `FOLLOW_TAU` | `0.1` | `llMoveToTarget` responsiveness. Lower = snappier, higher = smoother |
| `ROT_STRENGTH` | `0.5` | How quickly the rider rotates to match the mount's heading |
| `ROT_DAMPING` | `0.1` | Rotation damping — reduces spinning overshoot |
| `RIDING_ANIM` | `"riding_pose"` | Name of the animation in prim inventory. Set to `""` to skip |

### Tuning SADDLE_OFFSET
The offset is in the mount's **local space**, rotated into world space before applying:
- `X` = forward/back along mount's body
- `Y` = left/right
- `Z` = up/down (height above mount's origin)

Start with `<0.0, 0.0, 0.8>` and adjust Z until the rider sits at saddle height. If the mount's origin is at her waist, `0.8` places the rider roughly at her shoulders — tune to taste.

---

## Automatic Channel Setup (No Manual Pasting)

Instead of copy-pasting a channel number, you can automate it with a notecard:

1. The mount creates a plain-text notecard containing **one line**: her saddle prim's UUID  
   (found in Edit > General tab > "Key" field).
2. Drop the notecard, named exactly `mount_key`, into the Rider prim's Contents.
3. In `rider_follower.lsl`, un-comment the three blocks marked `// ---- Optional`.

The rider script will read the UUID, derive the channel with the same formula the mount uses, and connect automatically.

---

## Known Limitations

### Rubber-banding
At high speed or sharp turns, the rider will lag 1–3 frames behind the mount. This is inherent to `llMoveToTarget`. Mitigations:
- Lower `FOLLOW_TAU` (try `0.05`) for faster mounts.
- Increase the mount timer frequency (`llSetTimerEvent(0.05)`) — note this doubles script load.

### Sim Crossings
Both avatars cross region borders independently under their own movement. The rider will briefly snap/rubber-band during the crossing, then automatically re-acquire once both are in the new region. The mount should slow to a walk at sim borders.

### Two Pairs on the Same Region
Each saddle derives its channel from its own object UUID, so two different mount/rider pairs will always be on different channels. No configuration needed.

### The Rider's AO
The follower suppresses SL's default `sit` and `stand` animations. The rider's own AO (if they wear one) will continue to run unless it detects the `riding_pose` animation and overrides it — which is the correct behaviour for a well-configured AO.

### Detaching Without Stopping
If the rider's attachment is forcibly removed without the script running (e.g. SL crash), the `riding_pose` animation may ghost. The rider can clear ghost animations by opening **Animations** in their viewer and stopping them manually, or by briefly equipping and removing the attachment again.

---

## How the Channel Derivation Works

Both scripts use the same formula so they always agree:

```lsl
integer channel = -(integer)("0x" + llGetSubString((string)objectKey, 0, 6));
```

This takes the first 7 hex characters of the UUID, converts them to a positive integer, and negates it. The result is a large negative channel number that is unique per object and consistent across sessions (the UUID never changes for a no-copy object).
