import { listDepartments, listEmployees } from '$lib/api';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch }) => {
	try {
		const [employees, departments] = await Promise.all([
			listEmployees({}, { fetch }),
			listDepartments({ fetch })
		]);

		return {
			employees: employees.data,
			total: employees.meta.total ?? employees.data.length,
			departments: departments.data,
			apiError: null as string | null
		};
	} catch (err) {
		// The API being down is an expected first-run state, not a page crash —
		// render the empty dashboard with a hint instead of a 500.
		return {
			employees: [],
			total: 0,
			departments: [],
			apiError: err instanceof Error ? err.message : 'API unreachable'
		};
	}
};
