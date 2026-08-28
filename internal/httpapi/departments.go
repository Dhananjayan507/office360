package httpapi

import (
	"net/http"
	"strings"

	"github.com/google/uuid"

	"github.com/Dhananjayan507/office360/internal/db"
	"github.com/Dhananjayan507/office360/internal/httpx"
)

func (s *Server) listDepartments(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	rows, err := s.q.ListDepartments(r.Context(), org)
	if err != nil {
		return httpx.Internal(err)
	}

	total := int64(len(rows))
	return httpx.OK(w, r, rows, httpx.Page(total, int32(total), 0))
}

type createDepartmentRequest struct {
	Name     string     `json:"name"`
	Code     *string    `json:"code"`
	ParentID *uuid.UUID `json:"parent_id"`
}

func (s *Server) createDepartment(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	var body createDepartmentRequest
	if err := httpx.Decode(w, r, &body); err != nil {
		return err
	}

	body.Name = strings.TrimSpace(body.Name)
	if body.Name == "" {
		return httpx.Validation("name is required", map[string]string{"name": "required"})
	}

	department, err := s.q.CreateDepartment(r.Context(), db.CreateDepartmentParams{
		OrganizationID: org,
		Name:           body.Name,
		Code:           body.Code,
		ParentID:       body.ParentID,
	})
	if pgCode(err) == "23505" {
		return httpx.Conflict("a department with that name already exists").
			WithCode("department.name_taken")
	}
	if err != nil {
		return httpx.Internal(err)
	}

	return httpx.Created(w, r, department)
}

func (s *Server) deleteDepartment(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	id, err := pathUUID(r)
	if err != nil {
		return err
	}

	rows, err := s.q.DeleteDepartment(r.Context(), db.DeleteDepartmentParams{
		OrganizationID: org,
		ID:             id,
	})
	if err != nil {
		return httpx.Internal(err)
	}
	// Zero rows means it does not exist *for this organisation*. A department in
	// another tenant lands here too, and must stay a 404 — a 403 would confirm
	// the id is real.
	if rows == 0 {
		return httpx.NotFound("department not found")
	}

	return httpx.NoContent(w, r)
}
