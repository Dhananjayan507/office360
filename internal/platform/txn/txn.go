// Package txn runs a set of sqlc queries inside one database transaction.
//
// The layering rule this exists to support: services own the transaction. A use
// case that writes two tables and an audit row must commit or roll back as a
// unit, and that decision belongs to the service, not to a handler and not to
// the query layer. Handlers never see a transaction.
//
// Nothing here may import internal/modules — the dependency runs one way only.
package txn

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Dhananjayan507/office360/internal/db"
)

// Manager hands out query sets over one pool, transactional or not.
type Manager struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Manager {
	return &Manager{pool: pool}
}

// Queries returns a non-transactional query set, for a read that is a single
// statement. Anything that writes, or that reads several statements which must
// agree with each other, belongs in InTx or InReadOnlyTx.
func (m *Manager) Queries() *db.Queries { return db.New(m.pool) }

// Pool exposes the underlying pool for health checks and for the rare caller
// that needs pgx directly.
func (m *Manager) Pool() *pgxpool.Pool { return m.pool }

// InTx runs fn inside a read-write transaction, committing when it returns nil
// and rolling back on any error.
//
// fn must use only the *db.Queries it is handed. Reaching for the manager's
// Queries() inside fn would run that statement on a different pooled connection,
// outside the transaction — it would not see fn's uncommitted writes, and it
// would survive a rollback.
func (m *Manager) InTx(ctx context.Context, fn func(*db.Queries) error) error {
	return m.run(ctx, pgx.TxOptions{}, fn)
}

// InReadOnlyTx runs fn in a read-only transaction, so several reads see one
// consistent snapshot — a list and its total count, for instance, which would
// otherwise disagree if a row were inserted between them.
func (m *Manager) InReadOnlyTx(ctx context.Context, fn func(*db.Queries) error) error {
	return m.run(ctx, pgx.TxOptions{AccessMode: pgx.ReadOnly}, fn)
}

func (m *Manager) run(ctx context.Context, opts pgx.TxOptions, fn func(*db.Queries) error) (err error) {
	tx, err := m.pool.BeginTx(ctx, opts)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}

	defer func() {
		if p := recover(); p != nil {
			rollback(ctx, tx)
			panic(p)
		}
		if err != nil {
			rollback(ctx, tx)
		}
	}()

	if err = fn(db.New(tx)); err != nil {
		return err
	}

	if err = tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}
	return nil
}

// rollback detaches from the request's context deadline. If the client
// disconnected or the handler timed out, ctx is already cancelled and a rollback
// issued on it would be dropped — leaving the transaction open, holding its locks
// until the connection is reaped.
func rollback(ctx context.Context, tx pgx.Tx) {
	_ = tx.Rollback(context.WithoutCancel(ctx))
}
