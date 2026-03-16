// -- Rider Follower (Pose Attachment) ------------------------------------
// Worn by: The RIDER avatar
// Purpose: Listens for the mount's position/rotation broadcast and uses
//          llMoveToTarget to physically place the rider on the mount's
//          back. Pairs automatically -- when a saddle is nearby, a dialog
//          appears asking the rider to confirm the connection. No channel
//          number needs to be copy-pasted.
//
// Setup:
//   1. Drop this script into the rider pose prim.
//   2. Drop your riding animation (named "riding_pose") into the prim inventory.
//      If you have no custom animation, the script still works -- it will
//      just suppress the default sit pose and leave the rider in their AO.
//   3. Adjust SADDLE_OFFSET so the rider sits at the right height/position.
//   4. Have the mount touch her saddle; a pairing dialog will appear on
//      your screen. Click Yes to start following.
//   (Phantom is set automatically by the script.)
// ------------------------------------------------------------------------

// ---- CONFIGURATION -----------------------------------------------------

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

// Fixed discovery channel -- must match DISCOVERY_CHANNEL in mount_transmitter.lsl.
integer DISCOVERY_CHANNEL = -7654321;

// ---- ANIMATION LIST TO SUPPRESS ----------------------------------------
// SL may inject any of these when the rider's avatar state changes.
list SUPPRESS_ANIMS = ["sit", "sit_generic", "sit_to_stand", "stand",
                       "stand_1", "stand_2", "stand_3", "stand_4"];

// ---- GLOBALS -----------------------------------------------------------
integer gChannel           = 0;  // 0 = not yet paired
integer gListener          = -1; // Data channel listener handle
integer gDiscoveryListener = -1; // Discovery channel listener handle
integer gDialogChannel;          // Private channel for llDialog responses
integer gDialogListener    = -1; // Dialog response listener handle
integer gRiding            = FALSE;
integer gHasPerms          = FALSE;
integer gPendingChannel    = 0;  // Channel offered by a nearby saddle

// ---- HELPERS -----------------------------------------------------------

startRiding()
{
    if (gListener != -1) llListenRemove(gListener);
    gListener = llListen(gChannel, "", NULL_KEY, "");
    gRiding   = TRUE;

    // While riding, close discovery and dialog listeners to save resources.
    if (gDiscoveryListener != -1) { llListenRemove(gDiscoveryListener); gDiscoveryListener = -1; }
    if (gDialogListener    != -1) { llListenRemove(gDialogListener);    gDialogListener    = -1; }

    llOwnerSay("[Rider] Following on channel " + (string)gChannel + ". Touch to stop.");
    llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
}

stopRiding()
{
    if (gListener != -1) { llListenRemove(gListener); gListener = -1; }
    llStopMoveToTarget();
    gRiding = FALSE;

    if (gHasPerms && RIDING_ANIM != "") llStopAnimation(RIDING_ANIM);

    // Reopen discovery listener so a new (or same) saddle can re-pair.
    if (gDiscoveryListener == -1)
        gDiscoveryListener = llListen(DISCOVERY_CHANNEL, "", NULL_KEY, "");

    llOwnerSay("[Rider] Follower stopped. Listening for nearby saddles...");
}

suppressDefaultAnims()
{
    integer i;
    for (i = 0; i < llGetListLength(SUPPRESS_ANIMS); i++)
        llStopAnimation(llList2String(SUPPRESS_ANIMS, i));
}

// ========================================================================
default
{
    state_entry()
    {
        llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_PHANTOM, TRUE]);
        // Private dialog channel derived from this prim's key.
        gDialogChannel     = -(integer)("0x" + llGetSubString((string)llGetKey(), 0, 6));
        gDiscoveryListener = llListen(DISCOVERY_CHANNEL, "", NULL_KEY, "");
        llOwnerSay("[Rider] Ready. Have the mount touch her saddle to send a pairing signal.");
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
        // -- Discovery: incoming saddle pairing offer --
        if (channel == DISCOVERY_CHANNEL)
        {
            list parts = llParseString2List(msg, ["|"], []);
            if (llList2String(parts, 0) != "SADDLE_PAIR") return;
            if (llGetListLength(parts) < 4) return;

            gPendingChannel = (integer)llList2String(parts, 3);
            string mountName = llList2String(parts, 2);

            // Show pairing confirmation dialog to rider.
            if (gDialogListener != -1) llListenRemove(gDialogListener);
            gDialogListener = llListen(gDialogChannel, "", llGetOwner(), "");
            llDialog(llGetOwner(),
                "\n" + mountName + "'s saddle is nearby.\nPair and start following?",
                ["Yes", "No"],
                gDialogChannel);
            llSetTimerEvent(30.0); // Expire dialog after 30 seconds
            return;
        }

        // -- Dialog response --
        if (channel == gDialogChannel)
        {
            llListenRemove(gDialogListener);
            gDialogListener = -1;
            llSetTimerEvent(0.0);

            if (msg == "Yes")
            {
                gChannel = gPendingChannel;
                llOwnerSay("[Rider] Paired! Channel: " + (string)gChannel);
                startRiding();
            }
            else
            {
                llOwnerSay("[Rider] Pairing declined.");
                gPendingChannel = 0;
            }
            return;
        }

        // -- Riding data: pos/rot broadcast from mount --
        if (channel == gChannel)
        {
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
    }

    // Touch to toggle follow on/off.
    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (gRiding)          stopRiding();
        else if (gChannel != 0) startRiding();
        else llOwnerSay("[Rider] Not paired yet. Have the mount touch her saddle.");
    }

    // Dialog timed out -- clean up.
    timer()
    {
        if (gDialogListener != -1)
        {
            llListenRemove(gDialogListener);
            gDialogListener = -1;
            gPendingChannel = 0;
        }
        llSetTimerEvent(0.0);
        llOwnerSay("[Rider] Pairing dialog timed out.");
    }

    // Stop cleanly on detach; re-init on re-attach.
    attach(key id)
    {
        if (id == NULL_KEY)
        {
            stopRiding();
        }
        else
        {
            // Reset state on re-attach.
            gHasPerms = FALSE;
            gChannel  = 0;
            gDialogChannel = -(integer)("0x" + llGetSubString((string)llGetKey(), 0, 6));
            if (gDiscoveryListener != -1) { llListenRemove(gDiscoveryListener); gDiscoveryListener = -1; }
            gDiscoveryListener = llListen(DISCOVERY_CHANNEL, "", NULL_KEY, "");
            llOwnerSay("[Rider] Re-attached. Have the mount touch her saddle to pair.");
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }
}
