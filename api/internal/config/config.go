// Package config loads runtime configuration from the environment.
package config

import (
	"errors"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	DatabaseURL string
	Port        string
	Env         string
	CORSOrigins []string
}

// Load reads configuration from the environment, falling back to a .env file
// when one is present. Real deployments inject variables directly, so a missing
// .env is never an error.
func Load() (Config, error) {
	// Loaded one at a time: godotenv.Load stops at the first missing file, and
	// earlier files win, so the repo root .env applies when running from ./api.
	for _, path := range []string{".env", "../.env", "../../.env"} {
		_ = godotenv.Load(path)
	}

	cfg := Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		Port:        envOr("API_PORT", "8080"),
		Env:         envOr("API_ENV", "development"),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("DATABASE_URL is required (copy .env.example to .env)")
	}

	for _, origin := range strings.Split(envOr("CORS_ORIGINS", "http://localhost:5173"), ",") {
		if origin = strings.TrimSpace(origin); origin != "" {
			cfg.CORSOrigins = append(cfg.CORSOrigins, origin)
		}
	}

	return cfg, nil
}

func (c Config) IsProduction() bool { return c.Env == "production" }

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
