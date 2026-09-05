package com.duet.alarm

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * The local-network fast path: when both phones are on the same wifi, ring
 * state and "for both of us" actions travel as a signed UDP broadcast instead
 * of a round trip to Postgres.
 *
 * Why this exists at all, when RingSync already does the same job over HTTP:
 * the ringing screen deliberately runs with no Flutter engine (docs/12 3.2),
 * so it has no Supabase realtime client to subscribe with. Getting sub-second
 * updates there would otherwise mean hand-rolling a Phoenix websocket in
 * Kotlin; a datagram is a fraction of that. Far apart, the couple falls back
 * to RingSync's polling, where a few seconds genuinely does not matter.
 *
 * Three rules this must never break:
 *
 *  1. STRICTLY ADDITIVE. Nothing about ringing, snoozing or dismissing waits
 *     on this, and every failure here is swallowed. RingSync still reports the
 *     same events to Postgres in parallel -- LAN is a speed-up, never the
 *     source of truth (ADR-001).
 *  2. SIGNED, ALWAYS. A datagram that can stop someone's alarm is an attack
 *     surface on a cafe wifi. Every message carries an HMAC over its body
 *     keyed by `pairs.lan_secret`, which only the two members can read and
 *     which is never transmitted. Bad signature, wrong pair, or a timestamp
 *     outside [REPLAY_WINDOW_MS] -> dropped without comment.
 *  3. THE RECEIVER DECIDES. A "dismiss for both" arriving here is a request,
 *     not a command: the phone that receives it checks its OWN
 *     allow_partner_dismiss before acting. That is strictly better than the
 *     cloud path, where the preference is enforced server-side in
 *     act_on_partner() and the client has to trust it.
 */
object LanSync {
    private const val TAG = "DuetLanSync"
    private const val PORT = 47821
    private const val PROTOCOL_VERSION = 1

    /** How far out of step a datagram's clock may be before it is treated as a
     *  replay. Generous, because two phones' clocks drift and neither is
     *  authoritative -- but far short of "still valid tomorrow". */
    private const val REPLAY_WINDOW_MS = 60_000L

    /** Broadcast that a peer's ring state changed, for any UI that is showing. */
    const val ACTION_PARTNER_STATE = "com.duet.alarm.PARTNER_STATE"
    const val EXTRA_STATE = "state"

    // ── Sending ──────────────────────────────────────────────────────────────

    /** Tells the other phone what this one is doing: ringing, snoozed, dismissed. */
    fun announceState(ctx: Context, sessionId: String, state: String) =
        send(ctx, sessionId, state = state, act = null)

    /** Asks the other phone to dismiss too. It decides whether to honour it. */
    fun requestDismissForBoth(ctx: Context, sessionId: String) =
        send(ctx, sessionId, state = null, act = "dismiss")

    private fun send(ctx: Context, sessionId: String, state: String?, act: String?) {
        val pairId = AuthStore.pairId(ctx) ?: return
        val secret = AuthStore.lanSecret(ctx) ?: return
        val me = AuthStore.userId(ctx) ?: return

        Thread {
            try {
                val body = JSONObject().apply {
                    put("v", PROTOCOL_VERSION)
                    put("pair", pairId)
                    put("from", me)
                    put("session", sessionId)
                    put("state", state ?: JSONObject.NULL)
                    put("act", act ?: JSONObject.NULL)
                    put("ts", System.currentTimeMillis())
                }.toString()

                // body and signature on separate lines rather than nested JSON:
                // the bytes signed are then exactly the bytes verified, with no
                // canonicalisation rules to get subtly wrong on either side.
                val payload = "$body\n${sign(body, secret)}".toByteArray()

                DatagramSocket().use { socket ->
                    socket.broadcast = true
                    for (address in broadcastAddresses()) {
                        runCatching {
                            socket.send(DatagramPacket(payload, payload.size, address, PORT))
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "lan send failed (non-fatal, cloud path still carries it)", t)
            }
        }.start()
    }

    /**
     * Every interface's broadcast address, plus the global one as a backstop.
     * Routers vary on which they will actually forward, and a phone can be on
     * more than one interface at once, so this sprays rather than guesses.
     */
    private fun broadcastAddresses(): List<InetAddress> {
        val found = mutableListOf<InetAddress>()
        runCatching {
            for (iface in NetworkInterface.getNetworkInterfaces()) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in iface.interfaceAddresses) {
                    addr.broadcast?.let { found.add(it) }
                }
            }
        }
        runCatching { found.add(InetAddress.getByName("255.255.255.255")) }
        return found
    }

    // ── Receiving ────────────────────────────────────────────────────────────

    private var listener: Thread? = null
    @Volatile private var socket: DatagramSocket? = null

    /**
     * Listens for the duration of a ring and no longer. Owned by AlarmService,
     * which is alive exactly as long as the alarm is -- a socket held open
     * beyond that would be battery drain in exchange for nothing.
     */
    fun startListening(ctx: Context, onPeerMessage: (state: String?, act: String?) -> Unit) {
        if (listener != null) return
        val pairId = AuthStore.pairId(ctx) ?: return
        val secret = AuthStore.lanSecret(ctx) ?: return
        val me = AuthStore.userId(ctx) ?: return

        listener = Thread {
            try {
                DatagramSocket(null).apply {
                    reuseAddress = true
                    broadcast = true
                    bind(java.net.InetSocketAddress(PORT))
                    socket = this
                }
                val buffer = ByteArray(2048)
                while (!Thread.currentThread().isInterrupted) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    socket?.receive(packet) ?: break
                    val raw = String(packet.data, 0, packet.length)
                    val parsed = verify(raw, pairId, secret, me) ?: continue
                    onPeerMessage(
                        parsed.optString("state", "").ifEmpty { null },
                        parsed.optString("act", "").ifEmpty { null },
                    )
                }
            } catch (t: Throwable) {
                // Includes the ordinary "socket closed" on stopListening().
                Log.i(TAG, "lan listener ended: ${t.message}")
            }
        }.also { it.start() }
    }

    fun stopListening() {
        runCatching { socket?.close() }
        socket = null
        listener?.interrupt()
        listener = null
    }

    /**
     * Returns the body only if it is a well-formed, correctly signed, fresh
     * message from the OTHER member of this pair. Anything else -- our own
     * broadcast echoing back, a neighbour's pair, a forged or replayed packet
     * -- yields null and is dropped silently.
     */
    private fun verify(raw: String, pairId: String, secret: String, me: String): JSONObject? {
        val split = raw.lastIndexOf('\n')
        if (split <= 0) return null
        val body = raw.substring(0, split)
        val signature = raw.substring(split + 1)

        if (!constantTimeEquals(sign(body, secret), signature)) return null

        val json = runCatching { JSONObject(body) }.getOrNull() ?: return null
        if (json.optInt("v") != PROTOCOL_VERSION) return null
        if (json.optString("pair") != pairId) return null
        if (json.optString("from") == me) return null // our own broadcast, echoed
        val age = System.currentTimeMillis() - json.optLong("ts")
        if (kotlin.math.abs(age) > REPLAY_WINDOW_MS) return null
        return json
    }

    // ── Signing ──────────────────────────────────────────────────────────────

    private fun sign(body: String, secret: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
        return Base64.encodeToString(mac.doFinal(body.toByteArray()), Base64.NO_WRAP)
    }

    /** Compares in fixed time, so a forged signature cannot be found one byte
     *  at a time by timing how long the rejection takes. */
    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].code xor b[i].code)
        return diff == 0
    }
}
