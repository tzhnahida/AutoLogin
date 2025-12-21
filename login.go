package autologin

import (
	"encoding/json"
	"errors"
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
)

type LoginResponse struct {
	UserIndex         string      `json:"userIndex"`
	Result            string      `json:"result"`
	Message           string      `json:"message"`
	Forwordurl        interface{} `json:"forwordurl"`
	KeepaliveInterval int         `json:"keepaliveInterval"`
	CasFailErrString  interface{} `json:"casFailErrString"`
	ValidCodeURL      string      `json:"validCodeUrl"`
}

func CheckNetworkConnectivityWithURL(cfg *Config) error {
	resp, err := http.Get(cfg.API.TestURL)
	slog.Info("Checking network connectivity...")
	if err != nil {
		slog.Error(err.Error())
		return ErrHTTPTestURLGet
	}
	if resp.StatusCode != http.StatusOK {
		slog.Warn("Network connectivity check failed. Host is unreachable.")
		return ErrHTTPStatusNotOK
	}
	slog.Info("Network connectivity check passed. Network is reachable.")
	return nil
}

func FetchQueryString(client *http.Client, cfg *Config) (string, error) {
	resp, err := client.Get(cfg.API.BaseURL)
	if err != nil {
		slog.Error(err.Error())
		return "", err
	}

	content, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Error(err.Error())
		return "", err
	}

	re := regexp.MustCompile(`location\.href='([^']+)'`)
	matches := re.FindStringSubmatch(string(content))
	if len(matches) < 2 {
		slog.Warn("No redirect URL was acquired.")
		return "", ErrRedirectURLNotFound
	}

	redirectURL := matches[1]
	slog.Info("Successfully obtained the URL.")
	resp, err = client.Get(redirectURL)
	if err != nil {
		slog.Error(err.Error())
		return "", err
	}

	queryString := resp.Request.URL.RawQuery
	slog.Info("Successfully obtained the query string.")
	return queryString, nil

}

func AuthenticateWithCredentials(client *http.Client, cfg *Config, queryString string) error {
	data := url2.Values{}
	data.Set("userId", cfg.Auth.UserID)
	data.Set("password", cfg.Auth.Password)
	data.Set("service", url2.QueryEscape(cfg.Auth.Service))
	data.Set("queryString", url2.QueryEscape(queryString))
	data.Set("operatorPwd", "")
	data.Set("operatorUserId", "")
	data.Set("validcode", "")
	data.Set("passwordEncrypt", "false")

	slog.Info("Authenticating with credentials.")
	resp, err := client.Post(cfg.API.LoginURL, "application/x-www-form-urlencoded; charset=UTF-8", strings.NewReader(data.Encode()))
	if err != nil {
		slog.Error(err.Error())
		return err
	}
	content, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Error(err.Error())
		return err
	}
	var loginResp LoginResponse
	err = json.Unmarshal(content, &loginResp)
	if err != nil {
		return err
	}
	if loginResp.Result != "success" {
		slog.Warn("Authentication failed. Retrying...")
		ticker := time.NewTicker(cfg.Time.RetryInterval)
		select {
		case <-ticker.C:
			ticker.Stop()
			queryString, err := FetchQueryString(client, cfg)
			if err != nil {
				slog.Error(err.Error())
			}
			err = AuthenticateWithCredentials(client, cfg, queryString)
			if err != nil {
				slog.Error(err.Error())
			}
		}
	}
	return nil
}

func login(cfg *Config) error {
	jar, _ := cookiejar.New(nil)
	client := &http.Client{
		Jar: jar,
	}
	err := CheckNetworkConnectivityWithURL(cfg)
	if err == ErrHTTPStatusNotOK || err == ErrHTTPTestURLGet {
		queryString, err := FetchQueryString(client, cfg)
		if err != nil {
			slog.Error(err.Error())
		}
		err = AuthenticateWithCredentials(client, cfg, queryString)
		if err != nil {
			slog.Error(err.Error())
		}
	}
	return nil
}
