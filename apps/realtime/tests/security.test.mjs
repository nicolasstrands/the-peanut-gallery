import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "esbuild";
import { Miniflare, Log, LogLevel } from "miniflare";

let mf, temporary;
const peers = new Set();
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
before(async () => {
  temporary = await mkdtemp(join(tmpdir(), "peanut-security-"));
  // Test-only storage hooks are reachable solely through Miniflare's internal
  // namespace, never through the production public router or shipped Worker.
  const result = await build({
    stdin: {
      resolveDir: process.cwd(),
      contents: `
      import worker, { ReactionRoom } from './src/index.ts';
      export default worker;
      export class ProbeRoom extends ReactionRoom {
        async fetch(request) {
          const path = new URL(request.url).pathname;
          if (path === '/test/state') return Response.json(Object.fromEntries(await this.ctx.storage.list()));
          if (path === '/test/seed') { await this.ctx.storage.put(await request.json()); return new Response('ok'); }
          return super.fetch(request);
        }
      }`,
    },
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
    external: ["cloudflare:workers"],
  });
  mf = new Miniflare({
    name: "security-tests",
    script: result.outputFiles[0].text,
    modules: true,
    compatibilityDate: "2026-07-24",
    durableObjects: { ROOMS: { className: "ProbeRoom", useSQLite: true } },
    durableObjectsPersist: temporary,
    log: new Log(LogLevel.ERROR),
  });
  await mf.ready;
});
after(async () => {
  for (const peer of peers) {
    try {
      peer.ws.close();
    } catch {}
  }
  await mf?.dispose();
  if (temporary) await rm(temporary, { recursive: true, force: true });
});
async function create() {
  const response = await mf.dispatchFetch("https://example.test/rooms", {
    method: "POST",
  });
  assert.equal(response.status, 201);
  assert.equal(response.headers.get("cache-control"), "no-store");
  return response.json();
}
async function connect(room) {
  const response = await mf.dispatchFetch(
    `https://example.test/rooms/${room.roomId}`,
    { headers: { Upgrade: "websocket" } },
  );
  assert.equal(response.status, 101);
  const ws = response.webSocket;
  const messages = [];
  const listeners = new Set();
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    messages.push(message);
    for (const listener of listeners) listener(message);
  });
  ws.accept();
  const peer = {
    ws,
    messages,
    send: (value) =>
      ws.send(typeof value === "string" ? value : JSON.stringify(value)),
    next(predicate, from = 0) {
      const found = messages.slice(from).find(predicate);
      if (found) return Promise.resolve(found);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          listeners.delete(listener);
          reject(
            new Error(
              "Timed out waiting for message; got " +
                messages.map((m) => m.type + ":" + (m.code ?? "")).join(","),
            ),
          );
        }, 4000);
        const listener = (message) => {
          if (predicate(message)) {
            clearTimeout(timer);
            listeners.delete(listener);
            resolve(message);
          }
        };
        listeners.add(listener);
      });
    },
  };
  peers.add(peer);
  return peer;
}
async function joinRoom(peer, room, fields = {}) {
  const from = peer.messages.length;
  peer.send({
    type: "join-room",
    roomId: room.roomId,
    clientType: "web",
    ...fields,
  });
  await peer.next((m) => m.type === "room-ready", from);
  return peer.messages
    .slice(from)
    .find((m) => m.type === "participant-session");
}
async function setup(durationMs = 60000) {
  const room = await create();
  const host = await connect(room);
  await joinRoom(host, room, { clientType: "host", hostToken: room.hostToken });
  const voter = await connect(room);
  const session = await joinRoom(voter, room);
  const pollId = crypto.randomUUID();
  const from = host.messages.length;
  host.send({
    type: "poll-start",
    pollId,
    question: "Choose",
    options: [
      { id: "a", label: "A" },
      { id: "b", label: "B" },
    ],
    durationMs,
  });
  await host.next(
    (m) => m.type === "poll-state" && m.poll?.id === pollId,
    from,
  );
  return { room, host, voter, session, pollId };
}
async function state(room, seed) {
  const namespace = await mf.getDurableObjectNamespace("ROOMS");
  const stub = namespace.get(namespace.idFromName(room.roomId));
  if (seed)
    await stub.fetch("https://internal/test/seed", {
      method: "POST",
      body: JSON.stringify(seed),
    });
  return (await stub.fetch("https://internal/test/state")).json();
}
async function evict(room) {
  await mf.unsafeEvictDurableObject("security-tests", "ProbeRoom", {
    name: room.roomId,
    webSockets: "hibernate",
  });
}

