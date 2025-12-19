package main

import (
	"flag"
	"log"
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
			log.Fatalln(err)
		}
		dir, _ := filepath.Split(path)
		err = os.Chdir(dir)
		if err != nil {
			log.Fatalln(err)
		}
	}

	cfg, err := autologin.LoadConfig(autologin.CfgPath)
	if err != nil {
		log.Fatalf("config read failed: %v", err)
	}
	svcConfig := &service.Config{
		Name:        cfg.Service.Name,
		DisplayName: cfg.Service.DisplayName,
		Description: cfg.Service.Description,
	}
	prg := autologin.NewProgram(&cfg)
	s, err := service.New(prg, svcConfig)
	if err != nil {
		log.Fatal(err)
	}
	switch {
	case install:
		err = s.Install()
		if err != nil {
			log.Println(err)
		}
	case uninstall:
		err = s.Uninstall()
		if err != nil {
			log.Println(err)
		}
	default:
		autologin.Logger, err = s.Logger(nil)
		if err != nil {
			log.Fatal(err)
		}
		err = s.Run()
		if err != nil {
			autologin.Logger.Error(err)
		}

	}
}
