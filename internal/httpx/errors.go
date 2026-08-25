// Package httpx holds the HTTP plumbing every module shares: the response
// envelopes, the typed error set, and the middleware that logs requests.
//
// The rule this package exists to enforce: handlers never choose a status code.
// They return a typed error, and the mapping below is the single place a status
// is decided. That keeps one kind of failure from being a 400 in one module and
// a 422 in another.
package httpx

import (
	"errors"
	"fmt"
	"net/http"
)

// Kind classifies a failure. It is serialised to the client, so treat the
// values as API surface — renaming one is a breaking change.
type Kind string

const (
	KindValidation      Kind = "validation"
	KindUnauthenticated Kind = "unauthenticated"
	KindForbidden       Kind = "forbidden"
	KindNotFound        Kind = "not_found"
	// KindMethodNotAllowed is an addition to the plan's set. Without it chi's
	// default 405 bypasses the envelope and answers in plain text.
	KindMethodNotAllowed Kind = "method_not_allowed"
	KindConflict         Kind = "conflict"
	KindRuleViolation   Kind = "rule_violation"
	KindRateLimited     Kind = "rate_limited"
	KindInternal        Kind = "internal"
)

// statusByKind is the only place in the codebase that maps a failure onto an
// HTTP status.
var statusByKind = map[Kind]int{
	KindValidation:      http.StatusBadRequest,          // 400
	KindUnauthenticated: http.StatusUnauthorized,        // 401
	KindForbidden:       http.StatusForbidden,           // 403
	KindNotFound:         http.StatusNotFound,         // 404
	KindMethodNotAllowed: http.StatusMethodNotAllowed, // 405
	KindConflict:         http.StatusConflict,         // 409
	KindRuleViolation:   http.StatusUnprocessableEntity, // 422
	KindRateLimited:     http.StatusTooManyRequests,     // 429
	KindInternal:        http.StatusInternalServerError, // 500
}

// Status returns the HTTP status for a kind. An unrecognised kind is treated as
// Internal rather than defaulting to 200, so a missing case fails loudly.
func (k Kind) Status() int {
	if s, ok := statusByKind[k]; ok {
		return s
	}
	return http.StatusInternalServerError
}

// Error is the typed error handlers return. Message is shown to the client;
// cause never is.
type Error struct {
	Kind    Kind
	Message string
	// Code is a stable machine-readable identifier such as
	// "employee.email_taken", so clients can branch without parsing prose.
	Code string
	// Fields carries per-field validation messages, keyed by the JSON field name.
	Fields map[string]string

	cause error
}

func (e *Error) Error() string {
	if e.cause != nil {
		return fmt.Sprintf("%s: %s: %v", e.Kind, e.Message, e.cause)
	}
	return fmt.Sprintf("%s: %s", e.Kind, e.Message)
}

func (e *Error) Unwrap() error { return e.cause }

// Status is the HTTP status this error maps to.
func (e *Error) Status() int { return e.Kind.Status() }

// WithCause attaches an underlying error for the logs. It is never serialised.
func (e *Error) WithCause(err error) *Error {
	e.cause = err
	return e
}

// WithCode attaches a machine-readable code.
func (e *Error) WithCode(code string) *Error {
	e.Code = code
	return e
}

// AsError extracts a *Error from err, or nil if there is none in the chain.
func AsError(err error) *Error {
	var e *Error
	if errors.As(err, &e) {
		return e
	}
	return nil
}

// --- constructors -----------------------------------------------------------

// Validation reports malformed or missing input. Pass fields to produce
// per-field messages; pass nil when the problem is not field-specific.
func Validation(message string, fields map[string]string) *Error {
	return &Error{Kind: KindValidation, Message: message, Fields: fields}
}

// Unauthenticated reports a missing, expired or invalid credential.
func Unauthenticated(message string) *Error {
	return &Error{Kind: KindUnauthenticated, Message: message}
}

// Forbidden reports an authenticated caller lacking permission. Prefer NotFound
// when revealing existence would itself leak information across tenants.
func Forbidden(message string) *Error {
	return &Error{Kind: KindForbidden, Message: message}
}

// NotFound reports a missing resource.
func NotFound(message string) *Error {
	return &Error{Kind: KindNotFound, Message: message}
}

// MethodNotAllowed reports a known path called with the wrong verb.
func MethodNotAllowed(message string) *Error {
	return &Error{Kind: KindMethodNotAllowed, Message: message}
}

// Conflict reports a collision with existing state, such as a duplicate key.
func Conflict(message string) *Error {
	return &Error{Kind: KindConflict, Message: message}
}

// RuleViolation reports well-formed input that a business rule rejects — an
// invoice already issued, a payroll run already locked.
func RuleViolation(message string) *Error {
	return &Error{Kind: KindRuleViolation, Message: message}
}

// RateLimited reports that the caller must slow down.
func RateLimited(message string) *Error {
	return &Error{Kind: KindRateLimited, Message: message}
}

// Internal wraps an unexpected failure. The cause is logged; the client is told
// nothing beyond a generic message.
func Internal(cause error) *Error {
	return &Error{
		Kind:    KindInternal,
		Message: "internal server error",
		cause:   cause,
	}
}
