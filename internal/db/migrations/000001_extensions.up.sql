-- Extensions and the id generator every table depends on.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- UUID v7 (RFC 9562): a 48-bit Unix millisecond timestamp followed by random
-- bits. Postgres 16 has no native uuidv7() — that arrives in 18 — so this
-- builds one on top of gen_random_uuid().
--
-- Why v7 rather than v4: the leading timestamp makes generated ids
-- time-ordered, so inserts append to the right edge of the primary key index
-- instead of landing at random. On a large table that is the difference
-- between a mostly-cached index and one that thrashes.
--
-- Mechanics: take a random v4 uuid, overlay its first 6 bytes with the current
-- epoch in milliseconds, then rewrite the 4-bit version field from 0100 (v4)
-- to 0111 (v7). The two set_bit calls flip the two bits that differ.
CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS uuid
AS $$
BEGIN
    RETURN encode(
        set_bit(
            set_bit(
                overlay(
                    uuid_send(gen_random_uuid())
                    PLACING substring(
                        int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint)
                        FROM 3
                    )
                    FROM 1 FOR 6
                ),
                52, 1
            ),
            53, 1
        ),
        'hex')::uuid;
END
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION uuid_generate_v7() IS
    'RFC 9562 version 7 UUID: 48-bit millisecond timestamp then random. Replace with the built-in uuidv7() on Postgres 18.';
