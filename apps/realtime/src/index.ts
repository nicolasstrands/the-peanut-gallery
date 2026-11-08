import { DurableObject } from "cloudflare:workers";
import emojiRegex from "emoji-regex";
import type {
  ClientType,
  PollState,
  RoomCreatedMessage,
} from "@peanut-gallery/protocol";

export interface Env {
  ROOMS: DurableObjectNamespace<ReactionRoom>;
}

const ROOM_LIFETIME_MS = 24 * 60 * 60 * 1000;
const MAX_SOCKETS = 64;
const MAX_VOTERS_PER_POLL = 256;
const MAX_REACTION_KEYS = 64;
const MAX_MESSAGE_BYTES = 8192;
const DEFAULT_REACTIONS = ["🔥", "👏", "😂", "❤️", "👀", "💀", "🎉"];
const TOKEN = /^[a-f0-9]{64}$/;
const ROOM_CODE = /^[A-Z0-9]{6}$/;
const emojiPattern = emojiRegex();

type Room = {
  version: 1;
  roomId: string;
  hostHash: string;
  participantKey: string;
  displayHash: string;
  expiresAt: number;
};
type Rate = {
  start: number;
  messages: number;
  reactions: number;
  votes: number;
};
type Session = {
  version: 1;
  roomKey: string;
  role: ClientType;
  participantId?: string;
  rate: Rate;
};
type Input = Record<string, unknown>;

function token() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}
async function hash(value: string) {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(bytes), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}
function object(value: unknown): value is Input {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function text(value: unknown, max: number): value is string {
  return (
    typeof value === "string" && value.trim().length > 0 && value.length <= max
  );
}
function rate(): Rate {
  return { start: Date.now(), messages: 0, reactions: 0, votes: 0 };
}
function singleEmoji(value: unknown): value is string {
  if (!text(value, 32)) return false;
  emojiPattern.lastIndex = 0;
  const match = value.match(emojiPattern);
  return match?.length === 1 && match[0] === value;
}
function freshCounts(): Record<string, number> {
  return Object.assign(
    Object.create(null),
    Object.fromEntries(DEFAULT_REACTIONS.map((emoji) => [emoji, 0])),
  );
}
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Cache-Control": "no-store",
};
function json(value: unknown, status = 200) {
  return Response.json(value, { status, headers: cors });
}

