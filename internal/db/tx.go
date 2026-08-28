package db

// This file is hand-written and lives alongside the sqlc output on purpose.
// `sqlc generate` only writes db.go, models.go and *.sql.go, so tx.go survives
// regeneration — but do not rename it to match one of those.

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// TxManager hands out query sets over one pool and owns the commit/rollback
// decision, so no caller has to remember it.
//
// The layering rule this supports: services own the transaction. A use case
// that writes two tables and an audit row must commit or roll back as a unit,
// and that call belongs to the service — not to a handler, and not to the
// generated query layer.
type TxManager struct {
	pool *pgxpool.Pool
}

func NewTxManager(pool *pgxpool.Pool) *TxManager {
	return &TxManager{pool: pool}
}

// Queries returns a non-transactional query set, for work that is a single
// statement. Anything spanning more than one belongs in Run or RunReadOnly.
func (m *TxManager) Queries() *Queries { return New(m.pool) }

// Pool exposes the underlying pool for health checks.
func (m *TxManager) Pool() *pgxpool.Pool { return m.pool }

// Run executes fn inside a read-write transaction. It commits when fn returns
// nil and rolls back on any error, returning fn's error unwrapped so callers can
// still match on it with errors.Is.
//
// fn must use only the *Queries it is handed. Reaching for the manager's
// Queries() inside fn would run that statement on a different pooled connection,
// outside the transaction: it would not see fn's uncommitted writes, and it
// would survive the rollback.
//
// A panic inside fn rolls back and is then re-raised, so a bug cannot leave a
// transaction open holding locks until the connection is reaped.
func (m *TxManager) Run(ctx context.Context, fn func(*Queries) error) error {
	return m.run(ctx, pgx.TxOptions{}, fn)
}

// RunReadOnly executes fn in a read-only transaction, so several reads observe
// one consistent snapshot — a page of rows and its total count, for instance,
// which otherwise disagree when a row is inserted between the two statements.
func (m *TxManager) RunReadOnly(ctx context.Context, fn func(*Queries) error) error {
	return m.run(ctx, pgx.TxOptions{AccessMode: pgx.ReadOnly}, fn)
}

func (m *TxManager) run(ctx context.Context, opts pgx.TxOptions, fn func(*Queries) error) (err error) {
	tx, err := m.pool.BeginTx(ctx, opts)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}

	// Named return: the deferred func inspects err to decide whether the work
	// above it succeeded, which is what lets one place own the rollback.
	defer func() {
		if p := recover(); p != nil {
			rollback(ctx, tx)
			panic(p)
		}
		if err != nil {
			rollback(ctx, tx)
		}
	}()

	if err = fn(New(tx)); err != nil {
		return err
	}

	if err = tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}

	return nil
}

// rollback detaches from the caller's context deadline. If the client
// disconnected or the handler timed out, ctx is already cancelled and a rollback
// issued on it would be dropped — abandoning the transaction with its locks held
// until the connection is reaped.
func rollback(ctx context.Context, tx pgx.Tx) {
	_ = tx.Rollback(context.WithoutCancel(ctx))
}
