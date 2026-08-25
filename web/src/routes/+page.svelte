<script lang="ts">
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const byId = $derived(new Map(data.departments.map((d) => [d.id, d.name])));

	const statusLabels: Record<string, string> = {
		active: 'Active',
		on_leave: 'On leave',
		exited: 'Exited'
	};
</script>

<svelte:head>
	<title>Employees · office360</title>
</svelte:head>

<h1>Employees</h1>
<p class="sub">{data.total} record{data.total === 1 ? '' : 's'} · {data.departments.length} department{data.departments.length === 1 ? '' : 's'}</p>

{#if data.apiError}
	<div class="notice">
		<strong>Can't reach the API.</strong>
		<span>{data.apiError}</span>
		<code>docker compose up -d &amp;&amp; cd api &amp;&amp; go run ./cmd/server</code>
	</div>
{:else if data.employees.length === 0}
	<div class="empty">
		<p>No employees yet.</p>
		<code
			>curl -X POST http://localhost:8080/api/v1/employees -H "Content-Type: application/json" -d
			'&#123;"full_name":"Ada Lovelace","email":"ada@office360.dev"&#125;'</code
		>
	</div>
{:else}
	<table>
		<thead>
			<tr>
				<th>Name</th>
				<th>Email</th>
				<th>Department</th>
				<th>Title</th>
				<th>Status</th>
			</tr>
		</thead>
		<tbody>
			{#each data.employees as employee (employee.id)}
				<tr>
					<td class="name">{employee.full_name}</td>
					<td>{employee.email}</td>
					<td>{employee.department_id ? (byId.get(employee.department_id) ?? '—') : '—'}</td>
					<td>{employee.title ?? '—'}</td>
					<td><span class="badge {employee.status}">{statusLabels[employee.status] ?? employee.status}</span></td>
				</tr>
			{/each}
		</tbody>
	</table>
{/if}

<style>
	h1 {
		margin: 0;
		font-size: 1.5rem;
		letter-spacing: -0.02em;
	}

	.sub {
		margin: 0.25rem 0 1.5rem;
		color: var(--muted);
		font-size: 0.9rem;
	}

	.notice,
	.empty {
		display: grid;
		gap: 0.6rem;
		justify-items: start;
		padding: 1.25rem;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 10px;
	}

	.notice strong {
		color: var(--danger);
	}

	.notice span {
		color: var(--muted);
		font-size: 0.9rem;
	}

	code {
		display: block;
		max-width: 100%;
		overflow-x: auto;
		padding: 0.5rem 0.7rem;
		background: var(--bg);
		border: 1px solid var(--border);
		border-radius: 6px;
		font-size: 0.8rem;
		white-space: pre-wrap;
		word-break: break-word;
	}

	table {
		width: 100%;
		border-collapse: collapse;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 10px;
		overflow: hidden;
		font-size: 0.9rem;
	}

	th {
		text-align: left;
		font-weight: 600;
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--muted);
	}

	th,
	td {
		padding: 0.7rem 0.9rem;
		border-bottom: 1px solid var(--border);
	}

	tbody tr:last-child td {
		border-bottom: none;
	}

	.name {
		font-weight: 600;
	}

	.badge {
		display: inline-block;
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		font-size: 0.75rem;
		font-weight: 600;
		border: 1px solid currentColor;
	}

	.badge.active {
		color: var(--ok);
	}
	.badge.on_leave {
		color: var(--warn);
	}
	.badge.exited {
		color: var(--muted);
	}
</style>
