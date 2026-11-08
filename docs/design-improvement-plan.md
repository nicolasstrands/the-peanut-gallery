# Peanut Gallery design improvement plan

Reviewed 8 November 2026 using the Emil Kowalski design engineering skill.

Evidence: the three Nuxt pages, shared header/layout/styles, Nuxt configuration, the SwiftPM overlay and leaderboard source, and the existing `room-live-preview.png`. The screenshot is an existing reference, not a verified rendering of the current checkout. No live browser, phone, or native-app evaluation was performed. Findings below distinguish code observations from proposed design choices.

## Direction

Keep the warm charcoal, peanut yellow, expressive wordmark, and tactile reaction buttons. Make the product feel like a small, well-made audience remote: playful at the point of reaction, calm everywhere else. Avoid adding gradients, floating decorations, or motion simply to fill empty space.

The highest-value work is layout and hierarchy before animation. The host needs sharing and room controls; the audience needs immediate, reliable reactions; the projected overlay needs legibility without obscuring the presentation.

## Visual and interaction review

| Before | After | Why |
| --- | --- | --- |
| `Header.vue` has unscoped `h1` rules; the logo itself is an `h1`. Brand letter markup is duplicated on the homepage. | Extract one wordmark component with scoped styles; use a link with an accessible brand name, and reserve the page heading for its task. | Prevent accidental typography coupling and keep the brand consistent. |
| Balsamiq Sans is used across body text and controls; create-room also declares Inter on `body`. | Keep Rammetto One for the wordmark and selective headings. Trial a system sans for utility labels, forms, statuses, and room codes while retaining Balsamiq for playful copy. | Establish a clearer hierarchy without erasing the identity. Treat the font change as a visual experiment, not a prerequisite. |
| Shared layout uses an absolute header, `min-h-screen`, horizontal padding, and a shell with `min-width: 90vw`. | Put the header in normal flow; use `min-height: 100svh`, a bounded content width, flexible gutters, and explicit compact-height behavior. | Reduce the risk of overlap and horizontal overflow when content grows or the mobile keyboard opens. |
| The host card combines a QR code, status, code, copy/regenerate icons, two device links, and a small “Toggle Poll” control. | Give sharing its own hierarchy: QR, readable code, “Copy invite link,” then device actions. Place “Create poll” in a distinct host-tools area. | Prioritize the host's main job and make polling discoverable. Preserve code copy as a secondary action. |
| Regenerate sits beside copy with similar visual weight and immediately replaces the room. | Move “Create new room” into a secondary action area; explain that participants must use a new invitation before committing. | Avoid accidental disruption from a small icon beside a frequent action. |
| Opening the poll adds a flex sibling and can shrink the room card; `togglePoll` also scrolls smoothly. | Keep the sharing card width stable. Use a two-column layout only when both panels fit at useful widths; otherwise stack the poll below with deliberate focus placement. | Make the layout predictable instead of animating a cramped intermediate state. |
| Host poll options are entered in a multiline textarea and results are plain label/count rows. | Use labeled answer rows with add/remove controls, a compact duration control, and results with aligned counts plus proportional bars. | Make editing and comparing answers easier. Show vote counts alongside percentages. |
| The reaction deck has four grid columns, intrinsic button sizing, and only maximum button dimensions. | Define an explicit bounded deck width and equal `minmax(0, 1fr)` tracks; give every tile `width: 100%` and a consistent aspect ratio. Start with four columns and adapt only if narrow-width tests require it. | Make the deck read as a designed control surface and avoid sizing the empty custom slot differently from emoji tiles. |
| The empty custom reaction is a low-opacity blank button; editing uses `window.prompt` and `window.alert`. | Show a plus icon and “Custom” cue; open a small labeled editor with inline validation, Save, and Cancel. Give reset a minimum 44px hit area, even if its visible icon stays small. | Make the feature discoverable and keep its styling and error handling inside the product. |
| Connection feedback is a pill with an endlessly pulsing dot; disconnected states use generic presence copy. | Use a quiet static connected indicator, explicit “Connecting…” / “Reconnecting…” / “Unable to connect” text, and a retry path when appropriate. Keep room identity visible on the deck. | Reassure users without competing with reactions; explain why buttons are unavailable. |
| `react()` sends immediately, while the local received-reaction list is hidden. | Keep immediate tactile press feedback. If a sent confirmation is added, distinguish local dispatch from delivery and use real acknowledgement for delivery claims. | Feedback should be truthful; a pressed button does not prove the overlay received a reaction. |
| Poll completion still uses “Cast your vote,” shows a zero timer, and disables choices. | Introduce explicit active, selected, completed, and dismissed states. Completed copy: “Voting closed,” with selection retained and results shown only if supported by the audience payload. | Make the current state understandable. The join-page poll type currently lacks tally data. |
| Focus styling is explicit on host icon buttons and form fields, but not consistently across all actions; standard emoji buttons have no explicit accessible action names. | Add shared `:focus-visible` treatment, meaningful labels such as “Send applause,” selected-state semantics, and concise live announcements for status changes. | Make the same interface usable by keyboard and assistive technology. Avoid announcing every incoming reaction. |
| Viewport configuration disables zoom; poll inputs are 15px. | Allow browser zoom and use at least 16px form text on mobile. Include safe-area spacing. | Preserve readability and reduce disruptive input zoom behavior. |

