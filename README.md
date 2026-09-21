# 青海大学校园网自动登录工具（AutoLogin）

一个校园网自动认证工具，适用于 **青海大学校园网** 环境。  
当网络断开或设备重连时，程序可自动完成认证登录，减少手动操作。

---

##  功能特性

- 自动检测网络连通状态
- 自动获取校园网登录所需 `queryString`
- 模拟浏览器请求，完成认证登录流程
- 支持后台常驻运行（服务模式）
- 配置文件清晰，便于修改与维护
- 提供 Go 二进制版与 Shell / Windows 批处理脚本版

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
├─ autologin.sh      # Linux 脚本版
├─ autologin.cmd     # Windows 批处理版
├─ config.script.example # 脚本版配置示例
├─ build.sh          # Go 版 Linux / macOS 构建脚本
├─ build.bat         # Go 版 Windows 构建脚本
└─ README.md
```

---

##  配置说明

### Go 二进制版配置

Go 版使用 **TOML** 格式：

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

### 脚本版配置

Linux `autologin.sh` 和 Windows `autologin.cmd` 使用简单 `KEY=VALUE` 格式，默认读取当前文件夹下的 `autologin.conf`。运行前必须先把示例配置复制为真实配置：

```bash
cp config.script.example autologin.conf
```

配置示例：

```text
# 学号或账号
USER_ID="你的学号"

# 登录密码
PASSWORD="你的密码"
```

脚本默认内置校园网地址：

- `BASE_URL=http://210.27.177.172`
- `LOGIN_URL=http://210.27.177.172/eportal/InterFace.do?method=login`
- `TEST_URL=https://www.baidu.com`
- `POLL_INTERVAL=3600`
- `RETRY_INTERVAL=60`

如果 `SERVICE` 留空或不填写，脚本会依次尝试：`校园联通`、`校园电信`、`校园移动`、`校园无线`。如果填写了 `SERVICE`，脚本只尝试该值。

`POLL_INTERVAL` 和 `RETRY_INTERVAL` 单位为秒。配置文件包含账号密码，请妥善保管，不要提交到公开仓库。

---

##  Go 版构建方式

### 直接构建

```bash
go build -o autologin ./cmd
```

### Go 版构建脚本

- Windows：`build.bat`
- Linux / macOS：`build.sh`

---

##  使用方法

### Linux 脚本版

运行环境需要 `bash`、`curl`、`sed`、`grep`。

```bash
chmod +x autologin.sh
./autologin.sh
./autologin.sh -once
./autologin.sh -c /path/to/autologin.conf
```

### Windows 批处理版

Windows 使用系统自带或手动安装的 `curl.exe`。

```bat
autologin.cmd
autologin.cmd -c C:\path\to\autologin.conf
autologin.cmd -once
```

默认情况下脚本会读取当前文件夹下的 `autologin.conf`；如果配置放在其他位置，再使用 `-c/--config` 指定路径。

### Go 二进制版

```bash
./autologin
```

### Go 版指定配置文件

```bash
./autologin -config config.toml
```

程序启动后会周期性检测网络状态，并在断网时自动尝试登录。  
请通过日志信息判断登录是否成功。

---

##  Linux 脚本版开机自启

脚本版推荐用 systemd 开机自启。先复制配置文件：

```bash
cp config.script.example autologin.conf
```

编辑 `autologin.conf` 后，运行安装脚本：

```bash
sudo ./install-service.sh
```

安装脚本会执行：

- 复制 `autologin.sh` 到 `/usr/local/bin/autologin.sh`
- 复制当前 `autologin.conf` 到 `/etc/autologin.conf`
- 写入 `/etc/systemd/system/autologin.service`
- 执行 `systemctl daemon-reload`
- 执行 `systemctl enable --now autologin.service`

也可以指定配置文件：

```bash
sudo ./install-service.sh -c /path/to/autologin.conf
```

查看服务和日志：

```bash
systemctl status autologin.service
journalctl -u autologin.service -f
```

##  Windows 脚本版开机自启

Windows 脚本版可以复制到当前用户的启动目录。先复制配置文件：

```bat
copy config.script.example autologin.conf
```

编辑 `autologin.conf` 后，双击运行：

```bat
install-startup.cmd
```

安装脚本会执行：

- 查找当前 Windows 用户启动目录
- 复制当前目录下的 `autologin.cmd`
- 复制当前目录下的 `autologin.conf`

运行前请把 `autologin.cmd`、`autologin.conf` 和 `install-startup.cmd` 放在同一目录。

### Go 版服务模式

### Go 版安装为系统服务

```bash
./autologin -install
```

### Go 版卸载服务

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
