import { env } from '$env/dynamic/public';
import type {
	Department,
	Employee,
	EmployeeStatus,
	Envelope,
	ErrorKind,
	Health,
	Ping
} from './types';

/** SvelteKit hands `load` a special fetch; pass it through so SSR requests are traced. */
type Fetcher = typeof globalThis.fetch;

interface Options {
	fetch?: Fetcher;
}

/**
 * Mirrors the error envelope from `api/internal/httpx`. `kind` is the stable
 * thing to branch on — status codes are derived from it, not the other way round.
 */
export class ApiError extends Error {
	constructor(
		readonly status: number,
		readonly kind: ErrorKind,
		message: string,
		readonly code?: string,
		readonly fields?: Record<string, string>,
		readonly requestId?: string
	) {
		super(message);
		this.name = 'ApiError';
	}

	/** Message for a specific form field, when the API reported one. */
	fieldError(name: string): string | undefined {
		return this.fields?.[name];
	}
}

function baseUrl(): string {
	return (env.PUBLIC_API_URL ?? 'http://localhost:8080').replace(/\/$/, '');
}

/**
 * Identifies the organisation every request acts within.
 *
 * INTERIM, and the mirror of `currentOrganization` in `internal/httpapi/tenant.go`.
 * Day 3 adds login and Day 4 moves this onto the session token; at that point the
 * header disappears from here and `PUBLIC_DEV_ORGANIZATION_ID` leaves `.env`.
 * The API fails closed, so with no value configured every call returns 401.
 */
function tenantHeaders(): Record<string, string> {
	const org = env.PUBLIC_DEV_ORGANIZATION_ID;
	return org ? { 'X-Organization-Id': org } : {};
}

async function request<T>(
	path: string,
	{ fetch: doFetch = globalThis.fetch, ...init }: RequestInit & Options = {}
): Promise<Envelope<T>> {
	const res = await doFetch(`${baseUrl()}${path}`, {
		...init,
		headers: { 'Content-Type': 'application/json', ...tenantHeaders(), ...init.headers }
	});

	if (res.status === 204) return { data: undefined as T, meta: {} };

	let body: unknown;
	try {
		body = await res.json();
	} catch {
		throw new ApiError(res.status, 'internal', `${res.status} ${res.statusText}`);
	}

	if (!res.ok) {
		const { error, meta } = (body ?? {}) as Partial<import('./types').ErrorEnvelope>;
		throw new ApiError(
			res.status,
			error?.kind ?? 'internal',
			error?.message ?? `${res.status} ${res.statusText}`,
			error?.code,
			error?.fields,
			meta?.request_id
		);
	}

	return body as Envelope<T>;
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

export const ping = (opts: Options = {}) => request<Ping>('/api/v1/ping', opts);

export const listDepartments = (opts: Options = {}) =>
	request<Department[]>('/api/v1/departments', opts);

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
	request<Employee[]>(`/api/v1/employees${queryString({ ...query })}`, opts);

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