## Motion specification

Use CSS/Vue transitions for web interactions; no animation library is required for this scope. Default entrance curve: `cubic-bezier(0.23, 1, 0.32, 1)`. Gate hover effects behind `(hover: hover) and (pointer: fine)`. Keyboard navigation and repeated keyboard-triggered actions should remain immediate.

| Before | After | Why |
| --- | --- | --- |
| Reaction buttons alter bottom border width on press; homepage CTA uses `transition-all` and changes border thickness. | Keep geometry fixed and create depth with a shadow or pseudo-element. On pointer press, translate 2px and optionally scale to 0.98; release in 100–140ms. | Preserve the tactile character without changing layout. Rapid presses must retarget from the current state. |
| Shared wordmark view transition lasts 420ms. | Test 180–220ms, with no unrelated page-wide fade; skip for reduced motion and keyboard navigation. Remove it if the title travel distracts from room creation. | This is a small utility flow; brand continuity should not slow it down. |
| Connection dots pulse indefinitely with animated box-shadow. | Remove the connected pulse. Optional 120ms opacity change once when the connection state changes. | Stable connection is background information, not a continuing event. |
| Host poll entrance combines a Vue transition with smooth scrolling and layout changes. | First stabilize layout; then use opacity plus 6–8px vertical movement, 180ms in / 120ms out. Coordinate focus and any scroll so the user experiences one transition. Keyboard opening and reduced motion should use immediate scroll. | Explain the appearance of a new tool without moving several unrelated surfaces. |
| Audience reaction and poll content switch with `v-if`. | For server-driven poll arrival, use a short 120–160ms content swap and at most 6px movement. Never delay option interaction. Preserve outer spacing where practical rather than animating arbitrary height. | Explain a mode change while respecting the interruption during a live event. |
| Copy icon switches directly to a checkmark. | Keep its hit area fixed; crossfade icon content over 100–120ms, with a polite “Copied” announcement. Show an inline fallback if clipboard access fails. | Small confirmation is useful; bounce and confetti are unnecessary. |
| Poll timer updates every 250ms using a conic gradient; no reduced-motion policy exists in the reviewed web styles. | Keep digits instantaneous and tabular. Do not animate each count or vote. If adding a progress bar, use `scaleX` on a dedicated layer. Under reduced motion, remove translation, scaling, shared-element travel, and smooth scrolling; retain brief opacity changes only where useful. | Keep functional data legible and avoid painting decorative motion continuously. |
| Native emoji rise across the desktop with random size, drift, and frame-based speed; the pool is capped at 160 particles. | Keep this signature effect. Test a restrained 40–64px size range and use elapsed-time movement so speed stays consistent under load. Offer a reduced-motion mode with stationary short fades and a lower visible cap. | The reaction overlay is the product's purposeful animation. Protect presentation readability and accessibility. |
| Native leaderboard sorts rows on updates and uses fixed drawing rectangles. | Keep counts immediate; prefer stable row order while voting, with one deliberate final ranking. Improve long-question wrapping and answer truncation before considering 150–180ms result-panel fades. | Frequent ranking motion makes live information harder to follow; text handling matters more. |

Avoid per-letter logo entrances, staggered reaction tiles, bouncing poll answers, animated countdown digits, and extra particles on the audience's phone. The desktop already provides the celebratory payoff.

## Implementation sequence

