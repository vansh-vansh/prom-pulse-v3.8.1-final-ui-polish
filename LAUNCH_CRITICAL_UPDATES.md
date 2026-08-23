Prom Pulse launch-critical updates

1. Prom Energy options now have one-line hover descriptions (title/aria-label), including touch-friendly explanatory context through accessible labels.
2. Added required profile gender options: Boy, Girl, Gay.
   - Boy viewers discover Girl profiles only.
   - Girl viewers discover Boy profiles only.
   - Gay viewers discover Boy profiles only, exactly as specified.
   - Existing accounts must choose a gender in My Profile before gender-filtered discovery becomes available.
3. Added server-enforced discovery privacy for accepted matches.
   - A matched user's profile is removed from public discovery while the accepted match exists.
   - The matched partner can still access the profile through the accepted conversation relationship.
   - Unmatch sets the match to cancelled, restores discovery visibility, and allows a fresh Prom request later.
4. Added an Unmatch action inside the private chat with confirmation.
5. Added a Secret Crush onboarding popup after login/signup verification with a visual mini-guide showing the heart button location.

Database migration to run once in the existing Supabase project:
supabase/migrations/20260822_gender_unmatch_discovery.sql

Do not rerun older migrations.
