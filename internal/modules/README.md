# internal/modules

One directory per business domain. Every module is the same five files:

```
queries.sql       hand-written SQL, compiled by sqlc
domain.go         entities and validation rules; no database, no clock
service.go        use cases; owns the transaction, enforces scope, writes audit
handler.go        decode, validate, call ONE service method, respond
service_test.go   tests against the service, not the handler
```

The layering rule, in one line: **handlers never write SQL, services own the
transaction, domain never touches the database.**

`hr/` is built first (Day 6) and is the reference every later module copies.
When adding a module, point Claude at it: *"follow `internal/modules/hr`
exactly"* produces code that fits; *"write me a projects module"* produces code
you then have to reshape.

Empty until Day 6.
