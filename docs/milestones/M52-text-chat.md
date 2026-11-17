# M52 Text chat

Status: Planned.

## Goal

A chat box for the party, with emoji. Enter opens it, messages fade after a while, and the log scrolls back.

## Depends on

M51 (shares the party message RPC path). Independent of combat.

## Design

- A reliable RPC through the server: sender, text (limited length, control characters stripped), time. The server relays to everyone in the world and keeps the last messages for late joiners.
- Emoji: typed as `:name:` with a small picker; drawn from one open emoji font (Noto Emoji, SIL OFL: record it in `docs/RESOURCES.md`) so they look the same on every platform.
- System lines in the same box: joined, left, died (and to what), boss fallen, shrine lit.
- While the box is open the game takes no movement input; Esc closes it.
- Settings: chat on or off, fade time, text size. No profanity filter (friends only).

## Tasks

1. **Chat (Sonnet).** `net/net.gd`, new `client/chat_box.gd`, `client/game_client.gd` (input focus), `client/menus.gd` theme; tests for length, stripping and relay.
2. **Emoji and system lines, close (Sonnet).** The font, the picker, system lines from existing events, settings, play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Whispers and channels. Chat history saved to disk. Moderation tools.

## Pitfalls

- Input focus: a typed key must never also swing the sword; check with the pause menu's handling.
- A color emoji font is large: vendor only what is needed and check the export size.
- Text from other players is untrusted: no BBCode from chat in a `RichTextLabel`.
