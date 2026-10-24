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
	// Resolve the config path against the caller's working directory before
	// changing it, so test runs and the installed service point at the same
	// file.
	if abs, err := filepath.Abs(autologin.CfgPath); err == nil {
		autologin.CfgPath = abs
	}

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
		os.Exit(1)
	}
	svcConfig := &service.Config{
		Name:        cfg.Service.Name,
		DisplayName: cfg.Service.DisplayName,
		Description: cfg.Service.Description,
		// The installed service must start with the same -config the user
		// installed with; without this the flag is silently lost and the
		// service falls back to config.toml next to the binary.
		Arguments: []string{"-config", autologin.CfgPath},
	}
	prg := autologin.NewProgram(&cfg)
	s, err := service.New(prg, svcConfig)
	if err != nil {
		slog.Error(err.Error())
		os.Exit(1)
	}
	switch {
	case install:
		err = s.Install()
		if err != nil {
			slog.Error(err.Error())
			os.Exit(1)
		}
		slog.Info("Service registration in progress.")
	case uninstall:
		err = s.Uninstall()
		if err != nil {
			slog.Error(err.Error())
			os.Exit(1)
		}
		slog.Info("Service uninstall in progress.")
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
