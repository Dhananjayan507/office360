package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/Dhananjayan507/office360/api/internal/db"
)

const (
	defaultLimit = 50
	maxLimit     = 200
)

var employeeStatuses = map[string]bool{"active": true, "on_leave": true, "exited": true}

func (s *Server) listEmployees(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	departmentID, ok := optionalUUIDParam(w, q.Get("department_id"), "department_id")
	if !ok {
		return
	}

	var status *string
	if raw := strings.TrimSpace(q.Get("status")); raw != "" {
		if !employeeStatuses[raw] {
			writeError(w, http.StatusBadRequest, "status must be one of: active, on_leave, exited")
			return
		}
		status = &raw
	}

	limit := intParam(q.Get("limit"), defaultLimit, 1, maxLimit)
	offset := intParam(q.Get("offset"), 0, 0, 1<<30)

	rows, err := s.q.ListEmployees(r.Context(), db.ListEmployeesParams{
		DepartmentID: departmentID,
		Status:       status,
		Limit:        limit,
		Offset:       offset,
	})
	if err != nil {
		writeInternal(w, "list employees", err)
		return
	}

	total, err := s.q.CountEmployees(r.Context(), db.CountEmployeesParams{
		DepartmentID: departmentID,
		Status:       status,
	})
	if err != nil {
		writeInternal(w, "count employees", err)
		return
	}

	writeJSON(w, http.StatusOK, listBody[db.Employee]{Data: rows, Total: total, Limit: limit, Offset: offset})
}

func (s *Server) getEmployee(w http.ResponseWriter, r *http.Request) {
	id, ok := pathUUID(w, r)
	if !ok {
		return
	}

	employee, err := s.q.GetEmployee(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "employee not found")
		return
	}
	if err != nil {
		writeInternal(w, "get employee", err)
		return
	}

	writeJSON(w, http.StatusOK, employee)
}

type createEmployeeRequest struct {
	DepartmentID *uuid.UUID `json:"department_id"`
	FullName     string     `json:"full_name"`
	Email        string     `json:"email"`
	Title        *string    `json:"title"`
	Status       *string    `json:"status"`
	HiredOn      *jsonDate  `json:"hired_on"`
}

func (s *Server) createEmployee(w http.ResponseWriter, r *http.Request) {
	var body createEmployeeRequest
	if !decodeJSON(w, r, &body) {
		return
	}

	body.FullName = strings.TrimSpace(body.FullName)
	body.Email = strings.TrimSpace(body.Email)

	if body.FullName == "" {
		writeError(w, http.StatusBadRequest, "full_name is required")
		return
	}
	if body.Email == "" {
		writeError(w, http.StatusBadRequest, "email is required")
		return
	}
	if !validStatus(w, body.Status) {
		return
	}

	employee, err := s.q.CreateEmployee(r.Context(), db.CreateEmployeeParams{
		DepartmentID: body.DepartmentID,
		FullName:     body.FullName,
		Email:        body.Email,
		Title:        body.Title,
		Status:       body.Status,
		HiredOn:      body.HiredOn.timePtr(),
	})
	if handled := s.writeConstraintError(w, err); handled {
		return
	}
	if err != nil {
		writeInternal(w, "create employee", err)
		return
	}

	writeJSON(w, http.StatusCreated, employee)
}

type updateEmployeeRequest struct {
	DepartmentID *uuid.UUID `json:"department_id"`
	FullName     *string    `json:"full_name"`
	Email        *string    `json:"email"`
	Title        *string    `json:"title"`
	Status       *string    `json:"status"`
	HiredOn      *jsonDate  `json:"hired_on"`
}

func (s *Server) updateEmployee(w http.ResponseWriter, r *http.Request) {
	id, ok := pathUUID(w, r)
	if !ok {
		return
	}

	var body updateEmployeeRequest
	if !decodeJSON(w, r, &body) {
		return
	}
	if !validStatus(w, body.Status) {
		return
	}

	employee, err := s.q.UpdateEmployee(r.Context(), db.UpdateEmployeeParams{
		ID:           id,
		DepartmentID: body.DepartmentID,
		FullName:     body.FullName,
		Email:        body.Email,
		Title:        body.Title,
		Status:       body.Status,
		HiredOn:      body.HiredOn.timePtr(),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "employee not found")
		return
	}
	if handled := s.writeConstraintError(w, err); handled {
		return
	}
	if err != nil {
		writeInternal(w, "update employee", err)
		return
	}

	writeJSON(w, http.StatusOK, employee)
}

func (s *Server) deleteEmployee(w http.ResponseWriter, r *http.Request) {
	id, ok := pathUUID(w, r)
	if !ok {
		return
	}

	rows, err := s.q.DeleteEmployee(r.Context(), id)
	if err != nil {
		writeInternal(w, "delete employee", err)
		return
	}
	if rows == 0 {
		writeError(w, http.StatusNotFound, "employee not found")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// writeConstraintError maps the Postgres constraint violations these handlers
// can legitimately hit onto 4xx responses. It reports whether it wrote a response.
func (s *Server) writeConstraintError(w http.ResponseWriter, err error) bool {
	switch pgCode(err) {
	case "23505": // unique_violation
		writeError(w, http.StatusConflict, "an employee with that email already exists")
	case "23503": // foreign_key_violation
		writeError(w, http.StatusBadRequest, "department_id does not reference an existing department")
	case "23514": // check_violation
		writeError(w, http.StatusBadRequest, "status must be one of: active, on_leave, exited")
	default:
		return false
	}
	return true
}

func validStatus(w http.ResponseWriter, status *string) bool {
	if status != nil && !employeeStatuses[*status] {
		writeError(w, http.StatusBadRequest, "status must be one of: active, on_leave, exited")
		return false
	}
	return true
}

func pathUUID(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "id must be a UUID")
		return uuid.Nil, false
	}
	return id, true
}

func optionalUUIDParam(w http.ResponseWriter, raw, name string) (*uuid.UUID, bool) {
	if raw = strings.TrimSpace(raw); raw == "" {
		return nil, true
	}
	id, err := uuid.Parse(raw)
	if err != nil {
		writeError(w, http.StatusBadRequest, name+" must be a UUID")
		return nil, false
	}
	return &id, true
}

// intParam clamps rather than rejects, so a stray ?limit=9999 still returns a page.
func intParam(raw string, fallback, min, max int32) int32 {
	if raw == "" {
		return fallback
	}
	n, err := strconv.ParseInt(raw, 10, 32)
	if err != nil {
		return fallback
	}
	v := int32(n)
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
