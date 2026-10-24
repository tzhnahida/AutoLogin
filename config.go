package autologin

import (
	"log/slog"
	"time"

	"github.com/BurntSushi/toml"
)

var (
	CfgPath string
)

type Config struct {
	Auth    AuthConfig    `toml:"auth"`
	API     APIConfig     `toml:"api"`
	Time    TimeConfig    `toml:"time"`
	Service ServiceConfig `toml:"service"`
}

type AuthConfig struct {
	UserID   string `toml:"user_id"`
	Password string `toml:"password"`
	Service  string `toml:"service"`
}

type APIConfig struct {
	BaseURL    string `toml:"base_url"`
	LoginURL   string `toml:"login_url"`
	TestURL    string `toml:"test_url"`
	TriggerURL string `toml:"trigger_url"`
}
type TimeConfig struct {
	PollInterval  time.Duration `toml:"poll_interval"`
	RetryInterval time.Duration `toml:"retry_interval"`
}

type ServiceConfig struct {
	Name        string `toml:"name"`
	Description string `toml:"description"`
	DisplayName string `toml:"display_name"`
}

func defaultConfig() Config {
	return Config{
		Auth: AuthConfig{
			UserID:   "UserID",
			Password: "Password",
			Service:  "Service",
		},
		API: APIConfig{
			BaseURL:    "http://210.27.177.172",
			LoginURL:   "http://210.27.177.172/eportal/InterFace.do?method=login",
			TestURL:    "https://www.baidu.com",
			TriggerURL: "http://www.baidu.com",
		},
		Time: TimeConfig{
			PollInterval:  time.Hour,
			RetryInterval: time.Minute,
		},
		Service: ServiceConfig{
			Name:        "AutoLogin",
			Description: "Go-based CLI tool for campus network authentication.",
			DisplayName: "AutoLogin Service",
		},
	}
}

// LoadConfig decodes path on top of the built-in defaults: fields missing
// from the file keep their default instead of collapsing to zero values (a
// zero PollInterval would panic time.NewTicker).
func LoadConfig(path string) (Config, error) {
	cfg := defaultConfig()
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return Config{}, err
	}
	if cfg.Time.PollInterval <= 0 {
		slog.Warn("poll_interval is not positive, falling back to 1h.")
		cfg.Time.PollInterval = time.Hour
	}
	if cfg.Time.RetryInterval <= 0 {
		slog.Warn("retry_interval is not positive, falling back to 1m.")
		cfg.Time.RetryInterval = time.Minute
	}
	return cfg, nil
}