test("public paths cannot initialize arbitrary rooms or reach internal provisioning", async () => {
  assert.equal(
    (
      await mf.dispatchFetch("https://example.test/internal/create", {
        method: "POST",
        body: "{}",
      })
    ).status,
    404,
  );
  assert.equal(
    (
      await mf.dispatchFetch("https://example.test/rooms/AAAAAA", {
        headers: { Upgrade: "websocket" },
      })
    ).status,
    404,
  );
  assert.equal(
    (
      await mf.dispatchFetch("https://example.test/alias/AAAAAA", {
        headers: { Upgrade: "websocket" },
      })
    ).status,
    404,
  );
  const room = await create();
  const other = await create();
  assert.notEqual(room.hostToken, other.hostToken);
  assert.notEqual(room.hostToken, room.displayToken);
  const peer = await connect(room);
  peer.send({
    type: "join-room",
    roomId: room.roomId,
    clientType: "host",
    hostToken: other.hostToken,
  });
  await peer.next((m) => m.code === "unauthorized");
});

test("forged host/macOS roles cannot dismiss a poll or obtain restricted results", async () => {
  const { room, host, voter, pollId } = await setup();
  const forged = await connect(room);
  forged.send({ type: "join-room", roomId: room.roomId, clientType: "host" });
  await forged.next((m) => m.code === "unauthorized");
  await joinRoom(forged, room, { clientType: "macos" });
  const publicPoll = await forged.next(
    (m) => m.type === "poll-state" && m.poll?.id === pollId,
  );
  assert.equal(Object.hasOwn(publicPoll.poll, "tally"), false);
  let from = forged.messages.length;
  forged.send({ type: "poll-dismiss", pollId });
  await forged.next((m) => m.code === "unauthorized", from);
  assert.equal((await state(room)).poll.id, pollId);
  const display = await connect(room);
  await joinRoom(display, room, {
    clientType: "macos",
    displayToken: room.displayToken,
  });
  assert.ok(
    (
      await display.next(
        (m) => m.type === "poll-state" && m.poll?.id === pollId,
      )
    ).poll.tally,
  );
  from = display.messages.length;
  display.send({ type: "poll-dismiss", pollId });
  await display.next((m) => m.code === "unauthorized", from);
  from = voter.messages.length;
  voter.send({
    type: "join-room",
    roomId: room.roomId,
    clientType: "host",
    hostToken: room.hostToken,
  });
  await voter.next((m) => m.code === "already_joined", from);
  const hostFrom = host.messages.length;
  host.send({ type: "poll-dismiss", pollId });
  await host.next((m) => m.type === "poll-state" && m.poll === null, hostFrom);
});

test("fingerprint rotation, repeated joins and reconnects cannot multiply a session's vote", async () => {
  const { room, host, voter, session, pollId } = await setup();
  for (let i = 0; i < 3; i++) {
    const from = host.messages.length;
    voter.send({
      type: "poll-vote",
      pollId,
      optionId: i === 2 ? "b" : "a",
      fingerprint: `forged-identity-${i}`,
    });
    await host.next(
      (m) =>
        m.type === "poll-state" &&
        Object.values(m.poll?.tally ?? {}).reduce((a, b) => a + b, 0) === 1 &&
        m.poll?.tally?.[i === 2 ? "b" : "a"] === 1,
      from,
    );
  }
  let from = voter.messages.length;
  voter.send({ type: "join-room", roomId: room.roomId, clientType: "web" });
  await voter.next((m) => m.code === "already_joined", from);
  const restored = await connect(room);
  const resumed = await joinRoom(restored, room, {
    participantToken: session.participantToken,
  });
  assert.equal(resumed.participantId, session.participantId);
  assert.equal(
    (
      await restored.next(
        (m) => m.type === "vote-accepted" && m.pollId === pollId,
      )
    ).optionId,
    "b",
  );
  const hostFrom = host.messages.length;
  restored.send({
    type: "poll-vote",
    pollId,
    optionId: "a",
    fingerprint: "entirely-different",
  });
  await host.next(
    (m) =>
      m.type === "poll-state" && m.poll?.tally?.a === 1 && !m.poll?.tally?.b,
    hostFrom,
  );
  assert.equal(Object.keys((await state(room))["poll-votes"]).length, 1);
  const otherRoom = await create();
  const wrongRoom = await connect(otherRoom);
  wrongRoom.send({
    type: "join-room",
    roomId: otherRoom.roomId,
    clientType: "web",
    participantToken: session.participantToken,
  });
  await wrongRoom.next((m) => m.code === "invalid_session");
});

