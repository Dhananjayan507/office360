package httpapi

import (
	"net/http"
	"strings"

	"github.com/Dhananjayan507/office360/internal/httpx"
)

func (s *Server) listDepartments(w http.ResponseWriter, r *http.Request) error {
	rows, err := s.q.ListDepartments(r.Context())
	if err != nil {
		return httpx.Internal(err)
	}

	total := int64(len(rows))
	return httpx.OK(w, r, rows, httpx.Page(total, int32(total), 0))
}

type createDepartmentRequest struct {
	Name string `json:"name"`
}

func (s *Server) createDepartment(w http.ResponseWriter, r *http.Request) error {
	var body createDepartmentRequest
	if err := httpx.Decode(w, r, &body); err != nil {
		return err
	}

	body.Name = strings.TrimSpace(body.Name)
	if body.Name == "" {
		return httpx.Validation("name is required", map[string]string{"name": "required"})
	}

	department, err := s.q.CreateDepartment(r.Context(), body.Name)
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
	id, err := pathUUID(r)
	if err != nil {
		return err
	}

	rows, err := s.q.DeleteDepartment(r.Context(), id)
	if err != nil {
		return httpx.Internal(err)
	}
	if rows == 0 {
		return httpx.NotFound("department not found")
	}

	return httpx.NoContent(w, r)
}
