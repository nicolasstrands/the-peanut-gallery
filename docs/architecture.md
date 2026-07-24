# Architecture

The web reaction deck and macOS overlay both connect to the same room Durable Object through secure WebSockets. One Durable Object instance represents one room and broadcasts validated reactions to all connected clients.

The overlay is click-through: it renders above the desktop but never handles mouse events, so desktop icons and application windows remain usable.
