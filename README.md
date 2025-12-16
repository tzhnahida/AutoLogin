# 青海大学校园网自动登录工具

这是一个使用 Go 编写的**青海大学校园网自动登录程序**，用于在断网或重连后自动完成校园网认证登录。

## 项目用途

- 适用于青海大学校园网认证页面
- 自动获取登录所需的 `queryString`
- 模拟浏览器发送登录请求，完成认证

仅用于学习与个人使用，请勿滥用。

## 目录结构

```
.
├─cmd
│   └─main.go        # 程序入口
├─config
│   └─config.toml    # 校园网账号配置
├─internal
│   └─config.go     # 配置读取与默认配置
├─build.sh
├─build.bat
└─README.md
```

## 配置说明

首次运行如果不存在配置文件，会自动生成：`config/config.toml`

```toml
[auth]
user_id = "你的学号"
password = "你的校园网密码"
service = "校园网"

[api]
base_url = "http://210.27.177.172"
login_url = "http://210.27.177.172/eportal/InterFace.do?method=login"
```

请将学号和密码改为你自己的信息。

## 使用方法

### 构建

```bash
go build -o autologin ./cmd
```

### 运行

```bash
./autologin
```

或指定配置文件路径：

```bash
./autologin -config config/config.toml
```

运行后程序会自动完成校园网登录，请根据日志判断是否成功。

## 说明

- 本程序通过 HTTP 请求模拟网页登录流程
- 如果学校更换认证系统或接口地址，程序可能失效
- 建议仅在个人设备上使用

## License

MIT