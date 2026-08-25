# Prom Pulse fixes - 2026-08-24 (chat + discovery)

1. Fixed the runtime crash in Chats caused by `currentUserId` being referenced before it was defined.
2. Discovery now distinguishes the viewer's own matched state from the target person's matched state. If the viewer is already matched, the action says `You’re already matched` instead of falsely implying every target is matched. If the target is matched, other users see `Already matched`.
3. The request button remains disabled for a user who already has an accepted match, preserving the one-match-at-a-time rule.

No Supabase migration is required for these two frontend fixes. The previously applied `20260824_remaining_feature_fixes.sql` remains required for the Secret Crush / request / unmatch RPCs.
