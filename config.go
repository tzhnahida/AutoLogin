package autologin

import (
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
	BaseURL  string `toml:"base_url"`
	LoginURL string `toml:"login_url"`
	TestURL  string `toml:"test_url"`
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
			BaseURL:  "http://210.27.177.172",
			LoginURL: "http://210.27.177.172/eportal/InterFace.do?method=login",
			TestURL:  "https://www.baidu.com",
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

func LoadConfig(path string) (Config, error) {
	var cfg Config
	_, err := toml.DecodeFile(path, &cfg)
	if err != nil {
		return cfg, err
	}
	return cfg, nil
}
