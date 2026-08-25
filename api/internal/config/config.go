// Package config loads runtime configuration from the environment.
package config

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

// MinJWTSecretLen is the shortest secret we accept. Below 256 bits an HMAC
// signing key is brute-forceable, so this is a hard floor rather than advice.
const MinJWTSecretLen = 32

type Config struct {
	DatabaseURL string
	JWTSecret   string
	Port        string
	Env         string
	CORSOrigins []string
}

// Load reads configuration from the environment, falling back to a .env file
// when one is present. Real deployments inject variables directly, so a missing
// .env is never an error — but a missing required variable always is.
func Load() (Config, error) {
	// Loaded one at a time: godotenv.Load stops at the first missing file, and
	// earlier files win, so the repo root .env applies when running from ./api.
	for _, path := range []string{".env", "../.env", "../../.env"} {
		_ = godotenv.Load(path)
	}

	cfg := Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		JWTSecret:   os.Getenv("JWT_SECRET"),
		Port:        envOr("API_PORT", "8080"),
		Env:         envOr("API_ENV", "development"),
	}

	if err := cfg.validate(); err != nil {
		return Config{}, err
	}

	for _, origin := range strings.Split(envOr("CORS_ORIGINS", "http://localhost:5173"), ",") {
		if origin = strings.TrimSpace(origin); origin != "" {
			cfg.CORSOrigins = append(cfg.CORSOrigins, origin)
		}
	}

	return cfg, nil
}

// validate fails the whole start-up rather than degrading. A server running
// without a signing secret would accept forged tokens, so there is no safe
// fallback to reach for here.
func (c Config) validate() error {
	if c.DatabaseURL == "" {
		return errors.New("DATABASE_URL is required (copy .env.example to .env)")
	}
	if c.JWTSecret == "" {
		return errors.New("JWT_SECRET is required (copy .env.example to .env)")
	}
	if len(c.JWTSecret) < MinJWTSecretLen {
		return fmt.Errorf("JWT_SECRET must be at least %d characters, got %d", MinJWTSecretLen, len(c.JWTSecret))
	}
	return nil
}

func (c Config) IsProduction() bool { return c.Env == "production" }

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
