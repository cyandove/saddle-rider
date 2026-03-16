// -- Rider Follower (Pose Attachment) ------------------------------------
// Worn by: The RIDER avatar
// Purpose: Listens for the mount's position/rotation broadcast and uses
//          llMoveToTarget to physically place the rider on the mount's
//          back. Suppresses SL's default sit pose and plays a custom
//          riding animation instead.
//
// Setup:
//   1. Drop this script into the rider pose prim.
//   2. Drop your riding animation (named "riding_pose") into the prim inventory.
//      If you have no custom animation, the script still works -- it will
//      just suppress the default sit pose and leave the rider in their AO.
//   3. Set the prim to Phantom.
//   4. Set gChannel below to match the mount's channel (or use notecard).
//   5. Adjust SADDLE_OFFSET so the rider sits at the right height/position.
// ------------------------------------------------------------------------

// ---- CONFIGURATION -----------------------------------------------------

// Channel must match the mount's derived channel.
// Method A (simplest): mount touches her saddle, tells you the number,
//                      paste it here.
// Method B (automatic): store the mount's object UUID in a notecard named
//                       "mount_key" and un-comment the notecard loader below.
integer gChannel = -88881234; // <-- Replace with your mount's channel

// Offset in LOCAL saddle space: X=forward, Y=left, Z=up.
// Rotated into world space before applying, so it always tracks correctly.
vector SADDLE_OFFSET = <0.0, 0.0, 0.8>;

// llMoveToTarget tau. Lower = snappier tracking but more jitter.
// Recommended range: 0.05 (snappy) to 0.3 (smooth/floaty).
float FOLLOW_TAU = 0.1;

// llRotLookAt strength and damping.
float ROT_STRENGTH = 0.5;
float ROT_DAMPING  = 0.1;

// Name of the riding animation in this prim's inventory.
// Set to "" to skip custom animation (rider AO plays instead).
string RIDING_ANIM = "riding_pose";

// ---- ANIMATION LIST TO SUPPRESS ----------------------------------------
// SL may inject any of these when the rider's avatar state changes.
list SUPPRESS_ANIMS = ["sit", "sit_generic", "sit_to_stand", "stand",
                       "stand_1", "stand_2", "stand_3", "stand_4"];

// ---- GLOBALS -----------------------------------------------------------
integer gListener  = -1;
integer gRiding    = FALSE;
integer gHasPerms  = FALSE;

// ---- HELPERS -----------------------------------------------------------

startRiding()
{
    // Remove old listener if any, then open a fresh one.
    if (gListener != -1) llListenRemove(gListener);
    gListener = llListen(gChannel, "", NULL_KEY, "");
    gRiding   = TRUE;
    llOwnerSay("[Rider] Following on channel " + (string)gChannel
               + ". Touch to stop.");

    // Request animation permissions (auto-granted for attachments to owner).
    llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
}

stopRiding()
{
    if (gListener != -1)
    {
        llListenRemove(gListener);
        gListener = -1;
    }
    llStopMoveToTarget();
    gRiding = FALSE;

    // Stop our custom animation cleanly.
    if (gHasPerms && RIDING_ANIM != "")
        llStopAnimation(RIDING_ANIM);

    llOwnerSay("[Rider] Follower stopped. Touch to resume.");
}

suppressDefaultAnims()
{
    integer i;
    for (i = 0; i < llGetListLength(SUPPRESS_ANIMS); i++)
        llStopAnimation(llList2String(SUPPRESS_ANIMS, i));
}

// ---- NOTECARD CHANNEL LOADER (optional) --------------------------------
// If you want automatic channel setup, store the mount's object key in a
// notecard named "mount_key" (one line, just the UUID). Un-comment this
// block and the dataserver event below.
//
// key gNCQuery;
// loadMountKey()
// {
//     if (llGetInventoryType("mount_key") != INVENTORY_NOTECARD)
//     {
//         llOwnerSay("[Rider] No 'mount_key' notecard found. Using hardcoded channel.");
//         startRiding();
//         return;
//     }
//     gNCQuery = llGetNotecardLine("mount_key", 0);
// }

// ========================================================================
default
{
    state_entry()
    {
        llOwnerSay("[Rider] Follower attachment ready. Touch to start/stop.");
        // Auto-start on rez/attach. Remove this line if you prefer manual start.
        startRiding();
    }

    run_time_permissions(integer perms)
    {
        if (perms & PERMISSION_TRIGGER_ANIMATION)
        {
            gHasPerms = TRUE;
            suppressDefaultAnims();

            if (RIDING_ANIM != "" && llGetInventoryType(RIDING_ANIM) == INVENTORY_ANIMATION)
                llStartAnimation(RIDING_ANIM);
            else if (RIDING_ANIM != "")
                llOwnerSay("[Rider] Warning: animation '" + RIDING_ANIM
                           + "' not found in inventory. Add it or set RIDING_ANIM to \"\".");
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        // Parse "pos|rot" broadcast from mount.
        list     data     = llParseString2List(msg, ["|"], []);
        if (llGetListLength(data) < 2) return; // Malformed packet, ignore.

        vector   mountPos = (vector)  llList2String(data, 0);
        rotation mountRot = (rotation)llList2String(data, 1);

        // Rotate the saddle offset into world space so it always points
        // "up from the mount's back" regardless of her heading.
        vector worldOffset = SADDLE_OFFSET * mountRot;

        llMoveToTarget(mountPos + worldOffset, FOLLOW_TAU);
        llRotLookAt(mountRot, ROT_STRENGTH, ROT_DAMPING);
    }

    // Touch to toggle follow on/off.
    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (gRiding) stopRiding();
        else         startRiding();
    }

    // Stop cleanly on detach; re-init on re-attach.
    attach(key id)
    {
        if (id == NULL_KEY)
        {
            // Detaching -- stop everything to prevent ghost animations/movement.
            stopRiding();
        }
        else
        {
            // Re-attaching -- reset and auto-start.
            gHasPerms = FALSE;
            startRiding();
        }
    }

    // Re-request permissions after owner change.
    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    // ---- Optional notecard dataserver handler (un-comment to enable) ---
    // dataserver(key query_id, string data)
    // {
    //     if (query_id != gNCQuery) return;
    //     if (data == EOF || data == "")
    //     {
    //         llOwnerSay("[Rider] 'mount_key' notecard is empty.");
    //         return;
    //     }
    //     key mountKey = (key)llStringTrim(data, STRING_TRIM);
    //     if (mountKey == NULL_KEY)
    //     {
    //         llOwnerSay("[Rider] 'mount_key' notecard contains an invalid UUID.");
    //         return;
    //     }
    //     gChannel = -(integer)("0x" + llGetSubString((string)mountKey, 0, 6));
    //     llOwnerSay("[Rider] Channel set from notecard: " + (string)gChannel);
    //     startRiding();
    // }
}
