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
- Menu-bar controls for selecting a room code, disconnecting, and hiding the overlay

From the menu-bar peanut icon, choose **Connect to Room…** and enter the room code shared by the host. The selected room is saved locally and restored on the next launch. Choose **Disconnect** to clear the saved room.

The WebSocket URL is configured in `Sources/PeanutGallery/ReactionSocket.swift` for the deployed realtime Worker.

`PeanutGallery.xcodeproj` is retained as an optional IDE project for machines that later have full Xcode installed.
