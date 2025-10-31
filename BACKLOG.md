# BACKLOG — Harmony Admin (initial)

Priority order (short-term):

1. Admin UI scaffold (tabs) — Dashboard, Event Creator, Content Editor, Media Library, Preview, Scheduler, Users
2. Event Creator — title, intent, reference time, timezone, startTimeUTC preview, publish toggle, save locally
3. Local persistence — save/load events in browser localStorage (done)
4. Firebase wiring — add Firebase web config (flutterfire configure), implement `firebase_service.dart` to publish events to Firestore
5. Media upload — support uploading to Firebase Storage and storing URLs on Event documents
6. Scheduler & Notice Board — define recurring slots and display upcoming events (reads from Firestore)
7. User Management — view users, suspend, delete comments (admin tools)
8. Post-Event Tools — QuoteLibrary, AI-generated drafts (stubs for Gemini)
9. CI / GitHub Actions — build web on push, optional deploy

Notes:
- Each backlog item can be converted into small issues/tickets and implemented incrementally.
- Current branch: `main` has a minimal scaffold and local persistence.
