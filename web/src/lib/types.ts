/** Mirrors the JSON shapes returned by the Go API (`internal/db/models.go`). */

export type EmployeeStatus = 'probation' | 'active' | 'on_leave' | 'notice' | 'exited';

export type EmploymentType = 'full_time' | 'part_time' | 'contract' | 'intern' | 'consultant';

export type OrganizationStatus = 'active' | 'suspended' | 'closed';

/** The tenant root. Every record below belongs to exactly one. */
export interface Organization {
	id: string;
	name: string;
	slug: string;
	status: OrganizationStatus;
	created_at: string;
	updated_at: string;
}

export interface Department {
	organization_id: string;
	id: string;
	code: string | null;
	name: string;
	parent_id: string | null;
	created_at: string;
	updated_at: string;
	created_by: string | null;
	updated_by: string | null;
}

/** Money and rates arrive as JSON numbers from Postgres numeric — never floats server-side. */
export interface Employee {
	organization_id: string;
	id: string;
	employee_code: string;
	user_id: string | null;
	department_id: string | null;
	team_id: string | null;
	designation_id: string | null;
	manager_id: string | null;
	full_name: string;
	email: string;
	phone: string | null;
	gender: 'male' | 'female' | 'other' | 'undisclosed';
	date_of_birth: string | null;
	status: EmployeeStatus;
	employment_type: EmploymentType;
	hired_on: string | null;
	confirmed_on: string | null;
	exited_on: string | null;
	pan: string | null;
	aadhaar_last4: string | null;
	uan: string | null;
	pf_number: string | null;
	esi_number: string | null;
	bank_account: string | null;
	bank_ifsc: string | null;
	address: string | null;
	created_at: string;
	updated_at: string;
	created_by: string | null;
	updated_by: string | null;
}

/** Travels with every response. Pagination fields appear only on lists. */
export interface Meta {
	request_id?: string;
	total?: number;
	limit?: number;
	offset?: number;
}

/** Every successful response is `{ data, meta }`. */
export interface Envelope<T> {
	data: T;
	meta: Meta;
}

/** Mirrors the Kind constants in `api/internal/httpx/errors.go`. */
export type ErrorKind =
	| 'validation'
	| 'unauthenticated'
	| 'forbidden'
	| 'not_found'
	| 'method_not_allowed'
	| 'conflict'
	| 'rule_violation'
	| 'rate_limited'
	| 'internal';

export interface ErrorPayload {
	kind: ErrorKind;
	message: string;
	/** Stable identifier such as "employee.email_taken". */
	code?: string;
	/** Per-field validation messages, keyed by JSON field name. */
	fields?: Record<string, string>;
}

export interface ErrorEnvelope {
	error: ErrorPayload;
	meta: Meta;
}

export interface Health {
	status: string;
	db: string;
	env: string;
}

export interface Ping {
	message: string;
	env: string;
}
