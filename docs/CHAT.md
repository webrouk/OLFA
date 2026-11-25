# Chat system — ordering, sync, list order, paging, offline

| Requirement | How it is met | Where |
|---|---|---|
| **1. Message ordering & sequencing** | The database gives every message a per-conversation position `seq` (1, 2, 3 …) inside the insert, while it holds the conversation row lock. Two people sending at the same moment are serialised, so `seq` order = commit order = the order both people see. There are no gaps and no ties. `created_at` also moves strictly forward. A position can never change. The app sorts each thread by `seq`, and puts messages still on the phone after them, in the order they were written. | migration `20261125120000_chat_sequencing` (`olfa_message_sequence`), `mobile/.../domain/thread_order.dart` |
| **2. Real-time sync, no loss / no duplicates** | **No duplicates:** each message carries a client UUID (`clientMessageId`), unique per conversation and sender, so retries and the socket echo never create a second copy, and the app merges by that key. **No loss:** a jump in `seq` (a missed event) or a reconnect fetches exactly what is missing with `GET …/messages?afterSeq=N`. **Status sync:** "delivered" is acknowledged by the receiving phone (`delivered` socket event or `POST …/delivered`). "Read" is sent as `upToSeq` and respects the reciprocal read-receipt setting. Positions only move forward. | `messaging.module.ts` (`page`, `markDelivered`, `markRead`), `chat_controller.dart` |
| **3. Dynamic conversation sorting** | `conversations.last_message_at` is updated by the same trigger. On any new message (sent or received) the app updates that row's preview, time and unread count and moves it to the top straight away, without reloading. The list is always sorted latest message first, and a quiet server re-read reconciles after bursts. | `ConversationIndexController`, `byLatestActivity` |
| **4. Pagination & lazy loading** | The newest 30 messages load first. Older pages load when scrolling up, by position (`beforeSeq`). The full history is never loaded. Back at the newest messages, long threads keep only the latest 150 in memory. | `page()`, `loadOlder()`, `trimToRecent()` |
| **5. Offline queue & auto-reconnect** | Every message is written to the phone's disk *before* it is sent (write-ahead, atomic file replace), photos and voice files included. Offline messages show "waiting for network". They are sent by themselves, one conversation at a time and strictly in order: on reconnect, on returning to the app, at start-up, and on a back-off timer (3 s → 60 s). The same idempotency key is reused, so nothing is ever sent twice. A message the server refuses stays as "failed" with retry and delete. Socket.IO reconnects by itself. Rows have stable keys and only the open thread rebuilds, so the UI doesn't jank. | `mobile/.../data/outbox.dart` |

## API

- `GET /v1/conversations/:id/messages?beforeSeq=&afterSeq=&limit=` — items oldest → newest, each with `seq`. The response also has `lastSeq`, `peerDeliveredSeq` and `peerReadSeq` (null when read receipts are off).
- `POST /v1/conversations/:id/delivered {upToSeq}` — or socket `delivered`.
- Socket events:
  - `message:new` (message includes `seq`)
  - `message:delivered {conversationId, userId, upToSeq}`
  - `message:read {…, upToSeq}`

## Tests

- **DB:** `test/db/conversations_test.sh`, "message ordering" section. Two parallel sessions send 40 messages each. The checks: unique, gap-free positions; each sender's own order kept; time follows order; the list is latest first; positions are immutable; the read position only moves forward.
- **App:**
  - `test/features/thread_order_test.dart`: order, de-duplication, ticks, list order.
  - `test/features/outbox_test.dart`: offline → restart → in-order, exactly-once delivery; refused messages.
