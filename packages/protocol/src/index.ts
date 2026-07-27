export type ClientType = 'web' | 'host' | 'macos'

export type ReactionMessage = {
  type: 'reaction'
  emoji: string
  reactionId: string
  sentAt: number
}

export type JoinRoomMessage = {
  type: 'join-room'
  roomId: string
  clientType: ClientType
}

export type LeaderboardMessage = {
  type: 'leaderboard'
  counts: Record<string, number>
}

export type ClientMessage = ReactionMessage | JoinRoomMessage

export type ServerMessage = ReactionMessage | LeaderboardMessage