1. **Foundation and legibility.** Scope header styles, extract the wordmark, consolidate colors/type/spacing/radii, stabilize the shared layout, restore zoom, and add consistent focus and reduced-motion handling. Keep the current palette: canvas `#17130f`, surface `#241e1a`, accent `#f6b73c`, primary text `#fff4df`; measure contrast before finalizing muted text. Deliverable: coherent home, host, and audience screenshots at narrow and wide widths.
2. **Audience deck.** Make tile geometry explicit, add accessible reaction labels, make Custom visible, replace native dialogs, and clarify connection and completed-poll states. Deliverable: a thumb-friendly deck with predictable controls in every connection state.
3. **Host workspace.** Prioritize QR/code/invite copying, separate new-room creation, stabilize poll layout, improve the poll editor, and align result counts/bars. Deliverable: sharing remains useful while a poll is configured or running.
4. **Motion polish.** Apply the small motion vocabulary above after layout is stable; remove ambient pulsing and broad transitions. Deliverable: motion communicates press, confirmation, or mode changes and remains interruptible.
5. **Native pass.** Match the warm accent and surface hierarchy while retaining native settings controls. Verify overlay density, elapsed-time motion, reduced-motion behavior, long poll text, and leaderboard stability on the actual app.

Each phase should be independently reviewable. Start with phases 1–2: they affect every participant and provide more value than adding animation first.

## Validation and acceptance

- Capture home, host, deck, poll editor, active vote, selected vote, and closed vote at 320, 390, 768, and 1440px widths. Check short laptop windows, phone landscape, 200% zoom, and the mobile keyboard. No header overlap or horizontal page scrolling.
- Exercise long questions, 12 options, long unbroken option labels, six-character room codes, large counts, empty rooms, QR loading failure, clipboard failure, and reconnecting states. Reserve QR space so loading does not shift the card.
- Verify full keyboard navigation, visible focus, editor focus return, meaningful labels, selected-state semantics, and reduced motion. Check mobile tap targets on hardware.
- Send rapid repeated reactions and change poll state during transitions. No queued press animations, blocked controls, misleading success states, or repeated entrance sequences.
- Inspect animations at normal speed and slowed playback. Test native reaction bursts near the existing cap without obscuring presentation content. Native runtime behavior requires device verification; this review did not run it.
- At the time of the initial review, no app code had been changed. The implementation and checks below were completed afterward.


## Implementation completed — 8 November 2026

Implemented the shared wordmark and design tokens; normal-flow responsive layout; system utility typography; revised homepage; QR/invite sharing hierarchy and clipboard/QR fallbacks; separate new-room confirmation; stable host poll workspace; individual answer editing; result bars and counts; equal reaction tiles; inline custom emoji editor with validation and focus return; explicit poll completion and connection states; accessible names, selection semantics, focus styling, zoom support, and reduced-motion handling.

Motion uses CSS transform/opacity transitions: 120ms press feedback and 180ms entrance / 120ms exit for occasional panels. Removed the perpetual connection pulse and shared-title travel. Keyboard input disables transitions; reduced motion removes positional feedback. Poll mode changes mount new controls immediately while old content leaves inert.

The native overlay now measures elapsed time, stops its timer when idle, redraws when the last particle expires, uses a restrained 40–64pt emoji range, and follows the macOS Reduce Motion preference with stationary fades and a 12-particle limit. The native poll panel has a warmer surface, wrapped/truncated questions, truncated answer labels, stable answer order while voting, final ranking, and a disclosure when only five of the available answers are shown.

Validation completed:

- `pnpm --filter web lint`: passed. Added the missing Nuxt TypeScript project references and development tooling. Corrected two existing sound-plugin API/type errors exposed by typechecking.
- `pnpm --filter web build`: passed for the Cloudflare target.
- `swift build --package-path apps/macos-overlay`: passed. The local linker reported missing CommandLineTools search-path warnings, but produced the executable.
- Chromium against the local Nuxt server and actual local Wrangler Durable Object: invite clipboard contents, reaction broadcast, custom emoji validation/save/focus, poll creation/voting/tally/expiry/dismissal, and new-room confirmation all passed with no captured browser errors.
- Host and audience overflow checks at 320, 390, 768, and 1440px passed, including 12 answers, a 240-character question, and long answer labels.
- QR request failure, clipboard rejection, unavailable WebSocket transport, custom-editor Escape focus return, keyboard modality, and browser reduced-motion editor checks passed.
- Axe scans within main content reported no violations in eight states: home, host editor with clipboard fallback, reaction deck, active poll, host results, closed poll, custom editor, and reconnecting deck. This is an automated check, not a claim of full accessibility compliance.
- Offscreen AppKit rendering exercised the native poll view with long text and 12 options, plus a 200-reaction burst and particle expiry. Rendered images were visually inspected.

Remaining manual validation: physical phone/keyboard/safe-area behavior, Safari, browser zoom at 200%, assistive-technology usability, real presentation readability under load, and macOS Reduce Motion toggling during an active session. Native settings retain native controls. Audience results remain host-controlled because the current audience protocol does not expose tally data.
