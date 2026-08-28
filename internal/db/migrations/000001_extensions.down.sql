DROP FUNCTION IF EXISTS uuid_generate_v7();

-- pgcrypto is deliberately left in place: it may predate this migration and is
-- shared with anything else in the database that needs gen_random_uuid().
