import { env } from '$env/dynamic/public';
import type { Department, Employee, EmployeeStatus, Health, ListResponse } from './types';

/** SvelteKit hands `load` a special fetch; pass it through so SSR requests are traced. */
type Fetcher = typeof globalThis.fetch;

interface Options {
	fetch?: Fetcher;
}

export class ApiError extends Error {
	constructor(
		readonly status: number,
		message: string
	) {
		super(message);
		this.name = 'ApiError';
	}
}

function baseUrl(): string {
	return (env.PUBLIC_API_URL ?? 'http://localhost:8080').replace(/\/$/, '');
}

async function request<T>(
	path: string,
	{ fetch: doFetch = globalThis.fetch, ...init }: RequestInit & Options = {}
): Promise<T> {
	const res = await doFetch(`${baseUrl()}${path}`, {
		...init,
		headers: { 'Content-Type': 'application/json', ...init.headers }
	});

	if (!res.ok) {
		let message = `${res.status} ${res.statusText}`;
		try {
			const body = await res.json();
			if (body?.error) message = body.error;
		} catch {
			// Error body was not JSON — keep the status line.
		}
		throw new ApiError(res.status, message);
	}

	if (res.status === 204) return undefined as T;
	return (await res.json()) as T;
}

function queryString(params: Record<string, string | number | undefined>): string {
	const search = new URLSearchParams();
	for (const [key, value] of Object.entries(params)) {
		if (value !== undefined && value !== '') search.set(key, String(value));
	}
	const qs = search.toString();
	return qs ? `?${qs}` : '';
}

export const health = (opts: Options = {}) => request<Health>('/healthz', opts);

export const listDepartments = (opts: Options = {}) =>
	request<ListResponse<Department>>('/api/v1/departments', opts);

export const createDepartment = (name: string, opts: Options = {}) =>
	request<Department>('/api/v1/departments', {
		...opts,
		method: 'POST',
		body: JSON.stringify({ name })
	});

export const deleteDepartment = (id: string, opts: Options = {}) =>
	request<void>(`/api/v1/departments/${id}`, { ...opts, method: 'DELETE' });

export interface ListEmployeesQuery {
	department_id?: string;
	status?: EmployeeStatus;
	limit?: number;
	offset?: number;
}

export const listEmployees = (query: ListEmployeesQuery = {}, opts: Options = {}) =>
	request<ListResponse<Employee>>(`/api/v1/employees${queryString({ ...query })}`, opts);

export const getEmployee = (id: string, opts: Options = {}) =>
	request<Employee>(`/api/v1/employees/${id}`, opts);

export interface CreateEmployeeInput {
	full_name: string;
	email: string;
	department_id?: string | null;
	title?: string | null;
	status?: EmployeeStatus;
	/** YYYY-MM-DD */
	hired_on?: string | null;
}

export const createEmployee = (input: CreateEmployeeInput, opts: Options = {}) =>
	request<Employee>('/api/v1/employees', {
		...opts,
		method: 'POST',
		body: JSON.stringify(input)
	});

export const updateEmployee = (
	id: string,
	input: Partial<CreateEmployeeInput>,
	opts: Options = {}
) =>
	request<Employee>(`/api/v1/employees/${id}`, {
		...opts,
		method: 'PATCH',
		body: JSON.stringify(input)
	});

export const deleteEmployee = (id: string, opts: Options = {}) =>
	request<void>(`/api/v1/employees/${id}`, { ...opts, method: 'DELETE' });
