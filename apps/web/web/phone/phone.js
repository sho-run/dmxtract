// Phone side of the QR phone-photo hand-off: no Flutter, no bundler, no
// server upload. Loaded from index.html in this directory when a phone
// scans the QR code shown on the desktop's Add manual step. The AES-GCM key
// travels only in the URL fragment (never sent anywhere, including here);
// see phone_link_shared.js for the crypto/signaling design.
import {
  importAesGcmKey,
  encryptJSON,
  decryptJSON,
  newPeerConnection,
  waitForIceGatheringComplete,
  webRtcSupported,
  honestConnectFailureMessage,
  CHUNK_BYTES,
  SIGNAL_PATH,
} from "../phone_link_shared.js";

const FIND_DESKTOP_TIMEOUT_MS = 45 * 1000;
const POLL_INTERVAL_MS = 1000;
const BUFFERED_AMOUNT_HIGH_WATER = 1 << 20; // 1 MiB

const statusEl = document.getElementById("status");
const statusTextEl = document.getElementById("statusText");
const takePhotoButton = document.getElementById("takePhotoButton");
const chooseLibraryButton = document.getElementById("chooseLibraryButton");
const cameraInput = document.getElementById("cameraInput");
const libraryInput = document.getElementById("libraryInput");
const queueEl = document.getElementById("queue");
const sendButton = document.getElementById("sendButton");

const queue = []; // { file, url, sent }
let channel = null;
let sending = false;

function setStatus(text, kind) {
  statusTextEl.textContent = text;
  statusEl.className = "status" + (kind ? ` ${kind}` : "");
  const spinner = statusEl.querySelector(".spinner");
  if (kind) {
    spinner?.remove();
  } else if (!spinner) {
    statusEl.insertAdjacentHTML("afterbegin", '<div class="spinner"></div>');
  }
}

function fail(message) {
  setStatus(message, "error");
  takePhotoButton.disabled = true;
  chooseLibraryButton.disabled = true;
  sendButton.disabled = true;
}

function renderQueue() {
  queueEl.innerHTML = "";
  queue.forEach((item, index) => {
    const tile = document.createElement("div");
    tile.className = "tile";
    tile.innerHTML = `
      <img src="${item.url}" alt="Queued photo ${index + 1}">
      <span class="badge">${index + 1}</span>
      ${item.sent ? '<div class="sent">✅</div>' : `<button class="remove" type="button" aria-label="Remove photo ${index + 1}">×</button>`}
    `;
    if (!item.sent) {
      tile.querySelector(".remove").addEventListener("click", () => {
        URL.revokeObjectURL(item.url);
        queue.splice(index, 1);
        renderQueue();
      });
    }
    queueEl.appendChild(tile);
  });
  const pending = queue.filter((item) => !item.sent);
  sendButton.disabled = pending.length === 0 || sending || !channel || channel.readyState !== "open";
  sendButton.textContent = sending
    ? "Sending…"
    : pending.length === 0
      ? "Send photos"
      : `Send ${pending.length} ${pending.length === 1 ? "photo" : "photos"}`;
}

function enqueueFiles(files) {
  for (const file of files) {
    if (!file.type.startsWith("image/")) continue;
    queue.push({ file, url: URL.createObjectURL(file), sent: false });
  }
  renderQueue();
}

cameraInput.addEventListener("change", () => {
  enqueueFiles(cameraInput.files);
  cameraInput.value = "";
});
libraryInput.addEventListener("change", () => {
  enqueueFiles(libraryInput.files);
  libraryInput.value = "";
});
takePhotoButton.addEventListener("click", () => cameraInput.click());
chooseLibraryButton.addEventListener("click", () => libraryInput.click());
sendButton.addEventListener("click", () => sendQueuedPhotos());

async function sendQueuedPhotos() {
  if (sending || !channel || channel.readyState !== "open") return;
  sending = true;
  renderQueue();
  try {
    for (const item of queue) {
      if (item.sent) continue;
      await sendPhoto(item.file);
      item.sent = true;
      renderQueue();
    }
    setStatus("Sent! You can take more, or close this page.", "ok");
  } catch {
    setStatus(honestConnectFailureMessage(), "error");
  } finally {
    sending = false;
    renderQueue();
  }
}

