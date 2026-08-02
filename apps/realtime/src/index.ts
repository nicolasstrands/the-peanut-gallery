import { DurableObject } from "cloudflare:workers";
import type {
  ClientType,
  ClientMessage,
  LeaderboardMessage,
  PollState,
  PollStateMessage,
  PresenceMessage,
  ReactionMessage,
} from "@peanut-gallery/protocol";

export interface Env {
  ROOMS: DurableObjectNamespace<ReactionRoom>;
}

export class ReactionRoom extends DurableObject<Env> {
  private static readonly maxReactionsPerSecond = 120;
  private static readonly leaderboardBroadcastIntervalMs = 100;
  private counts: Record<string, number> = {};
  private poll: PollState | null = null;
  private pollVotes: Record<string, string> = {};
  private readonly countsLoaded: Promise<void>;
  private readonly reactionTimestamps = new WeakMap<WebSocket, number[]>();
  private readonly clientTypes = new WeakMap<WebSocket, ClientType>();
  private leaderboardBroadcastScheduled = false;
  private hostSocket: WebSocket | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.countsLoaded = ctx.storage
      .get<Record<string, number>>("leaderboard")
      .then((counts) => {
        if (counts) this.counts = counts;
      })
      .then(async () => {
        this.poll = (await ctx.storage.get<PollState>("poll")) ?? null;
        this.pollVotes = (await ctx.storage.get<Record<string, string>>("poll-votes")) ?? {};
      });
  }

  async fetch(request: Request) {
    if (request.headers.get("Upgrade") !== "websocket")
      return new Response("Expected WebSocket", { status: 426 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server);
    this.broadcastPresence();
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    await this.countsLoaded;
    if (typeof message !== "string") return;

    let parsed: ClientMessage;
    try {
      parsed = JSON.parse(message) as ClientMessage;
    } catch {
      return;
    }

    if (parsed.type === "join-room") {
      this.clientTypes.set(ws, parsed.clientType);
      ws.serializeAttachment({ clientType: parsed.clientType });
      if (parsed.clientType === "host" && !this.hostSocket) this.hostSocket = ws;
      this.sendLeaderboard(ws);
      this.sendPollState(ws);
      this.broadcastPresence();
      return;
    }

    if (parsed.type === "presence-sync") {
      this.broadcastPresence();
      return;
    }

    if (parsed.type === "poll-start") {
      if (!this.isHost(ws) || this.poll || !this.hasParticipants() || !this.isValidPollStart(parsed)) return;
      this.poll = {
        id: parsed.pollId,
        question: parsed.question.trim(),
        options: parsed.options,
        startAt: Date.now(),
        endAt: Date.now() + parsed.durationMs,
        status: "active",
      };
      this.pollVotes = {};
      await this.persistPoll();
      await this.ctx.storage.setAlarm(this.poll.endAt);
      this.broadcastPollState();
      return;
    }

    if (parsed.type === "poll-vote") {
      if (!this.poll || this.poll.status !== "active" || parsed.pollId !== this.poll.id) return;
      if (Date.now() >= this.poll.endAt || !this.isValidPollVote(parsed)) return;
      if (!this.poll.options.some((option) => option.id === parsed.optionId)) return;
      this.pollVotes[await this.fingerprintKey(parsed.fingerprint)] = parsed.optionId;
      await this.persistPoll();
      this.broadcastPollState();
      return;
    }

    if (parsed.type === "poll-dismiss") {
      // Dismissal must continue to work if the Durable Object was rehydrated
      // and the original host WebSocket reference is no longer in memory.
      if (this.clientType(ws) !== "host" || !this.poll || parsed.pollId !== this.poll.id) return;
      this.poll = null;
      this.pollVotes = {};
      await this.persistPoll();
      await this.ctx.storage.deleteAlarm();
      this.broadcastPollState();
      return;
    }

    if (parsed.type !== "reaction" || !this.isValidReaction(parsed)) return;
    if (!this.acceptReaction(ws)) return;

    this.counts[parsed.emoji] = (this.counts[parsed.emoji] ?? 0) + 1;
    await this.ctx.storage.put("leaderboard", this.counts);

    // getWebSockets() is hibernation-safe; an in-memory Set would be reset
    // when Cloudflare hibernates this Durable Object.
    for (const session of this.ctx.getWebSockets()) {
      session.send(message);
    }
    this.scheduleLeaderboardBroadcast();
  }

  webSocketClose(ws: WebSocket) {
    this.clientTypes.delete(ws);
    if (this.hostSocket === ws) this.hostSocket = null;
    this.broadcastPresence();
  }

  webSocketError(ws: WebSocket) {
    this.clientTypes.delete(ws);
    if (this.hostSocket === ws) this.hostSocket = null;
    this.broadcastPresence();
  }

  private sendLeaderboard(ws: WebSocket) {
    const message: LeaderboardMessage = {
      type: "leaderboard",
      counts: this.counts,
    };
    ws.send(JSON.stringify(message));
  }

  private sendPollState(ws: WebSocket) {
    const message = this.pollStateMessage(this.clientType(ws));
    ws.send(JSON.stringify(message));
  }

  private broadcastPollState() {
    for (const session of this.ctx.getWebSockets()) {
      try {
        session.send(JSON.stringify(this.pollStateMessage(this.clientType(session))));
      } catch {
        // Ignore sessions that are closing while we broadcast.
      }
    }
  }

  private pollStateMessage(clientType?: ClientType): PollStateMessage {
    if (!this.poll) return { type: "poll-state", poll: null };
    const poll = { ...this.poll };
    if (clientType === "host" || clientType === "macos") {
      poll.tally = this.tallyPoll();
    }
    return { type: "poll-state", poll };
  }

  private tallyPoll() {
    return Object.values(this.pollVotes).reduce<Record<string, number>>((tally, optionId) => {
      tally[optionId] = (tally[optionId] ?? 0) + 1;
      return tally;
    }, {});
  }

  private async persistPoll() {
    if (this.poll) await this.ctx.storage.put("poll", this.poll);
    else await this.ctx.storage.delete("poll");
    await this.ctx.storage.put("poll-votes", this.pollVotes);
  }

  private isHost(ws: WebSocket) {
    if (this.clientType(ws) !== "host") return false;
    if (this.hostSocket === ws) return true;

    // The Durable Object may be rehydrated between messages. In that case the
    // in-memory socket reference is gone, so recover ownership from the first
    // currently connected host client in this room.
    if (!this.hostSocket || !this.ctx.getWebSockets().includes(this.hostSocket)) {
      this.hostSocket = ws;
      return true;
    }
    return false;
  }

  private hasParticipants() {
    return this.ctx
      .getWebSockets()
      .some((session) => this.clientType(session) === "web");
  }

  private clientType(ws: WebSocket) {
    const inMemoryType = this.clientTypes.get(ws);
    if (inMemoryType) return inMemoryType;
    const attachment = ws.deserializeAttachment() as { clientType?: ClientType } | null;
    return attachment?.clientType;
  }

  private isValidPollStart(message: ClientMessage): message is Extract<ClientMessage, { type: "poll-start" }> {
    return message.type === "poll-start" &&
      typeof message.pollId === "string" && message.pollId.length > 0 &&
      typeof message.question === "string" && message.question.trim().length > 0 && message.question.length <= 240 &&
      Number.isInteger(message.durationMs) && message.durationMs >= 1000 && message.durationMs <= 86400000 &&
      Array.isArray(message.options) && message.options.length >= 2 && message.options.length <= 12 &&
      message.options.every((option) => typeof option.id === "string" && option.id.length > 0 &&
        typeof option.label === "string" && option.label.trim().length > 0 && option.label.length <= 80);
  }

  private isValidPollVote(message: ClientMessage): message is Extract<ClientMessage, { type: "poll-vote" }> {
    return message.type === "poll-vote" &&
      typeof message.fingerprint === "string" && message.fingerprint.length >= 8 && message.fingerprint.length <= 512 &&
      typeof message.optionId === "string" && message.optionId.length > 0;
  }

  private async fingerprintKey(fingerprint: string) {
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(fingerprint));
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  }

  async alarm() {
    await this.countsLoaded;
    if (!this.poll || this.poll.status !== "active") return;
    if (Date.now() < this.poll.endAt) {
      await this.ctx.storage.setAlarm(this.poll.endAt);
      return;
    }
    this.poll.status = "complete";
    await this.persistPoll();
    this.broadcastPollState();
  }

  private broadcastPresence() {
    const connected = this.ctx
      .getWebSockets()
      .reduce(
        (total, session) =>
          total + (this.clientType(session) === "web" ? 1 : 0),
        0,
      );
    const message: PresenceMessage = { type: "presence", connected };
    const payload = JSON.stringify(message);
    for (const session of this.ctx.getWebSockets()) {
      try {
        session.send(payload);
      } catch {
        // Ignore sessions that are closing while we broadcast.
      }
    }
  }

  private scheduleLeaderboardBroadcast() {
    if (this.leaderboardBroadcastScheduled) return;
    this.leaderboardBroadcastScheduled = true;

    setTimeout(() => {
      this.leaderboardBroadcastScheduled = false;
      for (const session of this.ctx.getWebSockets()) {
        this.sendLeaderboard(session);
      }
    }, ReactionRoom.leaderboardBroadcastIntervalMs);
  }

  private acceptReaction(ws: WebSocket) {
    const now = Date.now();
    const timestamps = this.reactionTimestamps.get(ws) ?? [];
    const recent = timestamps.filter((timestamp) => now - timestamp < 1000);

    if (recent.length >= ReactionRoom.maxReactionsPerSecond) {
      this.reactionTimestamps.set(ws, recent);
      return false;
    }

    recent.push(now);
    this.reactionTimestamps.set(ws, recent);
    return true;
  }

  private isValidReaction(message: ClientMessage): message is ReactionMessage {
    return (
      message.type === "reaction" &&
      typeof message.emoji === "string" &&
      message.emoji.trim().length > 0 &&
      message.emoji.length <= 32
    );
  }
}

export default {
  async fetch(request: Request, env: Env) {
    const roomId =
      new URL(request.url).pathname.split("/").filter(Boolean).pop() ??
      "default";
    const id = env.ROOMS.idFromName(roomId);
    return env.ROOMS.get(id).fetch(request);
  },
};
