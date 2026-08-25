package httpapi

import (
	"net/http"
	"strings"

	"github.com/Dhananjayan507/office360/api/internal/db"
)

func (s *Server) listDepartments(w http.ResponseWriter, r *http.Request) {
	rows, err := s.q.ListDepartments(r.Context())
	if err != nil {
		writeInternal(w, "list departments", err)
		return
	}

	writeJSON(w, http.StatusOK, listBody[db.Department]{
		Data:  rows,
		Total: int64(len(rows)),
		Limit: int32(len(rows)),
	})
}

type createDepartmentRequest struct {
	Name string `json:"name"`
}

func (s *Server) createDepartment(w http.ResponseWriter, r *http.Request) {
	var body createDepartmentRequest
	if !decodeJSON(w, r, &body) {
		return
	}

	body.Name = strings.TrimSpace(body.Name)
	if body.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}

	department, err := s.q.CreateDepartment(r.Context(), body.Name)
	if pgCode(err) == "23505" {
		writeError(w, http.StatusConflict, "a department with that name already exists")
		return
	}
	if err != nil {
		writeInternal(w, "create department", err)
		return
	}

	writeJSON(w, http.StatusCreated, department)
}

func (s *Server) deleteDepartment(w http.ResponseWriter, r *http.Request) {
	id, ok := pathUUID(w, r)
	if !ok {
		return
	}

	rows, err := s.q.DeleteDepartment(r.Context(), id)
	if err != nil {
		writeInternal(w, "delete department", err)
		return
	}
	if rows == 0 {
		writeError(w, http.StatusNotFound, "department not found")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
