package login

import (
	"autologin/internal/config"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	url2 "net/url"
	"regexp"
	"strings"
)

var (
	ErrRedirectURLNotFound = errors.New("redirect URL not found in response body")
	ErrHTTPStatusNotOK     = errors.New("http status not OK")
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

func CheckNetworkConnectivityWithURL(cfg *config.Config) error {
	resp, err := http.Get(cfg.API.TestURL)
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK {
		log.Println(resp.StatusCode)
		return ErrHTTPStatusNotOK
	}
	log.Println(resp.StatusCode)
	return nil
}

func FetchQueryString(client *http.Client, cfg *config.Config) (string, error) {
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

func AuthenticateWithCredentials(client *http.Client, cfg *config.Config, queryString string) error {
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
	json.Unmarshal(content, &loginResp)
	log.Printf("login response: %+v", loginResp.Result)
	return nil
}
