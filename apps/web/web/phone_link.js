// Desktop side of the QR phone-photo hand-off. Driven from Dart through
// dart:js_interop (see lib/src/phone_link_web.dart): Dart calls
// window.dmxtractPhoneLink.start/stop and receives status and photo events
// through the callback functions it passes in. See phone_link_shared.js for
// the crypto/signaling design; see phone/phone.js for the phone side.
import {
  importAesGcmKey,
  encryptJSON,
  decryptJSON,
  newPeerConnection,
  waitForIceGatheringComplete,
  webRtcSupported,
  honestConnectFailureMessage,
  SIGNAL_PATH,
} from "./phone_link_shared.js";

const WAIT_FOR_PHONE_MS = 3 * 60 * 1000;
const POLL_INTERVAL_MS = 1200;

let active = null;

async function start(sessionId, keyBase64Url, onEvent, onPhoto) {
  await stop();
  const session = { stopped: false, pc: null, channel: null, pollTimer: null };
  active = session;
  const emit = (type, message) => {
    if (session.stopped) return;
    onEvent(JSON.stringify(message ? { type, message } : { type }));
  };

  try {
    const key = await importAesGcmKey(keyBase64Url);
    const pc = newPeerConnection();
    session.pc = pc;
    const channel = pc.createDataChannel("photos", { ordered: true });
    session.channel = channel;
    bindDataChannel(channel, emit, onPhoto);

    pc.addEventListener("iceconnectionstatechange", () => {
      if (session.stopped) return;
      if (pc.iceConnectionState === "failed" || pc.iceConnectionState === "disconnected") {
        emit("error", honestConnectFailureMessage());
      }
    });

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await waitForIceGatheringComplete(pc);
    const encryptedOffer = await encryptJSON(key, {
      sdp: pc.localDescription.sdp,
      type: pc.localDescription.type,
    });

    const signalUrl = new URL(SIGNAL_PATH, location.origin);
    const posted = await fetch(signalUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        sessionId,
        slot: "offer",
        iv: encryptedOffer.iv,
        ciphertext: encryptedOffer.ciphertext,
      }),
    });
    if (!posted.ok) {
      emit("error", "Couldn’t start the hand-off. Try again.");
      return;
    }

    emit("waiting");
    await pollForAnswer(session, signalUrl, sessionId, key, pc, emit);
  } catch {
    emit("error", honestConnectFailureMessage());
  }
}

function bindDataChannel(channel, emit, onPhoto) {
  // Chrome defaults to "arraybuffer", but the WebRTC spec default is "blob"
  // and Firefox honors that default. Force "arraybuffer" so every browser
  // hands the message handler an ArrayBuffer instead of a Blob — otherwise
  // `new Uint8Array(event.data)` on a Blob silently yields a zero-length view.
  channel.binaryType = "arraybuffer";
  let receiving = null;
  channel.addEventListener("open", () => emit("connected"));
  channel.addEventListener("close", () => emit("closed"));
  channel.addEventListener("message", (event) => {
    if (typeof event.data === "string") {
      const message = JSON.parse(event.data);
      if (message.type === "photo-begin") {
        receiving = { name: message.name, mime: message.mime, size: message.size, chunks: [], received: 0 };
      } else if (message.type === "photo-end" && receiving) {
        if (receiving.received !== receiving.size) {
          emit("error", honestConnectFailureMessage());
          receiving = null;
          return;
        }
        const bytes = new Uint8Array(receiving.size);
        let offset = 0;
        for (const chunk of receiving.chunks) {
          bytes.set(chunk, offset);
          offset += chunk.length;
        }
        onPhoto(receiving.name, receiving.mime, bytes);
        receiving = null;
      }
    } else if (receiving) {
      const chunk = new Uint8Array(event.data);
      receiving.chunks.push(chunk);
      receiving.received += chunk.length;
    }
  });
}

async function pollForAnswer(session, signalUrl, sessionId, key, pc, emit) {
  const deadline = Date.now() + WAIT_FOR_PHONE_MS;
  while (!session.stopped && Date.now() < deadline) {
    await new Promise((resolve) => {
      session.pollTimer = setTimeout(resolve, POLL_INTERVAL_MS);
    });
    if (session.stopped) return;

    const pollUrl = new URL(signalUrl);
    pollUrl.searchParams.set("sessionId", sessionId);
    pollUrl.searchParams.set("slot", "answer");
    const response = await fetch(pollUrl);
    if (!response.ok) continue;
    const body = await response.json();
    if (!body.ready) continue;

    const answer = await decryptJSON(key, body.iv, body.ciphertext);
    await pc.setRemoteDescription(answer);
    emit("phoneJoined");
    return;
  }
  if (!session.stopped) emit("error", honestConnectFailureMessage());
}

async function stop() {
  if (!active) return;
  const session = active;
  active = null;
  session.stopped = true;
  if (session.pollTimer) clearTimeout(session.pollTimer);
  try {
    session.channel?.close();
  } catch {
    // Already closed; nothing to clean up.
  }
  try {
    session.pc?.close();
  } catch {
    // Already closed; nothing to clean up.
  }
}

window.dmxtractPhoneLink = { start, stop, supported: webRtcSupported };
