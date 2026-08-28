package httpapi

import (
	"net/http"

	"github.com/google/uuid"

	"github.com/Dhananjayan507/office360/internal/httpx"
)

// DevOrganizationHeader carries the caller's organisation until authentication
// exists.
const DevOrganizationHeader = "X-Organization-Id"

// currentOrganization resolves the organisation a request acts within, and is
// deliberately the only place in the codebase that decision is made.
//
// INTERIM. Day 3 issues JWTs and Day 4 adds internal/platform/tenant as real
// middleware; at that point the body of this function is replaced by a read of
// the verified claim and the header stops being trusted. Every call site stays
// as it is — that is the reason it is a single function rather than a header
// read scattered through the handlers.
//
// It fails closed. No header means no organisation, and no organisation means no
// query runs. Falling back to a default would quietly let an unauthenticated
// request act as a real tenant, which is the failure mode this whole layer
// exists to prevent.
func currentOrganization(r *http.Request) (uuid.UUID, error) {
	raw := r.Header.Get(DevOrganizationHeader)
	if raw == "" {
		return uuid.Nil, httpx.Unauthenticated("missing " + DevOrganizationHeader + " header").
			WithCode("tenant.missing")
	}

	id, err := uuid.Parse(raw)
	if err != nil {
		return uuid.Nil, httpx.Unauthenticated(DevOrganizationHeader + " must be a UUID").
			WithCode("tenant.invalid")
	}

	return id, nil
}
