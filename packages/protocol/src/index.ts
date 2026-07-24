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

export type ClientMessage = ReactionMessage | JoinRoomMessage
