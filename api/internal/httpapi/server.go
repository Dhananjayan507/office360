// Package httpapi wires the chi router and HTTP handlers onto the sqlc query layer.
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

	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   s.cfg.CORSOrigins,
		AllowedMethods:   []string{http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete, http.MethodOptions},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/healthz", s.health)

	r.Route("/api/v1", func(r chi.Router) {
		r.Route("/departments", func(r chi.Router) {
			r.Get("/", s.listDepartments)
			r.Post("/", s.createDepartment)
			r.Delete("/{id}", s.deleteDepartment)
		})

		r.Route("/employees", func(r chi.Router) {
			r.Get("/", s.listEmployees)
			r.Post("/", s.createEmployee)
			r.Get("/{id}", s.getEmployee)
			r.Patch("/{id}", s.updateEmployee)
			r.Delete("/{id}", s.deleteEmployee)
		})
	})

	r.NotFound(func(w http.ResponseWriter, _ *http.Request) {
		writeError(w, http.StatusNotFound, "route not found")
	})
	r.MethodNotAllowed(func(w http.ResponseWriter, _ *http.Request) {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	})

	return r
}
