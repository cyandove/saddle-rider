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
//      If you have no custom animation, the script still works.
//   3. Have the mount touch her saddle; a pairing dialog will appear on
//      your screen. Click Yes to start following.
//   4. Touch your prim at any time to open the offset adjustment menu.
//      Adjustments take effect immediately while riding and are saved
//      per mount, so your preferred position is restored automatically
//      each time you pair with the same mount.
//   (Phantom is set automatically by the script.)
// ------------------------------------------------------------------------

// ---- CONFIGURATION -----------------------------------------------------

// Saddle offset in LOCAL mount space: X=forward, Y=left, Z=up.
// Loaded from linkset data on pairing; adjustable at runtime via touch menu.
vector gSaddleOffset = <0.0, 0.0, 0.8>;

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
list SUPPRESS_ANIMS = ["sit", "sit_generic", "sit_to_stand", "stand",
                       "stand_1", "stand_2", "stand_3", "stand_4"];

// ---- GLOBALS -----------------------------------------------------------
integer gChannel              = 0;        // 0 = not yet paired
key     gMountOwner           = NULL_KEY; // Avatar key of the current mount
integer gListener             = -1;       // Data channel listener handle
integer gDiscoveryListener    = -1;       // Discovery channel listener handle
integer gDialogChannel;                   // Private channel for all llDialog responses
integer gDialogListener       = -1;       // Dialog/menu listener handle
integer gRiding               = FALSE;
integer gHasPerms             = FALSE;
integer gAnimPlaying          = FALSE;
integer gPendingChannel       = 0;        // Channel offered by a nearby saddle
key     gPendingMountOwner    = NULL_KEY; // Mount owner key from pending pairing offer
integer gMenuOpen             = FALSE;    // TRUE while offset menu is showing
float   gStep                 = 0.10;     // Adjustment increment; cycles via Step button

// Offset menu buttons (displayed bottom-to-top, 3 per row):
// Row 3 (top): [Step ][Reset][Done ]
// Row 2:       [X+   ][Y+   ][Z+   ]
// Row 1 (bot): [X-   ][Y-   ][Z-   ]
list MENU_BUTTONS = ["X-", "Y-", "Z-", "X+", "Y+", "Z+", "Step", "Reset", "Done"];

// ---- HELPERS -----------------------------------------------------------

// Format a float to 2 decimal places for compact display.
string fmt(float f)
{
    string s = (string)f;
    integer dot = llSubStringIndex(s, ".");
    if (dot == -1) return s;
    return llGetSubString(s, 0, dot + 2);
}

// Linkset data key for a given mount owner's offset.
string lsdKey(key mountOwner)
{
    return "offset_" + (string)mountOwner;
}

suppressDefaultAnims()
{
    integer i;
    for (i = 0; i < llGetListLength(SUPPRESS_ANIMS); i++)
        llStopAnimation(llList2String(SUPPRESS_ANIMS, i));
}

// Cycle step size: 0.05 -> 0.10 -> 0.25 -> 0.05
cycleStep()
{
    if      (gStep < 0.09) gStep = 0.10;
    else if (gStep < 0.19) gStep = 0.25;
    else                   gStep = 0.05;
}

string offsetMenuMsg()
{
    string hint;
    if (gRiding)            hint = "Changes apply live. Done = close menu.";
    else if (gChannel != 0) hint = "Done = close + start following";
    else                    hint = "Done = close";
    return "Saddle Offset  (step: " + fmt(gStep) + " m)\n"
         + "X " + fmt(gSaddleOffset.x)
         + "   Y " + fmt(gSaddleOffset.y)
         + "   Z " + fmt(gSaddleOffset.z)
         + "\n\nX = fwd/back   Y = left/right   Z = up/down\n"
         + hint;
}

openOffsetMenu()
{
    if (gDialogListener != -1) llListenRemove(gDialogListener);
    gDialogListener = llListen(gDialogChannel, "", llGetOwner(), "");
    gMenuOpen = TRUE;
    llSetTimerEvent(60.0); // Auto-close after 60 s of inactivity
    llDialog(llGetOwner(), offsetMenuMsg(), MENU_BUTTONS, gDialogChannel);
}

startRiding()
{
    if (gListener != -1) llListenRemove(gListener);
    gListener = llListen(gChannel, "", NULL_KEY, "");
    gRiding   = TRUE;

    // Close discovery listener while riding to free a listener slot.
    if (gDiscoveryListener != -1) { llListenRemove(gDiscoveryListener); gDiscoveryListener = -1; }

    llOwnerSay("[Rider] Following on channel " + (string)gChannel + ". Touch to adjust offset.");
    llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
}

stopRiding()
{
    if (gListener != -1) { llListenRemove(gListener); gListener = -1; }
    llStopMoveToTarget();
    gRiding = FALSE;

    if (gAnimPlaying) { llStopAnimation(RIDING_ANIM); gAnimPlaying = FALSE; }

    // Reopen discovery listener so a new saddle can re-pair.
    if (gDiscoveryListener == -1)
        gDiscoveryListener = llListen(DISCOVERY_CHANNEL, "", NULL_KEY, "");
}

