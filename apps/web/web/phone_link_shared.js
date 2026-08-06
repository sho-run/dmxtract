// Shared WebRTC + crypto helpers for the QR phone-photo hand-off, used by
// both the desktop app (phone_link.js) and the phone page (phone/phone.js).
//
// The AES-GCM key lives only in the URL fragment (`#sessionId.key`, set by
// the desktop when it generates the QR code) and is never sent to, or
// derivable by, the signaling relay. Every value that crosses the relay
// (SDP offer/answer) is encrypted client-side with this key before it is
// POSTed, so the server only ever stores and forwards ciphertext it cannot
// read. Once the WebRTC DataChannel opens, photos travel peer-to-peer and
// never touch the relay at all.
//
// ICE candidates are not trickled through the relay: both sides wait for
// `icegatheringstate` to reach "complete" before sending their local
// description, so the whole handshake is a single encrypted offer and a
// single encrypted answer. That keeps the relay's job to exactly two writes
// and two reads per session, at the cost of the few seconds STUN gathering
// takes on a normal network.

export const STUN_SERVERS = [{ urls: "stun:stun.l.google.com:19302" }];
export const CHUNK_BYTES = 16 * 1024;
export const SIGNAL_PATH = "/api/phone-link-signal";

export function base64UrlEncode(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64UrlDecode(text) {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/");
  const withPadding = padded + "=".repeat((4 - (padded.length % 4)) % 4);
  const binary = atob(withPadding);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function importAesGcmKey(keyBase64Url) {
  const raw = base64UrlDecode(keyBase64Url);
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encryptJSON(key, value) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(JSON.stringify(value));
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext);
  return { iv: base64UrlEncode(iv), ciphertext: base64UrlEncode(new Uint8Array(ciphertext)) };
}

export async function decryptJSON(key, ivBase64Url, ciphertextBase64Url) {
  const iv = base64UrlDecode(ivBase64Url);
  const ciphertext = base64UrlDecode(ciphertextBase64Url);
  const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext);
  return JSON.parse(new TextDecoder().decode(plaintext));
}

export function newPeerConnection() {
  return new RTCPeerConnection({ iceServers: STUN_SERVERS });
}

// Waits for ICE gathering to finish so the local description (with all
// candidates already embedded) can be sent as a single signaling message.
export function waitForIceGatheringComplete(pc, timeoutMs = 8000) {
  if (pc.iceGatheringState === "complete") return Promise.resolve();
  return new Promise((resolve) => {
    const timer = setTimeout(finish, timeoutMs);
    function finish() {
      clearTimeout(timer);
      pc.removeEventListener("icegatheringstatechange", onChange);
      resolve();
    }
    function onChange() {
      if (pc.iceGatheringState === "complete") finish();
    }
    pc.addEventListener("icegatheringstatechange", onChange);
  });
}

export function webRtcSupported() {
  return (
    typeof RTCPeerConnection !== "undefined" &&
    typeof crypto !== "undefined" &&
    typeof crypto.subtle?.encrypt === "function"
  );
}

const HONEST_CONNECT_FAILURE =
  "Couldn’t connect the two devices — your photos never left them. Try the same Wi-Fi, or AirDrop/email the photos instead.";

export function honestConnectFailureMessage() {
  return HONEST_CONNECT_FAILURE;
}
