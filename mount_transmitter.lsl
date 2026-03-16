// -- Mount Transmitter (Saddle) ------------------------------------------
// Worn by: The MOUNT avatar
// Purpose: Broadcasts world position + rotation at 10 Hz on a stable
//          channel derived from the mount owner's avatar key. Also
//          periodically announces pairing info on a fixed discovery
//          channel so the rider's attachment can pair automatically
//          via a confirmation dialog -- no channel number copy-paste needed.
//
// Setup:
//   1. Drop this script into the saddle prim.
//   2. Touch the saddle to send an immediate pairing signal; your rider
//      will see a dialog asking to confirm the connection.
//   (Phantom and channel are set automatically by the script.)
// ------------------------------------------------------------------------

// Fixed well-known channel for pairing broadcasts.
// Must match DISCOVERY_CHANNEL in rider_follower.lsl.
integer DISCOVERY_CHANNEL = -7654321;

integer gChannel;       // Derived from mount OWNER's avatar key -- stable across relogs
integer gBroadcasting;
integer gDiscoveryTick; // Counts 0.1 s ticks; discovery broadcast sent every 10 s

// Derive a stable negative channel from any key.
integer channelFromKey(key k)
{
    return -(integer)("0x" + llGetSubString((string)k, 0, 6));
}

// Broadcast presence on the discovery channel so the rider can pair.
announceDiscovery()
{
    llRegionSay(DISCOVERY_CHANNEL,
        "SADDLE_PAIR|" + (string)llGetOwner()
        + "|" + llKey2Name(llGetOwner())
        + "|" + (string)gChannel);
}

default
{
    state_entry()
    {
        llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_PHANTOM, TRUE]);
        // Channel derived from OWNER avatar key -- stable across re-attaches.
        gChannel       = channelFromKey(llGetOwner());
        gBroadcasting  = TRUE;
        gDiscoveryTick = 0;
        llSetTimerEvent(0.1); // 10 Hz broadcast
        llOwnerSay("[Saddle] Transmitter ready. Channel: " + (string)gChannel
            + "  -- Touch to send pairing signal to your rider.");
    }

    timer()
    {
        vector   pos = llGetPos();
        rotation rot = llGetRot();
        llRegionSay(gChannel, (string)pos + "|" + (string)rot);

        // Send discovery announcement every 10 seconds (100 ticks at 10 Hz).
        if (++gDiscoveryTick >= 100)
        {
            gDiscoveryTick = 0;
            announceDiscovery();
        }
    }

    // Owner touches the saddle to trigger an immediate pairing broadcast.
    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        llOwnerSay("[Saddle] Channel: " + (string)gChannel
            + "  |  Object key: " + (string)llGetKey());
        announceDiscovery();
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
            // Avatar key is stable, but re-derive in case of edge cases.
            gChannel       = channelFromKey(llGetOwner());
            gDiscoveryTick = 0;
            llSetTimerEvent(0.1);
            gBroadcasting  = TRUE;
            llOwnerSay("[Saddle] Re-attached. Channel: " + (string)gChannel);
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }
}
