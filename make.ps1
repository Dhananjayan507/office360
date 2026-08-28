<#
.SYNOPSIS
    Task runner for office360. Run  .\make.ps1 <task>

.DESCRIPTION
    Tasks:
      up          Start Postgres 16 in Docker (detached) and wait for health
      down        Stop the Postgres container (data is preserved)
      nuke        Stop the container AND delete its volume — DESTROYS local data
      migrate     Apply all pending migrations
      rollback    Roll back the most recent migration
      seed        Insert the demo organisation and a few rows (idempotent)
      sqlc        Regenerate api/internal/db from db/query + db/migrations
      api         Run the Go API on $API_PORT (default 8080)
      web         Run the SvelteKit dev server on 5173
      check       Build + vet the Go API and type-check the web app
      psql        Open a psql shell inside the Postgres container
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'down', 'nuke', 'migrate', 'rollback', 'seed', 'sqlc', 'api', 'web', 'check', 'psql')]
    [string]$Task = 'check'
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

function Import-DotEnv {
    $envFile = Join-Path $Root '.env'
    if (-not (Test-Path $envFile)) {
        # Keep this file pure ASCII: PowerShell 5.1 reads .ps1 as Windows-1252
        # unless there is a BOM, and a UTF-8 em dash decodes into a smart quote
        # that silently unbalances every string after it.
        Write-Warning ".env not found - copying from .env.example"
        Copy-Item (Join-Path $Root '.env.example') $envFile
    }
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $name = $Matches[1]
            $value = $Matches[2].Trim().Trim('"')
            Set-Item -Path "env:$name" -Value $value
        }
    }
}

function Assert-LastExit($what) {
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}

Import-DotEnv

switch ($Task) {
    'up' {
        docker compose up -d
        Assert-LastExit 'docker compose up'
        Write-Host 'Waiting for Postgres to report healthy...' -ForegroundColor Cyan
        $deadline = (Get-Date).AddSeconds(90)
        do {
            Start-Sleep -Seconds 2
            $state = docker inspect -f '{{.State.Health.Status}}' office360-postgres 2>$null
        } while ($state -ne 'healthy' -and (Get-Date) -lt $deadline)
        if ($state -ne 'healthy') { throw "Postgres did not become healthy (last state: '$state')" }
        Write-Host "Postgres healthy on localhost:$($env:POSTGRES_PORT)" -ForegroundColor Green
    }

    'down' { docker compose down; Assert-LastExit 'docker compose down' }

    'nuke' {
        Write-Host 'This deletes the office360 Postgres volume and all local data.' -ForegroundColor Yellow
        if ((Read-Host "Type 'yes' to continue") -ne 'yes') { Write-Host 'Aborted.'; break }
        docker compose down -v
        Assert-LastExit 'docker compose down -v'
    }

    'migrate' {
        # Uses ./cmd/migrate rather than the golang-migrate CLI, so a bare
        # checkout needs nothing on PATH beyond Go itself.
        Push-Location $Root
        try { go run ./cmd/migrate up; Assert-LastExit 'migrate up' } finally { Pop-Location }
    }

    'rollback' {
        Push-Location $Root
        try { go run ./cmd/migrate down 1; Assert-LastExit 'migrate down' } finally { Pop-Location }
    }

    'seed' {
        # Development rows only, and idempotent - see internal/db/seed/dev.sql.
        Get-Content (Join-Path $Root 'internal\db\seed\dev.sql') -Raw |
            docker exec -i office360-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1
        Assert-LastExit 'seed'
        Write-Host 'Seeded the demo organisation.' -ForegroundColor Green
    }

    'sqlc' {
        Push-Location $Root
        try { sqlc generate; Assert-LastExit 'sqlc generate' } finally { Pop-Location }
        Write-Host 'Regenerated internal/db' -ForegroundColor Green
    }

    'api' {
        Push-Location $Root
        try { go run ./cmd/server } finally { Pop-Location }
    }

    'web' {
        Push-Location (Join-Path $Root 'web')
        try { npm run dev } finally { Pop-Location }
    }

    'check' {
        Push-Location $Root
        try {
            go build ./...; Assert-LastExit 'go build'
            go vet ./...; Assert-LastExit 'go vet'
            # Database-backed tests skip themselves when Postgres is unreachable,
            # so this stays runnable without the container.
            go test ./...; Assert-LastExit 'go test'
        } finally { Pop-Location }

        Push-Location (Join-Path $Root 'web')
        try { npm run check; Assert-LastExit 'svelte-check' } finally { Pop-Location }

        Write-Host 'All checks passed.' -ForegroundColor Green
    }

    'psql' {
        docker exec -it office360-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB
    }
}
