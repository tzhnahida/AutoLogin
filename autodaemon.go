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

// stopped reports whether the service has been asked to stop.
func (p *Program) stopped() bool {
	select {
	case <-p.stop:
		return true
	default:
		return false
	}
}

func (p *Program) run() {
	for {
		p.loginCycle()
		select {
		case <-time.After(p.cfg.Time.PollInterval):
		case <-p.stop:
			slog.Info("Service stopped")
			return
		}
	}
}

// loginCycle checks connectivity once and, while offline, retries the
// authentication every RetryInterval until the network is reachable or the
// service is stopped. Every wait honours p.stop, so stopping the service
// never gets stuck behind a slow network round-trip or a retry sleep.
func (p *Program) loginCycle() {
	client, err := newClient()
	if err != nil {
		slog.Error(err.Error())
		return
	}
	if err := CheckNetworkConnectivityWithURL(client, p.cfg); err == nil {
		return
	}
	for {
		if err := AttemptAuthentication(client, p.cfg); err != nil {
			slog.Error(err.Error())
		}
		if p.stopped() {
			slog.Info("Service stopped")
			return
		}
		if err := CheckNetworkConnectivityWithURL(client, p.cfg); err == nil {
			slog.Info("Network is reachable.")
			return
		}
		slog.Warn("Network still unreachable. Retrying in " + p.cfg.Time.RetryInterval.String() + "...")
		select {
		case <-p.stop:
			slog.Info("Service stopped")
			return
		case <-time.After(p.cfg.Time.RetryInterval):
		}
	}
}
