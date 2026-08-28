package httpapi

import (
	"context"
	"net/http"
	"time"

	"github.com/Dhananjayan507/office360/internal/httpx"
)

type healthBody struct {
	Status string `json:"status"`
	DB     string `json:"db"`
	Env    string `json:"env"`
}

type pingBody struct {
	Message string `json:"message"`
	Env     string `json:"env"`
}

// health reports liveness. It is one of the few endpoints that picks its own
// status code, because here the status *is* the answer — a monitor reads the
// 503 without parsing the body.
func (s *Server) health(w http.ResponseWriter, r *http.Request) error {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	body := healthBody{Status: "ok", DB: "up", Env: s.cfg.Env}
	status := http.StatusOK

	if err := s.txn.Pool().Ping(ctx); err != nil {
		body.Status, body.DB = "degraded", "down"
		status = http.StatusServiceUnavailable
	}

	return httpx.Write(w, r, status, body, nil)
}

// ping answers without touching the database, so it distinguishes "the process
// is up" from "the process can reach Postgres".
func (s *Server) ping(w http.ResponseWriter, r *http.Request) error {
	return httpx.OK(w, r, pingBody{Message: "pong", Env: s.cfg.Env}, nil)
}