handleMenuButton(string btn)
{
    if (btn == "Done")
    {
        llListenRemove(gDialogListener);
        gDialogListener = -1;
        gMenuOpen = FALSE;
        llSetTimerEvent(0.0);
        if (!gRiding && gChannel != 0) startRiding();
        else if (!gRiding) llOwnerSay("[Rider] Offset saved. Pair with a saddle to start following.");
        return;
    }

    if      (btn == "Reset") gSaddleOffset = <0.0, 0.0, 0.8>;
    else if (btn == "Step")  cycleStep();
    else if (btn == "X-")    gSaddleOffset.x -= gStep;
    else if (btn == "X+")    gSaddleOffset.x += gStep;
    else if (btn == "Y-")    gSaddleOffset.y -= gStep;
    else if (btn == "Y+")    gSaddleOffset.y += gStep;
    else if (btn == "Z-")    gSaddleOffset.z -= gStep;
    else if (btn == "Z+")    gSaddleOffset.z += gStep;

    // Persist immediately, keyed to this mount, so it survives resets and relogs.
    if (gMountOwner != NULL_KEY)
        llLinksetDataWrite(lsdKey(gMountOwner), (string)gSaddleOffset);

    // Refresh the dialog; reset inactivity timer.
    llSetTimerEvent(60.0);
    llDialog(llGetOwner(), offsetMenuMsg(), MENU_BUTTONS, gDialogChannel);
}

// ========================================================================
default
{
    state_entry()
    {
        llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_PHANTOM, TRUE]);
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
            {
                llStartAnimation(RIDING_ANIM);
                gAnimPlaying = TRUE;
            }
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

            gPendingMountOwner = (key)llList2String(parts, 1);
            string mountName   = llList2String(parts, 2);
            gPendingChannel    = (integer)llList2String(parts, 3);

            if (gDialogListener != -1) llListenRemove(gDialogListener);
            gDialogListener = llListen(gDialogChannel, "", llGetOwner(), "");
            gMenuOpen = FALSE;
            llDialog(llGetOwner(),
                "\n" + mountName + "'s saddle is nearby.\nPair and start following?",
                ["Yes", "No"],
                gDialogChannel);
            llSetTimerEvent(30.0);
            return;
        }

        // -- Dialog / menu response --
        if (channel == gDialogChannel)
        {
            if (gMenuOpen)
            {
                handleMenuButton(msg);
            }
            else
            {
                // Pairing confirmation response.
                llListenRemove(gDialogListener);
                gDialogListener = -1;
                llSetTimerEvent(0.0);

                if (msg == "Yes")
                {
                    gChannel    = gPendingChannel;
                    gMountOwner = gPendingMountOwner;

                    // Load the saved offset for this mount, if any.
                    string stored = llLinksetDataRead(lsdKey(gMountOwner));
                    if (stored != "") gSaddleOffset = (vector)stored;

                    llOwnerSay("[Rider] Paired! Channel: " + (string)gChannel);
                    startRiding();
                }
                else
                {
                    llOwnerSay("[Rider] Pairing declined.");
                    gPendingChannel    = 0;
                    gPendingMountOwner = NULL_KEY;
                }
            }
            return;
        }

        // -- Riding data: pos/rot broadcast from mount --
        if (channel == gChannel)
        {
            list     data     = llParseString2List(msg, ["|"], []);
            if (llGetListLength(data) < 2) return;

            vector   mountPos = (vector)  llList2String(data, 0);
            rotation mountRot = (rotation)llList2String(data, 1);

            vector worldOffset = gSaddleOffset * mountRot;

            llMoveToTarget(mountPos + worldOffset, FOLLOW_TAU);
            llRotLookAt(mountRot, ROT_STRENGTH, ROT_DAMPING);
        }
    }

    // Touch at any time to open the offset menu.
    // Does not stop riding -- adjustments apply live while following.
    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        openOffsetMenu();
    }

    // Dialog or menu timed out -- clean up.
    timer()
    {
        if (gDialogListener != -1)
        {
            llListenRemove(gDialogListener);
            gDialogListener = -1;
        }
        llSetTimerEvent(0.0);

        if (gMenuOpen)
        {
            gMenuOpen = FALSE;
            llOwnerSay("[Rider] Offset menu closed (timeout).");
        }
        else
        {
            gPendingChannel    = 0;
            gPendingMountOwner = NULL_KEY;
            llOwnerSay("[Rider] Pairing dialog timed out.");
        }
    }

    // Stop cleanly on detach; re-init on re-attach.
    attach(key id)
    {
        if (id == NULL_KEY)
        {
            stopRiding();
            if (gDialogListener != -1) { llListenRemove(gDialogListener); gDialogListener = -1; }
            gMenuOpen = FALSE;
            llSetTimerEvent(0.0);
        }
        else
        {
            gHasPerms          = FALSE;
            gAnimPlaying       = FALSE;
            gChannel           = 0;
            gMountOwner        = NULL_KEY;
            gMenuOpen          = FALSE;
            gDialogChannel     = -(integer)("0x" + llGetSubString((string)llGetKey(), 0, 6));
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
