package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/Dhananjayan507/office360/internal/db"
	"github.com/Dhananjayan507/office360/internal/httpx"
)

const (
	defaultLimit = 50
	maxLimit     = 200
)

// The enum values come from Postgres via sqlc, so this list cannot drift from
// the database the way a hand-maintained one would.
var employeeStatuses = map[db.EmployeeStatus]bool{
	db.EmployeeStatusProbation: true,
	db.EmployeeStatusActive:    true,
	db.EmployeeStatusOnLeave:   true,
	db.EmployeeStatusNotice:    true,
	db.EmployeeStatusExited:    true,
}

var employmentTypes = map[db.EmploymentType]bool{
	db.EmploymentTypeFullTime:   true,
	db.EmploymentTypePartTime:   true,
	db.EmploymentTypeContract:   true,
	db.EmploymentTypeIntern:     true,
	db.EmploymentTypeConsultant: true,
}

const (
	statusMessage         = "status must be one of: probation, active, on_leave, notice, exited"
	employmentTypeMessage = "employment_type must be one of: full_time, part_time, contract, intern, consultant"
)

func (s *Server) listEmployees(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	q := r.URL.Query()

	departmentID, err := optionalUUIDParam(q.Get("department_id"), "department_id")
	if err != nil {
		return err
	}

	status, err := optionalStatusParam(q.Get("status"))
	if err != nil {
		return err
	}

	limit := intParam(q.Get("limit"), defaultLimit, 1, maxLimit)
	offset := intParam(q.Get("offset"), 0, 0, 1<<30)

	var (
		rows  []db.Employee
		total int64
	)

	// One read-only transaction, so the page and its total agree: without it a
	// row inserted between the two statements yields a count that does not match
	// the rows returned beside it.
	err = s.txn.RunReadOnly(r.Context(), func(tq *db.Queries) error {
		var err error
		rows, err = tq.ListEmployees(r.Context(), db.ListEmployeesParams{
			OrganizationID: org,
			DepartmentID:   departmentID,
			Status:         status,
			Limit:          limit,
			Offset:         offset,
		})
		if err != nil {
			return err
		}

		total, err = tq.CountEmployees(r.Context(), db.CountEmployeesParams{
			OrganizationID: org,
			DepartmentID:   departmentID,
			Status:         status,
		})
		return err
	})
	if err != nil {
		return httpx.Internal(err)
	}

	return httpx.OK(w, r, rows, httpx.Page(total, limit, offset))
}

func (s *Server) getEmployee(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	id, err := pathUUID(r)
	if err != nil {
		return err
	}

	employee, err := s.q.GetEmployee(r.Context(), db.GetEmployeeParams{
		OrganizationID: org,
		ID:             id,
	})
	// An employee in another organisation misses the scoped WHERE and arrives
	// here as ErrNoRows — a 404, never a 403, so the response cannot confirm
	// that the id exists somewhere else.
	if errors.Is(err, pgx.ErrNoRows) {
		return httpx.NotFound("employee not found")
	}
	if err != nil {
		return httpx.Internal(err)
	}

	return httpx.OK(w, r, employee, nil)
}

type createEmployeeRequest struct {
	EmployeeCode   string             `json:"employee_code"`
	DepartmentID   *uuid.UUID         `json:"department_id"`
	DesignationID  *uuid.UUID         `json:"designation_id"`
	FullName       string             `json:"full_name"`
	Email          string             `json:"email"`
	Phone          *string            `json:"phone"`
	Status         *db.EmployeeStatus `json:"status"`
	EmploymentType *db.EmploymentType `json:"employment_type"`
	HiredOn        *jsonDate          `json:"hired_on"`
}

func (s *Server) createEmployee(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	var body createEmployeeRequest
	if err := httpx.Decode(w, r, &body); err != nil {
		return err
	}

	body.EmployeeCode = strings.TrimSpace(body.EmployeeCode)
	body.FullName = strings.TrimSpace(body.FullName)
	body.Email = strings.TrimSpace(body.Email)

	fields := map[string]string{}
	if body.EmployeeCode == "" {
		fields["employee_code"] = "required"
	}
	if body.FullName == "" {
		fields["full_name"] = "required"
	}
	if body.Email == "" {
		fields["email"] = "required"
	}
	if body.Status != nil && !employeeStatuses[*body.Status] {
		fields["status"] = "invalid value"
	}
	if body.EmploymentType != nil && !employmentTypes[*body.EmploymentType] {
		fields["employment_type"] = "invalid value"
	}
	if len(fields) > 0 {
		return httpx.Validation("the employee could not be created", fields)
	}

	employee, err := s.q.CreateEmployee(r.Context(), db.CreateEmployeeParams{
		OrganizationID: org,
		EmployeeCode:   body.EmployeeCode,
		DepartmentID:   body.DepartmentID,
		DesignationID:  body.DesignationID,
		FullName:       body.FullName,
		Email:          body.Email,
		Phone:          body.Phone,
		Status:         body.Status,
		EmploymentType: body.EmploymentType,
		HiredOn:        body.HiredOn.timePtr(),
	})
	if err != nil {
		if ce := employeeConstraintError(err); ce != nil {
			return ce
		}
		return httpx.Internal(err)
	}

	return httpx.Created(w, r, employee)
}

