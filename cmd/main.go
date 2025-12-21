package main

import (
	"flag"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/kardianos/service"

	"autologin"
)

var (
	install   bool
	uninstall bool
	test      bool
)

func init() {
	flag.StringVar(&autologin.CfgPath, "config", "config.toml", "config file path")
	flag.BoolVar(&install, "install", false, "install service")
	flag.BoolVar(&uninstall, "uninstall", false, "uninstall service")
	flag.BoolVar(&test, "test", false, "running with test mode")
	flag.Parse()
}

func main() {
	// change current path for service and prevent get invalid path when test
	if !test {
		path, err := os.Executable()
		if err != nil {
			slog.Error(err.Error())
		}
		dir, _ := filepath.Split(path)
		err = os.Chdir(dir)
		if err != nil {
			slog.Error(err.Error())
		}
	}

	cfg, err := autologin.LoadConfig(autologin.CfgPath)
	if err != nil {
		slog.Error(err.Error())
	}
	svcConfig := &service.Config{
		Name:        cfg.Service.Name,
		DisplayName: cfg.Service.DisplayName,
		Description: cfg.Service.Description,
	}
	prg := autologin.NewProgram(&cfg)
	s, err := service.New(prg, svcConfig)
	if err != nil {
		slog.Error(err.Error())
	}
	switch {
	case install:
		err = s.Install()
		slog.Info("Service registration in progress.")
		if err != nil {
			slog.Error(err.Error())
		}
	case uninstall:
		err = s.Uninstall()
		slog.Info("Service uninstall in progress.")
		if err != nil {
			slog.Error(err.Error())
		}
	default:
		autologin.Logger, err = s.Logger(nil)
		if err != nil {
			slog.Error(err.Error())
		}
		err = s.Run()
		if err != nil {
			err := autologin.Logger.Error(err)
			if err != nil {
				slog.Error(err.Error())
			}
		}

	}
}
