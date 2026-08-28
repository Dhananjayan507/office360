/** Mirrors the JSON shapes returned by the Go API (`internal/db/models.go`). */

export type EmployeeStatus = 'active' | 'on_leave' | 'exited';

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
	id: string;
	organization_id: string;
	name: string;
	created_at: string;
}

export interface Employee {
	id: string;
	organization_id: string;
	department_id: string | null;
	full_name: string;
	email: string;
	title: string | null;
	status: EmployeeStatus;
	hired_on: string | null;
	created_at: string;
	updated_at: string;
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
