# Harmony by Intent - Admin Operating Manual (V2)

## Overview
This Admin Panel is the control center for the "Harmony by Intent" ecosystem. It allows you to manage Global Events, Monetization Deals, User Safety, and Legal Compliance.

---

## 1. Dashboard ("Year Command Center")
The **Dashboard** is your primary workspace for scheduling.
*   **Vertical Cards**: Each card represents a week of the year (Week 1 - 52).
*   **Sync Button**: The Blue/Amber button on each card controls the visibility of that week's events on the User App.
    *   **Blue (Sync)**: All events are live and up-to-date.
    *   **Amber (Publish Drafts)**: You have made changes (Drafts) that are not yet live. Click to publish.
*   **Copy/Paste Workflow**:
    1.  Click the **Three Dots** menu on a source week (e.g., Week 10).
    2.  Select **Copy To Week...**.
    3.  Select the destination (e.g., Week 15).
    4.  The system copies all events to Week 15 as **Drafts**.
*   **Alerts**: The top of the dashboard displays urgent system alerts (e.g., "3 Flagged Messages").

## 2. Event Scheduler (Drafting)
Clicking a Week Card takes you to the **Scheduler**.
*   **Draft Mode**: All changes here are saved instantly to your local "Draft" workspace. They are NOT live until you click "Save Week" or "Publish" from the Dashboard.
*   **Visual/Audio**: Use the Media Library to attach content.

## 3. Deals / Offers (Monetization)
This tab controls the **Paywall** and **Entitlements** displayed in the User App ("My Harmony" -> Upgrade).
*   **Workflow**:
    1.  **Edit**: Changes made here save to `product_tiers_draft` (Safe Mode).
    2.  **Publish to Live App**: Copies your drafts to the live App. Users will immediately see the new limits/presentation.
    3.  **Discard & Sync**: If you make a mistake, this resets your inputs to match what is currently live.
*   **Fields**:
    *   **RevenueCat Offering ID**: The exact ID string from your RevenueCat dashboard (e.g., `premium_monthly`).
    *   **Limits**: 
        *   **Sends**: How many messages a user can send (set `-1` for Infinity).
        *   **Forums**: How many chat rooms they can join.
*   **Troubleshooting**: If you see "Permission Denied" errors, ensure `firestore.rules` are deployed.

## 4. Community & Safety
*   **Moderation Queue**: Shows reported user content.
    *   **Flagged**: Posts containing words from your Blocklist appear here automatically.
    *   **Resolve**: Clicking "Resolve" removes the item from the active queue (V3 Feature Prep).
*   **Safety & Filter**:
    *   **Blocklist**: Add words here to automatically flag future messages.
    *   **Load Defaults**: Click "Load Standard Blocklist" to populate with industry-standard safety terms.

## 5. System Management
*   **Legal Compliance**:
    *   Enter URLs for your Privacy Policy, Terms, and EULA.
    *   These links appear dynamically in the User App settings.

---

## Technical Maintenance
*   **Deploying Rules**: If you modify permissions, run `deploy_rules.bat` in the `src/admin` folder.
*   **Backend**: Powered by Firebase (Firestore, Storage, Auth).

