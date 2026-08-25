// Command migrate applies and rolls back database migrations.
//
// It exists so the project does not depend on contributors having the
// golang-migrate CLI installed and on PATH — `go run ./cmd/migrate up` works
// from a bare checkout.
//
//	go run ./cmd/migrate            # apply everything pending
//	go run ./cmd/migrate up
//	go run ./cmd/migrate down       # roll back one migration
//	go run ./cmd/migrate down 3     # roll back three
//	go run ./cmd/migrate version    # current version, and whether it is dirty
//	go run ./cmd/migrate force 1    # clear a dirty state — see below
package main

import (
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"strconv"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/joho/godotenv"
)

const migrationsPath = "file://internal/db/migrations"

func main() {
	if err := run(); err != nil {
		slog.Error("migrate failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	flag.Usage = usage
	flag.Parse()

	// A migration tool has no business demanding a JWT secret, so this reads
	// DATABASE_URL directly instead of going through internal/config.
	for _, path := range []string{".env", "../.env"} {
		_ = godotenv.Load(path)
	}
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		return errors.New("DATABASE_URL is required (copy .env.example to .env)")
	}

	m, err := migrate.New(migrationsPath, dsn)
	if err != nil {
		return fmt.Errorf("open migrations: %w", err)
	}
	defer m.Close()

	switch cmd := flag.Arg(0); cmd {
	case "", "up":
		return report(m, m.Up())

	case "down":
		steps, err := stepArg(1)
		if err != nil {
			return err
		}
		return report(m, m.Steps(-steps))

	case "version":
		version, dirty, err := m.Version()
		if errors.Is(err, migrate.ErrNilVersion) {
			slog.Info("no migrations applied yet")
			return nil
		}
		if err != nil {
			return err
		}
		slog.Info("current version", "version", version, "dirty", dirty)
		return nil

	case "force":
		version, err := stepArg(-1)
		if err != nil {
			return err
		}
		if version < 0 {
			return errors.New("force requires a version number, e.g. `force 1`")
		}
		return m.Force(version)

	default:
		usage()
		return fmt.Errorf("unknown command %q", cmd)
	}
}

// report treats ErrNoChange as success — re-running `up` on an up-to-date
// database is a no-op, not a failure, and scripts should not have to special-case it.
func report(m *migrate.Migrate, err error) error {
	if errors.Is(err, migrate.ErrNoChange) {
		slog.Info("database already up to date")
		return nil
	}
	if err != nil {
		return err
	}

	version, dirty, verr := m.Version()
	if verr != nil {
		return nil // the migration itself succeeded; reporting is best-effort
	}
	slog.Info("migration complete", "version", version, "dirty", dirty)
	return nil
}

func stepArg(fallback int) (int, error) {
	if flag.NArg() < 2 {
		return fallback, nil
	}
	n, err := strconv.Atoi(flag.Arg(1))
	if err != nil {
		return 0, fmt.Errorf("expected a number, got %q", flag.Arg(1))
	}
	return n, nil
}

func usage() {
	fmt.Fprint(os.Stderr, `usage: migrate [command]

  up             apply all pending migrations (default)
  down [n]       roll back n migrations (default 1)
  version        print the current version and dirty flag
  force <v>      mark the database as being at version v WITHOUT running
                 anything. Only for clearing a dirty flag after a migration
                 failed halfway - inspect the schema by hand first.

DATABASE_URL is read from the environment or the repo-root .env.
Run from the repository root; migration files are read from
internal/db/migrations.
`)
}
