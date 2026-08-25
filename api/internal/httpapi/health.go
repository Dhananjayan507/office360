package httpapi

import (
	"context"
	"net/http"
	"time"
)

type healthBody struct {
	Status string `json:"status"`
	DB     string `json:"db"`
	Env    string `json:"env"`
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	body := healthBody{Status: "ok", DB: "up", Env: s.cfg.Env}
	status := http.StatusOK

	if err := s.pool.Ping(ctx); err != nil {
		body.Status, body.DB = "degraded", "down"
		status = http.StatusServiceUnavailable
	}

	writeJSON(w, status, body)
}
