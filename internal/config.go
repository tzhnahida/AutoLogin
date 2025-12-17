package config

import (
	"log"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

type Config struct {
	Auth AuthConfig `toml:"auth"`
	API  APIConfig  `toml:"api"`
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
			TestURL:  "www.baidu.com",
		},
	}
}

func LoadConfig(path string) (Config, error) {
	var cfg Config
	_, err := os.Stat(path)
	if os.IsNotExist(err) {
		cfg = defaultConfig()
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return cfg, err
		}
		file, err := os.Create(path)
		if err != nil {
			return cfg, err
		}
		defer file.Close()
		if err := toml.NewEncoder(file).Encode(cfg); err != nil {
			return cfg, err
		}
		log.Fatal("config file created, using default config")
	}
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return cfg, err
	}
	return cfg, nil
}
