// Package httpapi assembles the chi router and the handlers that sit on the
// sqlc query layer. All response and error shaping goes through internal/httpx.
package httpapi

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Dhananjayan507/office360/api/internal/config"
	"github.com/Dhananjayan507/office360/api/internal/db"
	"github.com/Dhananjayan507/office360/api/internal/httpx"
)

type Server struct {
	cfg  config.Config
	pool *pgxpool.Pool
	q    *db.Queries
}

func NewServer(cfg config.Config, pool *pgxpool.Pool) *Server {
	return &Server{cfg: cfg, pool: pool, q: db.New(pool)}
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()

	// Order matters: RequestID must precede the logger so every line carries an
	// id, and Recoverer must sit inside them so a panic is still logged.
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(httpx.RequestLogger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   s.cfg.CORSOrigins,
		AllowedMethods:   []string{http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete, http.MethodOptions},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/healthz", httpx.Handle(s.health))

	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/ping", httpx.Handle(s.ping))

		r.Route("/departments", func(r chi.Router) {
			r.Get("/", httpx.Handle(s.listDepartments))
			r.Post("/", httpx.Handle(s.createDepartment))
			r.Delete("/{id}", httpx.Handle(s.deleteDepartment))
		})

		r.Route("/employees", func(r chi.Router) {
			r.Get("/", httpx.Handle(s.listEmployees))
			r.Post("/", httpx.Handle(s.createEmployee))
			r.Get("/{id}", httpx.Handle(s.getEmployee))
			r.Patch("/{id}", httpx.Handle(s.updateEmployee))
			r.Delete("/{id}", httpx.Handle(s.deleteEmployee))
		})
	})

	r.NotFound(httpx.Handle(func(_ http.ResponseWriter, _ *http.Request) error {
		return httpx.NotFound("route not found")
	}))
	r.MethodNotAllowed(httpx.Handle(func(_ http.ResponseWriter, _ *http.Request) error {
		return httpx.MethodNotAllowed("method not allowed for this route")
	}))

	return r
}
