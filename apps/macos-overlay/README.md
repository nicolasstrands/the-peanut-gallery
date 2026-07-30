# Peanut Gallery macOS Overlay

This is a Swift Package Manager executable, so Xcode is not required for the normal development loop. Open the folder in VS Code/Cursor or use the terminal:

```bash
swift build
swift run
```

It contains a native AppKit menu-bar application with:

- Transparent borderless `NSPanel` per connected display
- `ignoresMouseEvents = true` so desktop and app clicks pass through
- Floating window level without keyboard focus
- `URLSessionWebSocketTask` connection to the realtime Worker
- A bounded emoji particle animation view
- A click-through floating room leaderboard showing the top five reactions
- Menu-bar controls for selecting a room code, disconnecting, and hiding the overlay

The app defaults to the production Peanut Gallery services, so a normal install can launch and join a room immediately.

If you need local development or a self-hosted deployment, open **Settings…** from the menu bar and enable **Developer settings**. That reveals custom realtime server and web UI overrides for this Mac only, while leaving the default experience pointed at the Arcodelabs endpoints.

From the menu-bar peanut icon, choose **Settings…** and enter the room code shared by the host. The selected room is saved locally and restored on the next launch. Choose **Disconnect** to pause reconnecting without forgetting the room.

The leaderboard is shown by default and can be toggled with **Hide Leaderboard** in the menu bar.

The production WebSocket default is `wss://gallerybutter.arcodelabs.com`, and the production web UI default is `https://peanutgallery.arcodelabs.com`.

`PeanutGallery.xcodeproj` is retained as an optional IDE project for machines that later have full Xcode installed.