async function sendPhoto(file) {
  const bytes = new Uint8Array(await file.arrayBuffer());
  channel.send(JSON.stringify({ type: "photo-begin", name: file.name, mime: file.type, size: bytes.length }));
  for (let offset = 0; offset < bytes.length; offset += CHUNK_BYTES) {
    await waitForBufferSpace();
    channel.send(bytes.subarray(offset, offset + CHUNK_BYTES));
  }
  channel.send(JSON.stringify({ type: "photo-end" }));
}

function waitForBufferSpace() {
  if (channel.bufferedAmount < BUFFERED_AMOUNT_HIGH_WATER) return Promise.resolve();
  return new Promise((resolve) => {
    const check = () => {
      if (channel.bufferedAmount < BUFFERED_AMOUNT_HIGH_WATER) resolve();
      else setTimeout(check, 40);
    };
    check();
  });
}

async function connect() {
  if (!webRtcSupported()) {
    fail("This browser can’t make a direct connection. Try a recent version of Chrome or Safari.");
    return;
  }
  const fragment = location.hash.replace(/^#/, "");
  const separator = fragment.indexOf(".");
  if (separator < 1) {
    fail("This link looks incomplete. Go back to DMXtract and scan a fresh QR code.");
    return;
  }
  const sessionId = fragment.slice(0, separator);
  const keyBase64Url = fragment.slice(separator + 1);

  try {
    const key = await importAesGcmKey(keyBase64Url);
    // The session id + key are never sent in an HTTP request, but leaving
    // them in the address bar exposes them to browser history and tab sync
    // (Chrome Sync, iCloud Tabs, etc.) for the life of this page. Strip the
    // fragment as soon as it's been read.
    history.replaceState(null, "", location.pathname + location.search);
    const signalUrl = new URL(SIGNAL_PATH, location.origin);

    const offerBody = await findOffer(signalUrl, sessionId);
    if (!offerBody) {
      fail("Couldn’t find your computer. Make sure the QR code is still on screen, then scan it again.");
      return;
    }
    const offer = await decryptJSON(key, offerBody.iv, offerBody.ciphertext);

    setStatus("Connecting…");
    const pc = newPeerConnection();
    pc.addEventListener("iceconnectionstatechange", () => {
      if (pc.iceConnectionState === "failed" || pc.iceConnectionState === "disconnected") {
        fail(honestConnectFailureMessage());
      }
    });
    pc.addEventListener("datachannel", (event) => bindChannel(event.channel));

    await pc.setRemoteDescription(offer);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await waitForIceGatheringComplete(pc);
    const encryptedAnswer = await encryptJSON(key, {
      sdp: pc.localDescription.sdp,
      type: pc.localDescription.type,
    });

    const answerUrl = new URL(signalUrl);
    const posted = await fetch(answerUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        sessionId,
        slot: "answer",
        iv: encryptedAnswer.iv,
        ciphertext: encryptedAnswer.ciphertext,
      }),
    });
    if (!posted.ok) {
      fail(honestConnectFailureMessage());
    }
  } catch {
    fail(honestConnectFailureMessage());
  }
}

function bindChannel(dataChannel) {
  channel = dataChannel;
  channel.addEventListener("open", () => {
    setStatus("Connected! Take or choose photos, then send.", "ok");
    takePhotoButton.disabled = false;
    chooseLibraryButton.disabled = false;
    renderQueue();
  });
  channel.addEventListener("close", () => {
    if (statusEl.classList.contains("error")) return;
    fail("The connection to your computer closed. Scan the QR code again to reconnect.");
  });
}

async function findOffer(signalUrl, sessionId) {
  const deadline = Date.now() + FIND_DESKTOP_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const pollUrl = new URL(signalUrl);
    pollUrl.searchParams.set("sessionId", sessionId);
    pollUrl.searchParams.set("slot", "offer");
    const response = await fetch(pollUrl);
    if (response.ok) {
      const body = await response.json();
      if (body.ready) return body;
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
  }
  return null;
}

connect();
