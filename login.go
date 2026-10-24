package autologin

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/cookiejar"
	url2 "net/url"
	"regexp"
	"strings"
	"time"
)

var (
	ErrRedirectURLNotFound = errors.New("redirect URL not found in response body")
	ErrHTTPStatusNotOK     = errors.New("http status not OK")
	ErrHTTPTestURLGet      = errors.New("http test URL get error")
	ErrLoginFailed         = errors.New("authentication failed")
)

// requestTimeout bounds every portal HTTP call, mirroring the shell version's
// curl --max-time: while offline, absent or blackholed answers must not hang
// the daemon for minutes.
const requestTimeout = 20 * time.Second

// servicesToTry is used when the config leaves service empty: a wrong service
// name is rejected harmlessly, so try each known one in turn.
var servicesToTry = []string{"校园联通", "校园电信", "校园移动", "校园无线"}

var reLocation = regexp.MustCompile(`location\.href='([^']+)'`)

type LoginResponse struct {
	UserIndex         string      `json:"userIndex"`
	Result            string      `json:"result"`
	Message           string      `json:"message"`
	Forwordurl        interface{} `json:"forwordurl"`
	KeepaliveInterval int         `json:"keepaliveInterval"`
	CasFailErrString  interface{} `json:"casFailErrString"`
	ValidCodeURL      string      `json:"validCodeUrl"`
}

// newClient builds the shared portal HTTP client: the portal hands out
// session cookies across the redirect and the login POST, so all calls share
// one cookie jar, and every call is bounded by requestTimeout.
func newClient() (*http.Client, error) {
	jar, err := cookiejar.New(nil)
	if err != nil {
		return nil, err
	}
	return &http.Client{
		Jar:     jar,
		Timeout: requestTimeout,
	}, nil
}

// drainAndClose empties the body so the connection can be reused, then
// closes it.
func drainAndClose(resp *http.Response) {
	if resp == nil || resp.Body == nil {
		return
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
}

func CheckNetworkConnectivityWithURL(client *http.Client, cfg *Config) error {
	slog.Info("Checking network connectivity...")
	resp, err := client.Get(cfg.API.TestURL)
	if err != nil {
		slog.Error(err.Error())
		return ErrHTTPTestURLGet
	}
	drainAndClose(resp)
	if resp.StatusCode != http.StatusOK {
		slog.Warn("Network connectivity check failed. Host is unreachable.")
		return ErrHTTPStatusNotOK
	}
	slog.Info("Network connectivity check passed. Network is reachable.")
	return nil
}

// portalRedirect fetches portalURL (following redirects) and extracts the
// location.href jump target from the response body.
func portalRedirect(client *http.Client, portalURL string) (string, error) {
	resp, err := client.Get(portalURL)
	if err != nil {
		slog.Error(err.Error())
		return "", err
	}
	content, err := io.ReadAll(resp.Body)
	drainAndClose(resp)
	if err != nil {
		slog.Error(err.Error())
		return "", err
	}
	m := reLocation.FindStringSubmatch(string(content))
	if len(m) < 2 {
		slog.Warn("No redirect URL was acquired from " + portalURL + ".")
		return "", ErrRedirectURLNotFound
	}
	return m[1], nil
}

// extractOrigin keeps the scheme://host part of a portal jump URL.
func extractOrigin(rawURL string) string {
	u, err := url2.Parse(rawURL)
	if err != nil {
		return ""
	}
	if u.Scheme == "" || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
}

func FetchQueryString(client *http.Client, cfg *Config) (string, error) {
	redirectURL, err := portalRedirect(client, cfg.API.BaseURL)
	if err != nil {
		// The configured portal refused or served no redirect page (e.g.
		// after moving to another campus network). A plain-HTTP trigger URL
		// gets hijacked to whichever portal is active, so adopt that one.
		slog.Warn("Trying portal auto-detection via " + cfg.API.TriggerURL + "...")
		redirectURL, err = portalRedirect(client, cfg.API.TriggerURL)
		if err != nil {
			return "", err
		}
		origin := extractOrigin(redirectURL)
		if origin == "" {
			return "", ErrRedirectURLNotFound
		}
		slog.Info("Detected portal: " + origin)
		cfg.API.BaseURL = origin
		cfg.API.LoginURL = origin + "/eportal/InterFace.do?method=login"
	}

	resp, err := client.Get(redirectURL)
	if err != nil {
		slog.Error(err.Error())
		return "", err
	}
	queryString := resp.Request.URL.RawQuery
	drainAndClose(resp)
	if queryString == "" {
		return "", errors.New("query string not found")
	}
	slog.Info("Successfully obtained the query string.")
	return queryString, nil
}

func AuthenticateWithCredentials(client *http.Client, cfg *Config, service, queryString string) error {
	data := url2.Values{}
	data.Set("userId", cfg.Auth.UserID)
	data.Set("password", cfg.Auth.Password)
	data.Set("service", url2.QueryEscape(service))
	data.Set("queryString", url2.QueryEscape(queryString))
	data.Set("operatorPwd", "")
	data.Set("operatorUserId", "")
	data.Set("validcode", "")
	data.Set("passwordEncrypt", "false")

	slog.Info("Authenticating.", "service", service)
	resp, err := client.Post(cfg.API.LoginURL, "application/x-www-form-urlencoded; charset=UTF-8", strings.NewReader(data.Encode()))
	if err != nil {
		slog.Error(err.Error())
		return err
	}
	content, err := io.ReadAll(resp.Body)
	drainAndClose(resp)
	if err != nil {
		slog.Error(err.Error())
		return err
	}
	var loginResp LoginResponse
	if err := json.Unmarshal(content, &loginResp); err != nil {
		slog.Error(err.Error())
		return err
	}
	if loginResp.Result != "success" {
		slog.Warn("Authentication failed.", "service", service, "message", loginResp.Message)
		return ErrLoginFailed
	}
	slog.Info("Authentication succeeded.", "service", service)
	return nil
}

// AttemptAuthentication fetches the portal query string and tries the
// configured service; with service left empty every known service name is
// tried in turn against the same query string.
func AttemptAuthentication(client *http.Client, cfg *Config) error {
	queryString, err := FetchQueryString(client, cfg)
	if err != nil {
		return fmt.Errorf("fetch query string: %w", err)
	}
	if cfg.Auth.Service != "" {
		return AuthenticateWithCredentials(client, cfg, cfg.Auth.Service, queryString)
	}
	var lastErr error
	for _, svc := range servicesToTry {
		if err := AuthenticateWithCredentials(client, cfg, svc, queryString); err == nil {
			return nil
		} else {
			lastErr = err
		}
	}
	return lastErr
}
