# 青海大学校园网自动登录工具（AutoLogin）

一个使用 **Go** 编写的校园网自动认证工具，适用于 **青海大学校园网** 环境。  
当网络断开或设备重连时，程序可自动完成认证登录，减少手动操作。

---

##  功能特性

- 自动检测网络连通状态
- 自动获取校园网登录所需 `queryString`
- 模拟浏览器请求，完成认证登录流程
- 支持后台常驻运行（服务模式）
- 配置文件清晰，便于修改与维护

---

##  适用场景

- 校园网频繁掉线、重连后需要重复登录
- 无线 / 有线校园网认证
- 个人设备长期在线（宿舍主机、服务器、NAS 等）

> 本工具仅适用于 **青海大学当前校园网认证系统**，认证接口变更后可能需要调整。

---

##  项目结构

```
.
├─ cmd
│  └─ main.go        # 程序入口
├─ config.go         # 配置加载与解析
├─ login.go          # 登录逻辑实现
├─ autodaemon.go     # 服务/守护进程相关
├─ build.sh          # Linux / macOS 构建脚本
├─ build.bat         # Windows 构建脚本
└─ README.md
```

---

##  配置说明

配置文件使用 **TOML** 格式：

```toml
[auth]
user_id = "你的学号"
password = "你的密码"
service = "校园联通/电信/移动"  # 或 "校园无线"

[api]
base_url  = "http://210.27.177.172"
login_url = "http://210.27.177.172/eportal/InterFace.do?method=login"
test_url  = "https://www.baidu.com"

[time]
poll_interval  = "1h0m0s"  # 网络状态检测间隔
retry_interval = "1m0s"    # 登录失败重试间隔

[service]
name         = "AutoLogin"
description  = "Go-based CLI tool for campus network authentication."
display_name = "AutoLogin Service"
```

 请务必将学号和密码替换为你自己的信息，配置文件请妥善保管。

---

##  构建方式

### 直接构建

```bash
go build -o autologin ./cmd
```

### 使用脚本

- Windows：`build.bat`
- Linux / macOS：`build.sh`

---

##  使用方法

### 普通运行

```bash
./autologin
```

### 指定配置文件

```bash
./autologin -config config.toml
```

程序启动后会周期性检测网络状态，并在断网时自动尝试登录。  
请通过日志信息判断登录是否成功。

---

##  服务模式（后台运行）

### 安装为系统服务

```bash
./autologin -install
```

### 卸载服务

```bash
./autologin -uninstall
```

适合需要长期运行、不希望手动启动的场景。

---

##  使用说明

- 本程序通过 HTTP 请求模拟网页登录流程
- 若学校更换认证系统或接口地址，程序可能失效
- 仅建议在**个人设备**上使用
- 请遵守学校网络使用相关规定

---

##  License

MIT License
