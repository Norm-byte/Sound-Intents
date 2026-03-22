# BACKLOG — Harmony Admin (Current Focus: Media Library Stability)

## Immediate Priorities (Active Sprint)
1. **[CRITICAL] Media Library Stability & Bug Fixes**
   - [x] Fix "Ghost Images" where old images appear in new slots (Fixed via `key: ValueKey(item.id)`).
   - [x] Fix "Unresponsive Taps" on non-video items (Fixed via correct widget recycling).
   - [ ] **Verify stability fixes in running app.**
   - [ ] Test large media lists for performance regressions.

2. **Completed Features (Recent)**
   - [x] **Rich File Previews:** Added color-coded icons for PDF, DOC, PPT, XLS.
   - [x] **Smart Video Detection:** Auto-detects YouTube/MP4 and shows play button overlay.
   - [x] **WebImage Component:** Implemented `pointer-events: none` to prevent click blocking.

3. **Pending / Next Up**
   - [ ] **Full Integration Testing:** Ensure `_MediaCard` logic handles all edge cases (missing thumbnails, weird extensions).
   - [ ] **Code Cleanup:** Remove any remaining unused imports in `media_library_tab.dart`.
   - [ ] **Commit Changes:** Once verified, commit the stability fixes.

## General Backlog
1. Admin UI scaffold (tabs) — Dashboard, Event Creator, Content Editor, Media Library, Preview, Scheduler, Users
2. Event Creator — title, intent, reference time, timezone, startTimeUTC preview, publish toggle, save locally
3. Local persistence — save/load events in browser localStorage (done)
4. Firebase wiring — add Firebase web config (flutterfire configure), implement `firebase_service.dart` to publish events to Firestore
5. Media upload — support uploading to Firebase Storage and storing URLs on Event documents
6. Scheduler & Notice Board — define recurring slots and display upcoming events (reads from Firestore)
7. User Management — view users, suspend, delete comments (admin tools)
8. Post-Event Tools — QuoteLibrary, AI-generated drafts (stubs for Gemini)
9. CI / GitHub Actions — build web on push, optional deploy
10. Internationalization & Compliance (Post-v2)
    - [ ] Implement on-device message translation (Google ML Kit) for user chats.
    - [ ] Expand profanity/blocklist to support detailed per-locale filtering.
    - [ ] Implement "Report User" flow for full App Store/Play Store compliance.

Notes:
- Current branch: `main`
- Last Action: Applied widget recycling fix to `media_library_tab.dart`.
