package main

import (
	"autologin/internal/config"
	"autologin/internal/login"
	"flag"
	"log"
	"net/http"
	"net/http/cookiejar"
)

func init() {
	flag.StringVar(&config.CfgPath, "config", "config/config.toml", "config file path")
	flag.Parse()
}

func main() {

	cfg, err := config.LoadConfig(config.CfgPath)
	if err != nil {
		log.Fatal("config read failed: %v", err)
	}

	jar, _ := cookiejar.New(nil)
	client := &http.Client{
		Jar: jar,
	}
	err = login.CheckNetworkConnectivityWithURL(&cfg)
	if err == login.ErrHTTPStatusNotOK {
		queryString, err := login.FetchQueryString(client, &cfg)
		err = login.AuthenticateWithCredentials(client, &cfg, queryString)
		log.Println(err)

	}

}
