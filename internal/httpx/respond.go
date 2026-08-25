package httpx

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5/middleware"
)

// MaxRequestBody caps decoded request bodies at 1 MiB.
const MaxRequestBody = 1 << 20

// Meta travels alongside every response. RequestID is always present; the
// pagination fields appear only on list responses.
type Meta struct {
	RequestID string `json:"request_id,omitempty"`
	Total     *int64 `json:"total,omitempty"`
	Limit     *int32 `json:"limit,omitempty"`
	Offset    *int32 `json:"offset,omitempty"`
}

// Page builds the Meta for a paginated list.
func Page(total int64, limit, offset int32) *Meta {
	return &Meta{Total: &total, Limit: &limit, Offset: &offset}
}

type successEnvelope struct {
	Data any   `json:"data"`
	Meta *Meta `json:"meta"`
}

type errorPayload struct {
	Kind    Kind              `json:"kind"`
	Message string            `json:"message"`
	Code    string            `json:"code,omitempty"`
	Fields  map[string]string `json:"fields,omitempty"`
}

type errorEnvelope struct {
	Error errorPayload `json:"error"`
	Meta  *Meta        `json:"meta"`
}

// HandlerFunc is a handler that returns an error instead of writing one.
// Handle adapts it to the standard library signature.
type HandlerFunc func(http.ResponseWriter, *http.Request) error

// Handle turns a HandlerFunc into an http.HandlerFunc, routing any returned
// error through Fail. This is what keeps status codes out of handler bodies.
func Handle(h HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			Fail(w, r, err)
		}
	}
}

// OK writes 200 with a success envelope.
func OK(w http.ResponseWriter, r *http.Request, data any, meta *Meta) error {
	return Write(w, r, http.StatusOK, data, meta)
}

// Created writes 201 with a success envelope.
func Created(w http.ResponseWriter, r *http.Request, data any) error {
	return Write(w, r, http.StatusCreated, data, nil)
}

// NoContent writes 204 with no body.
func NoContent(w http.ResponseWriter, _ *http.Request) error {
	w.WriteHeader(http.StatusNoContent)
	return nil
}

// Write emits a success envelope at an explicit status. Prefer OK, Created or
// NoContent; reach for this only when the status is genuinely situational, as
// on the health endpoint.
func Write(w http.ResponseWriter, r *http.Request, status int, data any, meta *Meta) error {
	if meta == nil {
		meta = &Meta{}
	}
	meta.RequestID = middleware.GetReqID(r.Context())

	encode(w, status, successEnvelope{Data: data, Meta: meta})
	return nil
}

// Fail maps any error onto the error envelope. Errors that are not a *Error are
// treated as Internal, so an unmapped failure can never leak its message.
func Fail(w http.ResponseWriter, r *http.Request, err error) {
	appErr := AsError(err)
	if appErr == nil {
		appErr = Internal(err)
	}

	if appErr.Kind == KindInternal {
		// The cause is for us, never for the client.
		slog.ErrorContext(r.Context(), "request failed",
			"error", appErr.Error(),
			"method", r.Method,
			"path", r.URL.Path,
			"request_id", middleware.GetReqID(r.Context()),
		)
	}

	encode(w, appErr.Status(), errorEnvelope{
		Error: errorPayload{
			Kind:    appErr.Kind,
			Message: appErr.Message,
			Code:    appErr.Code,
			Fields:  appErr.Fields,
		},
		Meta: &Meta{RequestID: middleware.GetReqID(r.Context())},
	})
}

// Decode reads a JSON body into dst, rejecting unknown fields so a misspelled
// key is a 400 rather than a silently ignored value.
func Decode(w http.ResponseWriter, r *http.Request, dst any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, MaxRequestBody))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return Validation("request body is not valid JSON: "+err.Error(), nil)
	}
	return nil
}

func encode(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		slog.Error("encode response", "error", err)
	}
}
