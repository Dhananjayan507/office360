package db_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"

	"github.com/Dhananjayan507/office360/internal/db"
)

// errBoom stands in for any failure a service might return mid-transaction.
var errBoom = errors.New("deliberate failure")

func newPool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	// The test binary runs in its own package directory, so reach back up for
	// the repo-root .env the rest of the tooling uses.
	for _, path := range []string{".env", filepath.Join("..", "..", ".env")} {
		_ = godotenv.Load(path)
	}

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping database test")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		t.Skipf("database unreachable (%v); is ./make.ps1 up running?", err)
	}

	t.Cleanup(pool.Close)
	return pool
}

func countOrganizations(t *testing.T, ctx context.Context, pool *pgxpool.Pool) int64 {
	t.Helper()

	var n int64
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM organizations").Scan(&n); err != nil {
		t.Fatalf("count organizations: %v", err)
	}
	return n
}

// TestRunRollsBackOnError is the end-of-day check: a transaction that fails
// part-way must leave the database exactly as it found it. The insert below
// succeeds before the error is returned, so a missing rollback would leave a
// visible row.
func TestRunRollsBackOnError(t *testing.T) {
	ctx := context.Background()
	pool := newPool(t)
	manager := db.NewTxManager(pool)

	before := countOrganizations(t, ctx, pool)

	err := manager.Run(ctx, func(q *db.Queries) error {
		if _, err := q.CreateOrganization(ctx, db.CreateOrganizationParams{
			Name: "Rollback Test Org",
			Slug: "rollback-test-org",
		}); err != nil {
			return err
		}
		// The row exists inside the transaction at this point. Returning an
		// error must undo it.
		return errBoom
	})

	if !errors.Is(err, errBoom) {
		t.Fatalf("expected errBoom to propagate unwrapped, got %v", err)
	}

	if after := countOrganizations(t, ctx, pool); after != before {
		t.Fatalf("rollback failed: organizations went from %d to %d", before, after)
	}

	// And the specific row must be gone, not merely the count unchanged.
	var exists bool
	if err := pool.QueryRow(ctx,
		"SELECT EXISTS (SELECT 1 FROM organizations WHERE slug = $1)", "rollback-test-org",
	).Scan(&exists); err != nil {
		t.Fatalf("existence check: %v", err)
	}
	if exists {
		t.Fatal("rollback failed: the organisation created inside the failed transaction survived")
	}
}

// TestRunCommitsOnSuccess is the control. Without it the test above would also
// pass if Run silently did nothing at all.
func TestRunCommitsOnSuccess(t *testing.T) {
	ctx := context.Background()
	pool := newPool(t)
	manager := db.NewTxManager(pool)

	const slug = "commit-test-org"
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), "DELETE FROM organizations WHERE slug = $1", slug)
	})

	before := countOrganizations(t, ctx, pool)

	err := manager.Run(ctx, func(q *db.Queries) error {
		_, err := q.CreateOrganization(ctx, db.CreateOrganizationParams{
			Name: "Commit Test Org",
			Slug: slug,
		})
		return err
	})
	if err != nil {
		t.Fatalf("Run returned an error on the success path: %v", err)
	}

	if after := countOrganizations(t, ctx, pool); after != before+1 {
		t.Fatalf("commit failed: organizations went from %d to %d", before, after)
	}
}

// TestRunRollsBackOnPanic covers the other exit path. A panic must not leave the
// transaction open holding locks until the pool reaps the connection.
func TestRunRollsBackOnPanic(t *testing.T) {
	ctx := context.Background()
	pool := newPool(t)
	manager := db.NewTxManager(pool)

	before := countOrganizations(t, ctx, pool)

	func() {
		defer func() {
			if recover() == nil {
				t.Error("expected the panic to be re-raised after rollback")
			}
		}()

		_ = manager.Run(ctx, func(q *db.Queries) error {
			if _, err := q.CreateOrganization(ctx, db.CreateOrganizationParams{
				Name: "Panic Test Org",
				Slug: "panic-test-org",
			}); err != nil {
				return err
			}
			panic("boom")
		})
	}()

	if after := countOrganizations(t, ctx, pool); after != before {
		t.Fatalf("panic rollback failed: organizations went from %d to %d", before, after)
	}
}
