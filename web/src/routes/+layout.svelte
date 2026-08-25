<script lang="ts">
	import favicon from '$lib/assets/favicon.svg';
	import '../app.css';

	let { children } = $props();
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

<div class="shell">
	<header>
		<a class="brand" href="/">office<span>360</span></a>
		<nav>
			<a href="/">Employees</a>
		</nav>
	</header>

	<main>
		{@render children()}
	</main>
</div>

<style>
	.shell {
		max-width: 68rem;
		margin: 0 auto;
		padding: 0 1.25rem 3rem;
	}

	header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		padding: 1.25rem 0;
		border-bottom: 1px solid var(--border);
	}

	.brand {
		font-size: 1.15rem;
		font-weight: 700;
		letter-spacing: -0.02em;
		text-decoration: none;
		color: var(--text);
	}

	.brand span {
		color: var(--accent);
	}

	nav {
		display: flex;
		gap: 1rem;
		font-size: 0.9rem;
	}

	main {
		padding-top: 1.75rem;
	}
</style>
