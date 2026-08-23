# Prom Pulse v3.7.4

Clean package based on the latest fixed authentication build.

Important:
- Email OTP is used only once during signup.
- Future login uses email + password.
- Personal email is allowed. No phone/college email required.
- The profile editor and signup flow include “I don’t want to reveal my interests”.
- Discover shows verified, non-banned students from the configured college and supports name/course/branch/interest search.

Before local testing:
1. Copy your existing `.env.local` into this project root.
2. Run `npm install`.
3. Run `npm run dev`.

The project root is the folder containing `package.json`, `app`, `lib`, and `supabase`.

## v3.7.5 changes
- Added `Figure out yourself` to the Prom Energy options.
- Added a permanent `Delete account` action in My Profile.
- Account deletion uses the `public.delete_my_account()` Supabase function and permanently removes the signed-in auth user plus all cascade-linked Prom Pulse data, including matches, messages, memories, XP, badges, reports, questions, and notifications. Avatar files under the user's avatar folder are removed first.
- The app asks for explicit confirmation before deletion and signs the user out after success.

### Database step for this release
Run the `supabase/schema.sql` from this release in your existing Supabase project once. It contains the `delete_my_account()` function. Do not mix it with older schema files.


## Signup OTP setup
Prom Pulse uses a one-time 6-digit email OTP only during signup. In Supabase Dashboard, open Authentication → Providers → Email and make sure **Confirm email** is enabled. The confirmation email template must include `{{ .Token }}` so the six-digit code is included. If Confirm email is disabled, Supabase will create a session immediately; Prom Pulse now detects that and blocks entry until email confirmation is enabled.

Existing profiles are backfilled from `auth.users.email_confirmed_at`, so only genuinely confirmed email accounts appear in campus discovery.


### OTP verification fix
The signup OTP verifier is guarded against duplicate submissions. It accepts exactly the 6-digit latest code, disables duplicate verification attempts, and gives a clear message for invalid/expired tokens. Resending clears the previous OTP so users know to use only the newest code.


## OTP configuration
Supabase may be configured to generate 6- or 8-digit email OTPs. Prom Pulse v3.7.8 accepts either 6 or 8 digits so existing projects do not break. For the intended 6-digit UX, set the Supabase email OTP length to 6 if that setting is available in your Authentication email/OTP settings. Resend is protected with a 30-second cooldown.


## OTP is 8 digits
Prom Pulse v3.8.0 expects an 8-digit signup OTP. Update the Supabase Confirm signup template text to say “Your Prom Pulse verification code is:” and use `{{ .Token }}`. Resend uses `supabase.auth.resend({ type: 'signup', email })` with a 60-second cooldown and visible errors.

## v3.8.1 clean resend build
This build keeps the 8-digit OTP UX and uses a dedicated resend flow with a 60-second cooldown and explicit on-screen status/errors. Resend uses Supabase Auth `resend({ type: 'signup' })` and does not require a database migration.
