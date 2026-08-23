Profile save fix

The profile editor no longer requires PostgREST to return a single row from
UPDATE ... SELECT after saving. This avoids 'Cannot coerce the result to a
single JSON object' when discovery RLS prevents the returned row.
No database migration is required for this frontend fix.