test("authenticated roles and participant identity survive actual Durable Object hibernation", async () => {
  const { room, host, voter, session, pollId } = await setup();
  await evict(room);
  const from = host.messages.length;
  voter.send({
    type: "poll-vote",
    pollId,
    optionId: "a",
    participantId: "forged",
    fingerprint: "forged-after-eviction",
  });
  await host.next(
    (m) => m.type === "poll-state" && m.poll?.tally?.a === 1,
    from,
  );
  assert.equal(
    Object.keys((await state(room))["poll-votes"])[0],
    session.participantId,
  );
  const hostFrom = host.messages.length;
  host.send({ type: "poll-dismiss", pollId });
  await host.next((m) => m.type === "poll-state" && m.poll === null, hostFrom);
});

test("custom emoji work; non-emoji, oversized and malformed payloads are rejected", async () => {
  const room = await create();
  const peer = await connect(room);
  await joinRoom(peer, room);
  for (const emoji of ["🥳", "👩🏽‍💻", "🇲🇺", "❤️"]) {
    const from = peer.messages.length;
    peer.send({ type: "reaction", emoji, unrelated: "discard me" });
    const message = await peer.next(
      (m) => m.type === "reaction" && m.emoji === emoji,
      from,
    );
    assert.equal(Object.hasOwn(message, "unrelated"), false);
  }
  for (const emoji of ["arbitrary-key", "__proto__", "🔥🔥"]) {
    const from = peer.messages.length;
    peer.send({ type: "reaction", emoji });
    await peer.next((m) => m.code === "invalid_reaction", from);
  }
  let from = peer.messages.length;
  peer.send("null");
  await peer.next((m) => m.code === "invalid_message", from);
  from = peer.messages.length;
  peer.send("x".repeat(9000));
  await peer.next((m) => m.code === "invalid_message", from);
  assert.ok(Object.keys((await state(room)).leaderboard).length <= 64);
});

test("historical state is bounded on load and a full vocabulary cannot block default reactions", async () => {
  const room = await create();
  const emoji = Array.from({ length: 100 }, (_, i) =>
    String.fromCodePoint(0x1f600 + i),
  );
  // Use only single-emoji codepoints accepted by the production validator.
  const counts = Object.fromEntries(emoji.map((e) => [e, 2]));
  await state(room, { leaderboard: counts });
  await evict(room);
  const peer = await connect(room);
  await joinRoom(peer, room);
  assert.ok(Object.keys((await state(room)).leaderboard).length <= 64);
  const snapshot = await state(room);
  // If the seed includes non-emoji codepoints, fill the last slots through the
  // same loader to exercise the hard cap deterministically.
  assert.ok(Object.keys(snapshot.leaderboard).length >= 50);
  let from = peer.messages.length;
  peer.send({ type: "reaction", emoji: "🦄" });
  await peer.next((m) => m.code === "reaction_limit", from);
  from = peer.messages.length;
  peer.send({ type: "reaction", emoji: "🔥" });
  await peer.next((m) => m.type === "reaction" && m.emoji === "🔥", from);
  const leaderboard = await peer.next((m) => m.type === "leaderboard");
  assert.ok(Object.keys(leaderboard.counts).length <= 5);
});

test("reaction rate limits survive hibernation and never grow storage on rejection", async () => {
  const room = await create();
  const peer = await connect(room);
  await joinRoom(peer, room);
  const from = peer.messages.length;
  for (let i = 0; i < 14; i++) peer.send({ type: "reaction", emoji: "👏" });
  await peer.next((m) => m.code === "rate_limited", from);
  const beforeCount = (await state(room)).leaderboard["👏"];
  assert.ok(beforeCount <= 12);
  await evict(room);
  const again = peer.messages.length;
  peer.send({ type: "reaction", emoji: "👏" });
  await peer.next((m) => m.code === "rate_limited", again);
  assert.equal((await state(room)).leaderboard["👏"], beforeCount);
});

