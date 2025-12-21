package autologin

import (
	"log/slog"
	"time"

	"github.com/kardianos/service"
)

var Logger service.Logger

type Program struct {
	stop chan struct{}
	cfg  *Config
}

func NewProgram(cfg *Config) *Program {
	return &Program{cfg: cfg}
}

func (p *Program) Start(s service.Service) error {
	p.stop = make(chan struct{})
	go p.run()
	return nil
}

func (p *Program) Stop(s service.Service) error {
	if p.stop != nil {
		close(p.stop)
	}
	return nil
}

func (p *Program) run() {
	if err := login(p.cfg); err != nil {
		slog.Error(err.Error())
	}

	ticker := time.NewTicker(p.cfg.Time.PollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			if err := login(p.cfg); err != nil {
				slog.Error(err.Error())
			}
		case <-p.stop:
			slog.Info("Service stopped")
			return
		}
	}
}
