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
//   4. Touch your prim while stopped to open the offset adjustment menu.
//   (Phantom is set automatically by the script.)
// ------------------------------------------------------------------------

// ---- CONFIGURATION -----------------------------------------------------

// Saddle offset in LOCAL mount space: X=forward, Y=left, Z=up.
// Adjustable at runtime via the touch menu -- no script edit needed.
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
integer gChannel           = 0;    // 0 = not yet paired
integer gListener          = -1;   // Data channel listener handle
integer gDiscoveryListener = -1;   // Discovery channel listener handle
integer gDialogChannel;            // Private channel for all llDialog responses
integer gDialogListener    = -1;   // Dialog/menu listener handle
integer gRiding            = FALSE;
integer gHasPerms          = FALSE;
integer gPendingChannel    = 0;    // Channel offered by a nearby saddle
integer gMenuOpen          = FALSE; // TRUE while offset menu is showing
float   gStep              = 0.10; // Adjustment increment; cycles via Step button

// Offset menu buttons (displayed bottom-to-top, 3 per row):
// Row 3 (top): [Step ][Reset][Done ]
// Row 2:       [Y+   ][Z-   ][Z+   ]
// Row 1 (bot): [X-   ][X+   ][Y-   ]
list MENU_BUTTONS = ["X-", "X+", "Y-", "Y+", "Z-", "Z+", "Step", "Reset", "Done"];

// ---- HELPERS -----------------------------------------------------------

// Format a float to 2 decimal places for compact display.
string fmt(float f)
{
    string s = (string)f;
    integer dot = llSubStringIndex(s, ".");
    if (dot == -1) return s;
    return llGetSubString(s, 0, dot + 2);
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
    if (gChannel != 0) hint = "Done = save + start following";
    else               hint = "Done = save + close";
    return "Saddle Offset  (step: " + fmt(gStep) + " m)\n"
         + "X " + fmt(gSaddleOffset.x)
         + "   Y " + fmt(gSaddleOffset.y)
         + "   Z " + fmt(gSaddleOffset.z)
         + "\n\nX = fwd/back   Y = left/right   Z = up/down\n"
         + hint;
}

openOffsetMenu()
{
    // Close any existing dialog listener before opening a fresh one.
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

    // While riding, close discovery listener to save a listener slot.
    if (gDiscoveryListener != -1) { llListenRemove(gDiscoveryListener); gDiscoveryListener = -1; }
    if (gDialogListener    != -1) { llListenRemove(gDialogListener);    gDialogListener    = -1; }
    gMenuOpen = FALSE;
    llSetTimerEvent(0.0);

    llOwnerSay("[Rider] Following on channel " + (string)gChannel + ". Touch to stop.");
    llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
}

stopRiding()
{
    if (gListener != -1) { llListenRemove(gListener); gListener = -1; }
    llStopMoveToTarget();
    gRiding = FALSE;

    if (gHasPerms && RIDING_ANIM != "") llStopAnimation(RIDING_ANIM);

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
        if (gChannel != 0) startRiding();
        else llOwnerSay("[Rider] Offset saved. Pair with a saddle to start following.");
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

    // Refresh the dialog to show updated values; reset inactivity timer.
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
                    gChannel = gPendingChannel;
                    llOwnerSay("[Rider] Paired! Channel: " + (string)gChannel);
                    startRiding();
                }
                else
                {
                    llOwnerSay("[Rider] Pairing declined.");
                    gPendingChannel = 0;
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

    // Touch while riding = stop. Touch while stopped = open offset menu.
    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (gRiding) stopRiding();
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
            gPendingChannel = 0;
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
            gHasPerms  = FALSE;
            gChannel   = 0;
            gMenuOpen  = FALSE;
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
