/** Mirrors the JSON shapes returned by the Go API (`api/internal/db/models.go`). */

export type EmployeeStatus = 'active' | 'on_leave' | 'exited';

export interface Department {
	id: string;
	name: string;
	created_at: string;
}

export interface Employee {
	id: string;
	department_id: string | null;
	full_name: string;
	email: string;
	title: string | null;
	status: EmployeeStatus;
	hired_on: string | null;
	created_at: string;
	updated_at: string;
}

export interface ListResponse<T> {
	data: T[];
	total: number;
	limit: number;
	offset: number;
}

export interface Health {
	status: string;
	db: string;
	env: string;
}
