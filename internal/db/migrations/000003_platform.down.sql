DROP TABLE IF EXISTS settings;
DROP TABLE IF EXISTS number_series;
DROP TABLE IF EXISTS feature_flags;

-- Dropping the partitioned parent takes its partitions with it.
DROP TABLE IF EXISTS audit_log;

DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS plans;
DROP TABLE IF EXISTS organizations;