type updateEmployeeRequest struct {
	DepartmentID   *uuid.UUID         `json:"department_id"`
	DesignationID  *uuid.UUID         `json:"designation_id"`
	FullName       *string            `json:"full_name"`
	Email          *string            `json:"email"`
	Phone          *string            `json:"phone"`
	Status         *db.EmployeeStatus `json:"status"`
	EmploymentType *db.EmploymentType `json:"employment_type"`
	HiredOn        *jsonDate          `json:"hired_on"`
}

func (s *Server) updateEmployee(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	id, err := pathUUID(r)
	if err != nil {
		return err
	}

	var body updateEmployeeRequest
	if err := httpx.Decode(w, r, &body); err != nil {
		return err
	}
	if body.Status != nil && !employeeStatuses[*body.Status] {
		return httpx.Validation(statusMessage, map[string]string{"status": "invalid value"})
	}
	if body.EmploymentType != nil && !employmentTypes[*body.EmploymentType] {
		return httpx.Validation(employmentTypeMessage, map[string]string{"employment_type": "invalid value"})
	}

	employee, err := s.q.UpdateEmployee(r.Context(), db.UpdateEmployeeParams{
		OrganizationID: org,
		ID:             id,
		DepartmentID:   body.DepartmentID,
		DesignationID:  body.DesignationID,
		FullName:       body.FullName,
		Email:          body.Email,
		Phone:          body.Phone,
		Status:         body.Status,
		EmploymentType: body.EmploymentType,
		HiredOn:        body.HiredOn.timePtr(),
	})
	// Order matters: a missing id is a 404, even though a bad payload on the
	// same request would be a 400.
	if errors.Is(err, pgx.ErrNoRows) {
		return httpx.NotFound("employee not found")
	}
	if err != nil {
		if ce := employeeConstraintError(err); ce != nil {
			return ce
		}
		return httpx.Internal(err)
	}

	return httpx.OK(w, r, employee, nil)
}

func (s *Server) deleteEmployee(w http.ResponseWriter, r *http.Request) error {
	org, err := currentOrganization(r)
	if err != nil {
		return err
	}

	id, err := pathUUID(r)
	if err != nil {
		return err
	}

	rows, err := s.q.DeleteEmployee(r.Context(), db.DeleteEmployeeParams{
		OrganizationID: org,
		ID:             id,
	})
	if err != nil {
		return httpx.Internal(err)
	}
	if rows == 0 {
		return httpx.NotFound("employee not found")
	}

	return httpx.NoContent(w, r)
}

// employeeConstraintError translates the Postgres constraint violations these
// handlers can legitimately hit into typed errors. It returns nil for anything
// else, so the caller falls through to Internal.
func employeeConstraintError(err error) error {
	switch pgCode(err) {
	case "23505": // unique_violation
		return httpx.Conflict("an employee with that email or code already exists").
			WithCode("employee.duplicate")
	case "23503": // foreign_key_violation
		// The composite key also catches an id belonging to another tenant, so
		// this covers a cross-organisation reference as well as a missing row.
		return httpx.Validation("the employee could not be saved",
			map[string]string{"department_id": "no such department in this organisation"})
	case "23514": // check_violation
		return httpx.Validation("the employee could not be saved", nil)
	default:
		return nil
	}
}

func pathUUID(r *http.Request) (uuid.UUID, error) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		return uuid.Nil, httpx.Validation("id must be a UUID", map[string]string{"id": "not a UUID"})
	}
	return id, nil
}

func optionalUUIDParam(raw, name string) (*uuid.UUID, error) {
	if raw = strings.TrimSpace(raw); raw == "" {
		return nil, nil
	}
	id, err := uuid.Parse(raw)
	if err != nil {
		return nil, httpx.Validation(name+" must be a UUID", map[string]string{name: "not a UUID"})
	}
	return &id, nil
}

func optionalStatusParam(raw string) (*db.EmployeeStatus, error) {
	if raw = strings.TrimSpace(raw); raw == "" {
		return nil, nil
	}
	status := db.EmployeeStatus(raw)
	if !employeeStatuses[status] {
		return nil, httpx.Validation(statusMessage, map[string]string{"status": "invalid value"})
	}
	return &status, nil
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
