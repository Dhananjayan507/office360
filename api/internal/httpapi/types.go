package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

// pgCode returns the SQLSTATE of a Postgres error, or "" for any other error.
func pgCode(err error) string {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code
	}
	return ""
}

// jsonDate accepts a bare "YYYY-MM-DD" string, which is what a Postgres `date`
// column means — time.Time alone would demand a full RFC 3339 timestamp.
type jsonDate struct{ time.Time }

func (d *jsonDate) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	if s == "" {
		return nil
	}
	t, err := time.Parse(time.DateOnly, s)
	if err != nil {
		return fmt.Errorf("date must be formatted YYYY-MM-DD, got %q", s)
	}
	d.Time = t
	return nil
}

func (d *jsonDate) timePtr() *time.Time {
	if d == nil || d.IsZero() {
		return nil
	}
	return &d.Time
}