test("poll voter storage is bounded while existing sessions can revise their choice", async () => {
  const { room, host, voter, session, pollId } = await setup();
  const votes = Object.fromEntries(
    Array.from({ length: 299 }, (_, i) => [
      i.toString(16).padStart(64, "0"),
      "a",
    ]),
  );
  votes[session.participantId] = "a";
  // Put the existing session first so the loader retains its legitimate slot.
  const seeded = { [session.participantId]: "a", ...votes };
  await state(room, { "poll-votes": seeded });
  await evict(room);
  assert.equal(Object.keys((await state(room))["poll-votes"]).length, 256);
  const newcomer = await connect(room);
  await joinRoom(newcomer, room);
  let from = newcomer.messages.length;
  newcomer.send({ type: "poll-vote", pollId, optionId: "b" });
  await newcomer.next((m) => m.code === "voter_limit", from);
  from = host.messages.length;
  voter.send({ type: "poll-vote", pollId, optionId: "b" });
  await host.next(
    (m) => m.type === "poll-state" && m.poll?.tally?.b === 1,
    from,
  );
  assert.equal(Object.keys((await state(room))["poll-votes"]).length, 256);
  const stored = await state(room);
  await state(room, { room: { ...stored.room, expiresAt: Date.now() - 1000 } });
  await evict(room);
  assert.equal(
    (
      await mf.dispatchFetch(`https://example.test/rooms/${room.roomId}`, {
        headers: { Upgrade: "websocket" },
      })
    ).status,
    404,
  );
  assert.deepEqual(await state(room), {});
});

test("poll deadlines and host reconnect retain legitimate lifecycle", async () => {
  const { room, host, voter, pollId } = await setup(1000);
  await host.next(
    (m) =>
      m.type === "poll-state" &&
      m.poll?.id === pollId &&
      m.poll?.status === "complete",
  );
  voter.send({ type: "poll-vote", pollId, optionId: "a" });
  await delay(50);
  assert.deepEqual((await state(room))["poll-votes"], {});
  const reconnect = await connect(room);
  await joinRoom(reconnect, room, {
    clientType: "host",
    hostToken: room.hostToken,
  });
  const from = reconnect.messages.length;
  reconnect.send({ type: "poll-dismiss", pollId });
  await reconnect.next((m) => m.type === "poll-state" && m.poll === null, from);
});

test("new browser sessions can vote automatically without host approval", async () => {
  const { room, host, pollId } = await setup();
  const peer = await connect(room);
  await joinRoom(peer, room);
  const from = host.messages.length;
  peer.send({ type: "poll-vote", pollId, optionId: "a" });
  await host.next(
    (m) => m.type === "poll-state" && m.poll?.tally?.a === 1,
    from,
  );
  assert.equal(Object.keys((await state(room))["poll-votes"]).length, 1);
  assert.equal(
    peer.messages.some((m) => m.type === "participant-status"),
    false,
  );
});

test("non-voting reconnects remain stateless and forged or cross-room signed tokens are rejected", async () => {
  const room = await create();
  const original = await connect(room);
  const session = await joinRoom(original, room);
  original.ws.close();
  await evict(room);
  const resumed = await connect(room);
  const identity = await joinRoom(resumed, room, {
    participantToken: session.participantToken,
  });
  assert.equal(identity.participantId, session.participantId);
  assert.equal(Object.hasOwn(await state(room), "participants"), false);
  const forged = await connect(room);
  forged.send({
    type: "join-room",
    roomId: room.roomId,
    clientType: "web",
    participantToken: "0".repeat(64) + "." + "0".repeat(64),
  });
  await forged.next((m) => m.code === "invalid_session");
  const otherRoom = await create();
  const wrongRoom = await connect(otherRoom);
  wrongRoom.send({
    type: "join-room",
    roomId: otherRoom.roomId,
    clientType: "web",
    participantToken: session.participantToken,
  });
  await wrongRoom.next((m) => m.code === "invalid_session");
});