export class ReactionRoom extends DurableObject<Env> {
  private room: Room | null = null;
  private counts = freshCounts();
  private poll: PollState | null = null;
  private votes: Record<string, string> = Object.create(null);
  private ready: Promise<void>;
  private leaderboardScheduled = false;
  private signingKey: CryptoKey | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ready = ctx.blockConcurrencyWhile(async () => {
      const stored = await ctx.storage.get<Room>("room");
      // Pre-capability rooms have no authenticated creator. Never claim them by
      // first connection or load their historical unbounded collections.
      if (!stored || stored.version !== 1 || !TOKEN.test(stored.participantKey))
        return;
      this.room = stored;
      if (Date.now() >= stored.expiresAt) {
        await this.expire();
        return;
      }
      const counts =
        await ctx.storage.get<Record<string, number>>("leaderboard");
      for (const [emoji, count] of Object.entries(counts ?? {}).slice(
        0,
        MAX_REACTION_KEYS,
      )) {
        if (!singleEmoji(emoji) || !Number.isSafeInteger(count) || count < 0)
          continue;
        if (
          !Object.hasOwn(this.counts, emoji) &&
          Object.keys(this.counts).length >= MAX_REACTION_KEYS
        )
          continue;
        this.counts[emoji] = count;
      }
      this.poll = (await ctx.storage.get<PollState>("poll")) ?? null;
      const votes = await ctx.storage.get<Record<string, string>>("poll-votes");
      for (const [id, option] of Object.entries(votes ?? {}).slice(
        0,
        MAX_VOTERS_PER_POLL,
      )) {
        if (
          TOKEN.test(id) &&
          this.poll?.options.some((item) => item.id === option)
        )
          this.votes[id] = option;
      }
      await ctx.storage.delete("participants");
      // Persist the bounded representation before any further mutation.
      await ctx.storage.put({
        leaderboard: this.counts,
        "poll-votes": this.votes,
      });
    });
  }

  async fetch(request: Request) {
    await this.ready;
    // Only the outer worker can reach this path. Public routing below never
    // forwards arbitrary HTTP paths to a room object.
    if (
      request.method === "POST" &&
      new URL(request.url).pathname === "/internal/create"
    ) {
      return this.ctx.blockConcurrencyWhile(async () => {
        if (this.room && Date.now() < this.room.expiresAt)
          return json({ error: "Room already exists" }, 409);
        const input = (await request.json()) as RoomCreatedMessage;
        if (
          !ROOM_CODE.test(input.roomId) ||
          !TOKEN.test(input.hostToken) ||
          !TOKEN.test(input.displayToken)
        )
          return json({ error: "Invalid room" }, 400);
        if (this.room) await this.expire();
        await this.ctx.storage.deleteAll();
        this.room = {
          version: 1,
          roomId: input.roomId,
          hostHash: await hash(input.hostToken),
          participantKey: token(),
          displayHash: await hash(input.displayToken),
          expiresAt: input.expiresAt,
        };
        this.counts = freshCounts();
        this.votes = Object.create(null);
        this.poll = null;
        await this.ctx.storage.put({
          room: this.room,
          leaderboard: this.counts,
        });
        await this.scheduleAlarm();
        return json(input, 201);
      });
    }
    if (!(await this.live()))
      return json(
        { error: "Room is unavailable. Ask the host for a new invitation." },
        404,
      );
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket")
      return json({ error: "Expected WebSocket" }, 426);
    if (this.ctx.getWebSockets().length >= MAX_SOCKETS)
      return json({ error: "Room connection limit reached" }, 429);
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    await this.ready;
    await this.ctx.blockConcurrencyWhile(async () => {
      if (!(await this.live())) return;
      if (
        typeof message !== "string" ||
        message.length > MAX_MESSAGE_BYTES ||
        new TextEncoder().encode(message).byteLength > MAX_MESSAGE_BYTES
      ) {
        this.error(
          ws,
          "invalid_message",
          "Message is too large or is not text.",
        );
        return;
      }
      let input: unknown;
      try {
        input = JSON.parse(message);
      } catch {
        this.error(ws, "invalid_message", "Invalid message.");
        return;
      }
      if (!object(input) || typeof input.type !== "string") {
        this.error(ws, "invalid_message", "Invalid message.");
        return;
      }
      let session = this.session(ws);
      if (!(await this.acceptMessage(ws, session, input.type))) return;
      if (input.type === "join-room") {
        if (session) {
          this.error(
            ws,
            "already_joined",
            "This connection already has an identity.",
          );
          return;
        }
        if (input.roomId !== this.room!.roomId) {
          this.error(ws, "invalid_room", "Room does not match the invitation.");
          return;
        }
        let participantToken: string | undefined;
        if (input.clientType === "host") {
          if (!(await this.authorized(input.hostToken, this.room!.hostHash))) {
            this.error(
              ws,
              "unauthorized",
              "A private host credential is required.",
            );
            return;
          }
          session = {
            version: 1,
            roomKey: this.room!.hostHash,
            role: "host",
            rate: rate(),
          };
        } else if (input.clientType === "macos") {
          // Room-only native clients may still receive public reactions/polls.
          // Only the separate read-only display capability grants result access.
          const display = await this.authorized(
            input.displayToken,
            this.room!.displayHash,
          );
          if (input.displayToken !== undefined && !display) {
            this.error(
              ws,
              "unauthorized",
              "The display credential is invalid.",
            );
            return;
          }
          session = {
            version: 1,
            roomKey: this.room!.hostHash,
            role: display ? "macos" : "web",
            rate: rate(),
          };
        } else if (input.clientType === "web") {
          if (input.participantToken !== undefined) {
            if (!(await this.validParticipantToken(input.participantToken))) {
              this.error(
                ws,
                "invalid_session",
                "Your participant session is invalid.",
              );
              return;
            }
            participantToken = input.participantToken as string;
          } else {
            participantToken = await this.issueParticipantToken();
          }
          const participantId = await hash(participantToken);
          // Joining is automatic and stateless. Only votes allocate durable
          // entries, with a fixed per-poll cap; reconnects reuse this identity.
          session = {
            version: 1,
            roomKey: this.room!.hostHash,
            role: "web",
            participantId,
            rate: rate(),
          };
        } else {
          this.error(ws, "invalid_message", "Unknown client type.");
          return;
        }
        ws.serializeAttachment(session);
        if (session.participantId)
          this.send(ws, {
            type: "participant-session",
            participantToken,
            participantId: session.participantId,
          });
        this.send(ws, { type: "room-ready" });
        this.sendLeaderboard(ws);
        this.sendPoll(ws);
        this.sendChoice(ws);
        this.broadcastPresence();
        return;
      }
      if (!session) {
        this.error(
          ws,
          "join_required",
          "Join the room before sending messages.",
        );
        return;
      }
      if (input.type === "presence-sync") {
        this.broadcastPresence();
        return;
      }
      if (input.type === "poll-start") {
        if (session.role !== "host") {
          this.error(ws, "unauthorized", "Only the host can start a poll.");
          return;
        }
        if (
          this.poll ||
          !this.ctx
            .getWebSockets()
            .some((client) => !!this.session(client)?.participantId)
        ) {
          this.error(
            ws,
            "poll_unavailable",
            "Wait for a participant and dismiss any previous poll first.",
          );
          return;
        }
        if (!this.validPoll(input)) {
          this.error(
            ws,
            "invalid_poll",
            "Check the question, answers, and duration.",
          );
          return;
        }
        const endAt = Date.now() + (input.durationMs as number);
        if (endAt > this.room!.expiresAt) {
          this.error(
            ws,
            "room_expiring",
            "Choose a shorter poll or create a new room.",
          );
          return;
        }
        this.poll = {
          id: input.pollId as string,
          question: (input.question as string).trim(),
          options: input.options as PollState["options"],
          startAt: Date.now(),
          endAt,
          status: "active",
        };
        this.votes = Object.create(null);
        await this.persistPoll();
        await this.scheduleAlarm();
        this.broadcastPoll();
        return;
      }
      if (input.type === "poll-dismiss") {
        if (session.role !== "host") {
          this.error(ws, "unauthorized", "Only the host can dismiss a poll.");
          return;
        }
        if (!this.poll || input.pollId !== this.poll.id) return;
        this.poll = null;
        this.votes = Object.create(null);
        await this.persistPoll();
        await this.scheduleAlarm();
        this.broadcastPoll();
        return;
      }
      if (input.type === "poll-vote") {
        if (session.role !== "web" || !session.participantId) {
          this.error(ws, "unauthorized", "Join as a participant to vote.");
          return;
        }
        if (
          !this.poll ||
          this.poll.status !== "active" ||
          input.pollId !== this.poll.id ||
          Date.now() >= this.poll.endAt
        )
          return;
        if (!this.poll.options.some((option) => option.id === input.optionId)) {
          this.error(ws, "invalid_vote", "Choose an available answer.");
          return;
        }
        if (
          !Object.hasOwn(this.votes, session.participantId) &&
          Object.keys(this.votes).length >= MAX_VOTERS_PER_POLL
        ) {
          this.error(
            ws,
            "voter_limit",
            "This poll has reached its voting-session limit.",
          );
          return;
        }
        // Fingerprints and other caller-supplied identities have no authority.
        this.votes[session.participantId] = input.optionId as string;
        await this.persistPoll();
        this.sendChoice(ws);
        this.broadcastPoll();
        return;
      }
      if (input.type !== "reaction" || !singleEmoji(input.emoji)) {
        this.error(ws, "invalid_reaction", "Send a single emoji.");
        return;
      }
      const emoji = input.emoji.normalize("NFC");
      if (
        !Object.hasOwn(this.counts, emoji) &&
        Object.keys(this.counts).length >= MAX_REACTION_KEYS
      ) {
        this.error(
          ws,
          "reaction_limit",
          "This room has reached its custom reaction limit.",
        );
        return;
      }
      this.counts[emoji] = Math.min(
        (this.counts[emoji] ?? 0) + 1,
        Number.MAX_SAFE_INTEGER,
      );
      await this.ctx.storage.put("leaderboard", this.counts);
      // Broadcast a canonical bounded payload, never arbitrary extra JSON fields.
      this.broadcast({
        type: "reaction",
        emoji,
        reactionId: crypto.randomUUID(),
        sentAt: Date.now(),
      });
      this.scheduleLeaderboard();
    });
  }

  private session(ws: WebSocket): Session | null {
    const value = ws.deserializeAttachment() as Session | null;
    if (
      !value ||
      value.version !== 1 ||
      value.roomKey !== this.room?.hostHash ||
      !["host", "web", "macos"].includes(value.role)
    )
      return null;
    return value;
  }
  private async participantSigningKey() {
    if (!this.signingKey)
      this.signingKey = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(this.room!.participantKey),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign", "verify"],
      );
    return this.signingKey;
  }
  private async issueParticipantToken() {
    const nonce = token();
    const signature = await crypto.subtle.sign(
      "HMAC",
      await this.participantSigningKey(),
      new TextEncoder().encode(nonce),
    );
    return `${nonce}.${Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
  }
  private async validParticipantToken(value: unknown) {
    if (typeof value !== "string") return false;
    const match = /^([a-f0-9]{64})\.([a-f0-9]{64})$/.exec(value);
    if (!match) return false;
    const signature = Uint8Array.from(match[2]!.match(/../g)!, (byte) =>
      parseInt(byte, 16),
    );
    return crypto.subtle.verify(
      "HMAC",
      await this.participantSigningKey(),
      signature,
      new TextEncoder().encode(match[1]!),
    );
  }
  private async authorized(value: unknown, expected: string) {
    return (
      typeof value === "string" &&
      TOKEN.test(value) &&
      (await hash(value)) === expected
    );
  }
  private async acceptMessage(
    ws: WebSocket,
    session: Session | null,
    type: string,
  ) {
    // Limits survive object eviction: per-connection counters are attachments,
    // and room-wide counters are a single bounded storage record.
    const now = Date.now();
    const state =
      session?.rate ??
      (ws.deserializeAttachment() as { pendingRate?: Rate } | null)
        ?.pendingRate ??
      rate();
    if (now - state.start >= 1000) Object.assign(state, rate());
    const roomRate = (await this.ctx.storage.get<Rate>("rate")) ?? rate();
    if (now - roomRate.start >= 1000) Object.assign(roomRate, rate());
    if (
      state.messages >= 30 ||
      roomRate.messages >= 240 ||
      (type === "reaction" &&
        (state.reactions >= 12 || roomRate.reactions >= 60)) ||
      (type === "poll-vote" && (state.votes >= 5 || roomRate.votes >= 120))
    ) {
      this.error(
        ws,
        "rate_limited",
        "Too many requests. Try again in a moment.",
      );
      return false;
    }
    state.messages++;
    roomRate.messages++;
    if (type === "reaction") {
      state.reactions++;
      roomRate.reactions++;
    }
    if (type === "poll-vote") {
      state.votes++;
      roomRate.votes++;
    }
    if (session) {
      session.rate = state;
      ws.serializeAttachment(session);
    } else ws.serializeAttachment({ pendingRate: state });
    await this.ctx.storage.put("rate", roomRate);
    return true;
  }
  private validPoll(input: Input) {
    if (
      !text(input.pollId, 64) ||
      !text(input.question, 240) ||
      !Number.isInteger(input.durationMs) ||
      (input.durationMs as number) < 1000 ||
      (input.durationMs as number) > ROOM_LIFETIME_MS ||
      !Array.isArray(input.options) ||
      input.options.length < 2 ||
      input.options.length > 12
    )
      return false;
    const ids = new Set<string>();
    for (const option of input.options) {
      if (
        !object(option) ||
        !text(option.id, 64) ||
        !text(option.label, 80) ||
        ids.has(option.id)
      )
        return false;
      ids.add(option.id);
    }
    // Drop extra fields instead of retaining attacker-sized object graphs.
    input.options = input.options.map((option) => ({
      id: option.id,
      label: option.label.trim(),
    }));
    return true;
  }
  private async persistPoll() {
    if (this.poll) await this.ctx.storage.put("poll", this.poll);
    else await this.ctx.storage.delete("poll");
    await this.ctx.storage.put("poll-votes", this.votes);
  }
  private tally() {
    const counts: Record<string, number> = Object.create(null);
    for (const option of Object.values(this.votes))
      counts[option] = (counts[option] ?? 0) + 1;
    return counts;
  }
  private sendPoll(ws: WebSocket) {
    const role = this.session(ws)?.role;
    const poll = this.poll ? { ...this.poll } : null;
    if (poll && (role === "host" || role === "macos"))
      poll.tally = this.tally();
    this.send(ws, { type: "poll-state", poll });
  }
  private sendChoice(ws: WebSocket) {
    const id = this.session(ws)?.participantId;
    const optionId = id ? this.votes[id] : undefined;
    if (this.poll && optionId)
      this.send(ws, { type: "vote-accepted", pollId: this.poll.id, optionId });
  }
  private broadcastPoll() {
    for (const ws of this.ctx.getWebSockets()) this.sendPoll(ws);
  }
  private sendLeaderboard(ws: WebSocket) {
    const top = Object.entries(this.counts)
      .filter(([, count]) => count > 0)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 5);
    this.send(ws, { type: "leaderboard", counts: Object.fromEntries(top) });
  }
  private scheduleLeaderboard() {
    if (this.leaderboardScheduled) return;
    this.leaderboardScheduled = true;
    setTimeout(() => {
      this.leaderboardScheduled = false;
      for (const ws of this.ctx.getWebSockets()) this.sendLeaderboard(ws);
    }, 100);
  }
  private broadcastPresence() {
    const ids = new Set(
      this.ctx
        .getWebSockets()
        .map((ws) => this.session(ws)?.participantId)
        .filter(Boolean),
    );
    this.broadcast({ type: "presence", connected: ids.size });
  }
  private send(ws: WebSocket, message: unknown) {
    try {
      ws.send(JSON.stringify(message));
    } catch {
      /* The peer may have closed. */
    }
  }
  private broadcast(message: unknown) {
    for (const ws of this.ctx.getWebSockets()) this.send(ws, message);
  }
  private error(ws: WebSocket, code: string, message: string) {
    this.send(ws, { type: "protocol-error", code, message });
  }
  webSocketClose() {
    this.broadcastPresence();
  }
  webSocketError() {
    this.broadcastPresence();
  }
  private async live() {
    if (!this.room) return false;
    if (Date.now() < this.room.expiresAt) return true;
    await this.expire();
    return false;
  }
  private async expire() {
    this.broadcast({
      type: "protocol-error",
      code: "room_expired",
      message: "This room has expired. Ask the host for a new invitation.",
    });
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(1008, "Room expired");
      } catch {}
    }
    this.room = null;
    this.signingKey = null;
    this.counts = freshCounts();
    this.poll = null;
    this.votes = Object.create(null);
    await this.ctx.storage.deleteAll();
    await this.ctx.storage.deleteAlarm();
  }
  private async scheduleAlarm() {
    if (!this.room) return;
    await this.ctx.storage.setAlarm(
      this.poll?.status === "active"
        ? Math.min(this.room.expiresAt, this.poll.endAt)
        : this.room.expiresAt,
    );
  }
  async alarm() {
    await this.ready;
    await this.ctx.blockConcurrencyWhile(async () => {
      if (!(await this.live())) return;
      if (this.poll?.status === "active" && Date.now() >= this.poll.endAt) {
        this.poll.status = "complete";
        await this.persistPoll();
        this.broadcastPoll();
      }
      await this.scheduleAlarm();
    });
  }
}

export default {
  async fetch(request: Request, env: Env) {
    const pathname = new URL(request.url).pathname;
    if (pathname === "/rooms" && request.method === "OPTIONS")
      return new Response(null, { status: 204, headers: cors });
    if (pathname === "/rooms" && request.method === "POST") {
      for (let attempt = 0; attempt < 4; attempt++) {
        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        const roomId = Array.from(
          crypto.getRandomValues(new Uint8Array(6)),
          (byte) => alphabet[byte % alphabet.length],
        ).join("");
        const room: RoomCreatedMessage = {
          roomId,
          hostToken: token(),
          displayToken: token(),
          expiresAt: Date.now() + ROOM_LIFETIME_MS,
        };
        const id = env.ROOMS.idFromName(roomId);
        const response = await env.ROOMS.get(id).fetch(
          new Request("https://room.internal/internal/create", {
            method: "POST",
            body: JSON.stringify(room),
          }),
        );
        if (response.status !== 409) return response;
      }
      return json({ error: "Could not allocate a room. Try again." }, 503);
    }
    const match = /^\/rooms\/([A-Z0-9]{6})$/.exec(pathname);
    if (!match || request.headers.get("Upgrade")?.toLowerCase() !== "websocket")
      return json({ error: "Not found" }, 404);
    return env.ROOMS.get(env.ROOMS.idFromName(match[1]!)).fetch(request);
  },
};
