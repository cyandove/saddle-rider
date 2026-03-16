// -- Mount Transmitter (Saddle) ------------------------------------------
// Worn by: The MOUNT avatar
// Purpose: Broadcasts world position + rotation at 10 Hz on a private
//          channel derived from this object's key, so multiple mount/rider
//          pairs on the same region never interfere with each other.
//
// Setup:
//   1. Drop this script into the saddle prim.
//   2. Touch the saddle to hear your channel number, then share it with
//      your rider (or use the notecard method described in the README).
//   (Phantom is set automatically by the script.)
// ------------------------------------------------------------------------

integer gChannel;      // Derived from object key at startup
integer gBroadcasting; // TRUE while timer is running

// Derive a stable, unique negative channel from this object's key.
// Uses the first 7 hex digits of the UUID.
integer channelFromKey(key k)
{
    return -(integer)("0x" + llGetSubString((string)k, 0, 6));
}

default
{
    state_entry()
    {
        llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_PHANTOM, TRUE]);
        gChannel      = channelFromKey(llGetKey());
        gBroadcasting = TRUE;
        llSetTimerEvent(0.1); // 10 Hz broadcast
        llOwnerSay("[Saddle] Transmitter ready. Channel: " + (string)gChannel);
    }

    timer()
    {
        vector   pos = llGetPos();
        rotation rot = llGetRot();
        // Format: "pos|rot"  e.g. "<128.0,128.0,25.0>|<0.0,0.0,0.0,1.0>"
        llRegionSay(gChannel, (string)pos + "|" + (string)rot);
    }

    // Owner touches the saddle to hear/re-announce the channel.
    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        llOwnerSay("[Saddle] Channel: " + (string)gChannel
            + "  |  Object key: " + (string)llGetKey());
    }

    // Stop broadcasting cleanly when detached; restart on re-attach.
    attach(key id)
    {
        if (id == NULL_KEY)
        {
            llSetTimerEvent(0.0);
            gBroadcasting = FALSE;
        }
        else
        {
            // Key may change on re-attach in some viewers, re-derive to be safe.
            gChannel = channelFromKey(llGetKey());
            llSetTimerEvent(0.1);
            gBroadcasting = TRUE;
            llOwnerSay("[Saddle] Re-attached. Channel: " + (string)gChannel);
        }
    }

    // If the owner changes (e.g. transfer), reset cleanly.
    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }
}
