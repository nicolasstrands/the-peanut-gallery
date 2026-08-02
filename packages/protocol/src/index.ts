export type ClientType = "web" | "host" | "macos";

export type PollStatus = "active" | "complete";

export type PollOption = {
  id: string;
  label: string;
};

export type PollState = {
  id: string;
  question: string;
  options: PollOption[];
  startAt: number;
  endAt: number;
  status: PollStatus;
  tally?: Record<string, number>;
};

export type ReactionMessage = {
  type: "reaction";
  emoji: string;
  reactionId: string;
  sentAt: number;
};

export type JoinRoomMessage = {
  type: "join-room";
  roomId: string;
  clientType: ClientType;
};

export type PresenceSyncMessage = {
  type: "presence-sync";
};

export type PollStartMessage = {
  type: "poll-start";
  pollId: string;
  question: string;
  options: PollOption[];
  durationMs: number;
};

export type PollVoteMessage = {
  type: "poll-vote";
  pollId: string;
  optionId: string;
  fingerprint: string;
};

export type PollDismissMessage = {
  type: "poll-dismiss";
  pollId: string;
};

export type LeaderboardMessage = {
  type: "leaderboard";
  counts: Record<string, number>;
};

export type PresenceMessage = {
  type: "presence";
  connected: number;
};

export type PollStateMessage = {
  type: "poll-state";
  poll: PollState | null;
};

export type ClientMessage =
  | ReactionMessage
  | JoinRoomMessage
  | PresenceSyncMessage
  | PollStartMessage
  | PollVoteMessage
  | PollDismissMessage;

export type ServerMessage =
  | ReactionMessage
  | LeaderboardMessage
  | PresenceMessage
  | PollStateMessage;
