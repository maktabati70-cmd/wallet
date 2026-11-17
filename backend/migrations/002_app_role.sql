-- 002_app_role.sql — least-privilege database role for the API process.
-- The API can read pricing, create quotes and append audit entries, but it
-- cannot change pricing (admin CLI uses the owner role) or rewrite history.
-- Set the password out-of-band:  ALTER ROLE wallet_api PASSWORD '...';
-- On managed databases where the owner may not create roles (some hosted
-- plans), this migration only prints a notice; create the role manually there.
DO $$
BEGIN
    IF NOT (SELECT rolcreaterole OR rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE NOTICE 'current user cannot create roles; skipping wallet_api role';
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'wallet_api') THEN
        CREATE ROLE wallet_api LOGIN;
    END IF;
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM wallet_api';
    EXECUTE 'GRANT SELECT ON fee_schedules TO wallet_api';
    EXECUTE 'GRANT SELECT, INSERT ON audit_log TO wallet_api';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON fee_quotes TO wallet_api';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON sponsored_transfers TO wallet_api';
    EXECUTE 'GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO wallet_api';
END $$;
