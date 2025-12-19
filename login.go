package autologin

import (
	"encoding/json"
	"errors"
	"io"
	"log"
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
	if err != nil {
		return ErrHTTPTestURLGet
	}
	if resp.StatusCode != http.StatusOK {
		log.Println(resp.StatusCode)
		return ErrHTTPStatusNotOK
	}
	log.Println(resp.StatusCode)
	return nil
}

func FetchQueryString(client *http.Client, cfg *Config) (string, error) {
	resp, err := client.Get(cfg.API.BaseURL)
	if err != nil {
		log.Printf("request to %s failed: %v", cfg.API.BaseURL, err)
		return "", err
	}

	content, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("failed to read response body: %v", err)
		return "", err
	}

	re := regexp.MustCompile(`location\.href='([^']+)'`)
	matches := re.FindStringSubmatch(string(content))
	if len(matches) < 2 {
		log.Printf("redirect URL not found in response body")
		return "", ErrRedirectURLNotFound
	}

	redirectURL := matches[1]
	log.Printf("redirect URL extracted: %s", redirectURL)

	resp, err = client.Get(redirectURL)
	if err != nil {
		log.Printf("request to redirect URL failed: %v", err)
		return "", err
	}

	queryString := resp.Request.URL.RawQuery
	log.Printf("raw query string: %s", queryString)
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

	resp, err := client.Post(cfg.API.LoginURL, "application/x-www-form-urlencoded; charset=UTF-8", strings.NewReader(data.Encode()))
	if err != nil {
		log.Printf("login request failed: %v", err)
		return err
	}

	content, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("failed to read login response body: %v", err)
		return err
	}
	log.Printf("login response body: %s", content)
	var loginResp LoginResponse
	err = json.Unmarshal(content, &loginResp)
	if err != nil {
		return err
	}
	log.Printf("login response: %+v", loginResp.Result)
	if loginResp.Result != "success" {
		ticker := time.NewTicker(cfg.Time.RetryInterval)
		select {
		case <-ticker.C:
			ticker.Stop()
			queryString, err := FetchQueryString(client, cfg)
			if err != nil {
				log.Fatalf("fetch query string failed: %v", err)
			}
			err = AuthenticateWithCredentials(client, cfg, queryString)
			if err != nil {
				log.Fatalf("fetch query string failed: %v", err)
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
			log.Fatalf("fetch query string failed: %v", err)
		}
		err = AuthenticateWithCredentials(client, cfg, queryString)
		if err != nil {
			log.Fatalf("authenticate failed: %v", err)
		}
	}
	return err
}
