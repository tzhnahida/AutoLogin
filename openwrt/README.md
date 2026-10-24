# OpenWrt / busybox 路由器版（autologin.sh 的 ash 移植）

[`../autologin.sh`](../autologin.sh) 是 **bash** 脚本，而路由器固件（OpenWrt 等）通常只有 **busybox ash**，既没有 bash 也没有 systemd。本目录是把 bash 版逐行移植到 POSIX sh / busybox ash 的成果，并用 OpenWrt 原生的 **procd** 实现开机自启，登录逻辑（编码方式、连通性判定、重试节奏）与 bash / Go 版保持一致。

```
openwrt/
├─ autologin.sh            # busybox ash 兼容版脚本（本目录核心）
├─ autologin.conf.example  # 配置示例（UTF-8 无 BOM）
├─ autologin.initd         # procd 服务脚本 → /etc/init.d/autologin
├─ install.sh              # 路由器上的一键安装
└─ README.md               # 本文档：移植方法、部署步骤、踩坑记录
```

已在 **OpenWrt 19.07.5 (mips, kernel 4.14) + busybox ash + curl** 实测通过。

---

## 一、bash → busybox ash 移植清单

busybox ash 是 POSIX sh 方言，bash 版用到的以下特性全部不存在，逐项替换方式如下。

### 1. 全局

| bash 版 | ash 版 | 说明 |
|---|---|---|
| `#!/usr/bin/env bash` | `#!/bin/sh` | OpenWrt 只有 `/bin/sh`（→ ash） |
| `set -Eeuo pipefail` | `set -eu` | ash 无 `pipefail`/`E`；脚本内没有依赖二者的管道语义 |

### 2. 条件判断

| bash 版 | ash 版 |
|---|---|
| `[[ $# -gt 0 ]]` | `[ $# -gt 0 ]` |
| `[[ "$line" =~ ^[[:space:]]*# ]]` | 取出剥掉前导空白后的首字符，`case "$first" in '#'*)` |
| `[[ "$value:0:1" == '"' ]]`（首字符） | `${value%"${value#?}"}`（取首字符） |
| `${value: -1}`（尾字符） | `${value#"${value%?}"}`（取尾字符） |
| `${value:1:${#value}-2}`（去首尾） | `value=${value#?}; value=${value%?}` |

`${var:offset:length}` 子串扩展、`=~` 正则、`[[ ]]` 都是 bash/ksh 特性，ash 一律没有；POSIX 的 `${var#pattern}` / `${var%pattern}` 组合可以覆盖全部场景。

### 3. 变量替换与转义

| bash 版 | ash 版 | 说明 |
|---|---|---|
| `line="${line%$'\r'}"` | `CR=$(printf '\r')`，然后 `${line%"$CR"}` | `$'\xNN'` ANSI-C 引号是 bash 特性 |
| `line="${line#$'\xEF\xBB\xBF'}"`（剥 BOM） | `BOM=$(printf '\357\273\277')` | **注意八进制**：EF=357、BB=273、BF=277，别写成十进制习惯的 317 |
| `key="${key//[[:space:]]/}"`（全局替换） | `key=$(printf '%s' "$key" \| tr -d ' \t')` | `${var//pat/rep}` 是 bash 特性 |
| `printf -v c '%%%02X' ...` | `c=$(printf '%%%02X' "$code")` | `printf -v` 是 bash 特性，用命令替换代替 |

### 4. urlencode 逐字节循环（最核心的差异）

bash 版用 `for ((i = 0; i < ${#string}; i++))` + `${string:i:1}` 按下标取字节；ash 没有下标子串，改用"剥离法"逐字节前进：

```sh
urlencode() {
  rest=$1
  encoded=''
  while [ -n "$rest" ]; do
    c=${rest%"${rest#?}"}     # 取第一个字节：先挖掉 1 字节再从尾部还原
    rest=${rest#?}            # 剥掉第一个字节
    case "$c" in
      [a-zA-Z0-9.~_-]) encoded="$encoded$c" ;;
      *) code=$(( $(printf '%d' "'$c") & 0xFF ))
         encoded="$encoded$(printf '%%%02X' "$code")" ;;
    esac
  done
  printf '%s' "$encoded"
}
```

两个关键点：

- **`printf '%d' "'$c"`**：POSIX `printf` 支持把单字节字符转成整数值。busybox 实测 `A`→65、`\xE4`→228（**无符号字节值**，不需要 bash 版的负数防护，但保留 `& 0xFF` 无害且兼容）。UTF-8 中文在 C locale 下按字节循环，每个字节独立 `%XX`，与 Go `url.QueryEscape` 语义一致。
- **`& 0xFF`**：如果某实现返回带符号值，掩码兜底。

### 5. 数组

bash 版 `local services=("校园联通" "校园电信" ...)` + 下标遍历 → ash 无数组，改成空格分隔字符串 + `for service_name in 校园联通 校园电信 校园移动 校园无线`（服务名本身不含空格，分词安全）。

### 6. mktemp

| bash 版 | ash 版 | 说明 |
|---|---|---|
| `mktemp -d -t autologin.XXXXXX` | `mktemp -d /tmp/autologin.XXXXXX` | busybox 的 `-t` 语义完全不同（表示"相对 -d DIR 解释模板"），直接给绝对路径模板最稳 |

### 7. set -e 加固（顺带修复 bash 版的隐患）

bash 版多处 `var="$(curl ...)"` 没有兜底，断网时 curl 非零退出码会让 `set -e` **直接终止整个脚本**（原靠 systemd `Restart=always` / procd respawn 重启兜底）。ash 版显式处理，语义更清晰：

```sh
status=$(curl -sS ... -w '%{http_code}' "$TEST_URL") || status=000
...
query_string=$(curl ... -w '%{url_effective}' "$redirect_url") || query_string=''
...
response=$(curl ... --data-binary "$body" "$LOGIN_URL") || response=''
```

其余逻辑（先认证后验连、Portal 劫持自动探测、 queryString 双重编码、四个服务名轮询）原样保留，见根目录 README。

---

## 二、procd 开机自启（替代 systemd）

`install-service.sh` 依赖 systemd，OpenWrt 用 **procd**。`autologin.initd` 全文：

```sh
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /bin/sh /usr/bin/autologin.sh -c /etc/autologin.conf
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
```

要点：

- `respawn 3600 5 0`：进程异常退出后 5 秒拉起，**0 = 无限重试**（第三位 0 表示永不放弃），对应 systemd 版的 `Restart=always`。
- `stdout 1` / `stderr 1`：脚本日志进 syslog，用 `logread` 查看（对应 `journalctl -u`）。
- `START=99`：在网络栈就绪后启动。

常用命令（对应 systemd 的 systemctl）：

```sh
/etc/init.d/autologin start|stop|restart|enable|disable
logread | grep autologin | tail -20      # 查看日志
ubus call service list | grep -A4 autologin   # 运行状态
```

---

## 三、部署步骤

### 1. 前置条件

路由器需装 curl：`opkg install curl`（OpenWrt 19.07 自带 busybox wget，但脚本依赖 curl 的 `-w`/`--noproxy`/cookie 能力）。

### 2. 一键安装

在电脑上把本目录传到路由器，然后在路由器上执行：

```sh
# 电脑上（scp 必须加 -O，见踩坑第 4 条）
scp -O -r openwrt/ root@<路由器IP>:/tmp/

# 路由器上（老 dropbear 可能要求 HostKeyAlgorithms，见踩坑第 1 条）
ssh -o HostKeyAlgorithms=+ssh-rsa root@<路由器IP>
sh /tmp/openwrt/install.sh
```

`install.sh` 会：检查 conf 是否仍是占位符 → 安装脚本/配置/init 脚本 → enable + restart。

或者手动逐步执行（等价）：

```sh
cp autologin.sh /usr/bin/autologin.sh   && chmod 0755 /usr/bin/autologin.sh
cp autologin.conf /etc/autologin.conf   && chmod 0600 /etc/autologin.conf
cp autologin.initd /etc/init.d/autologin && chmod 0755 /etc/init.d/autologin
/etc/init.d/autologin enable && /etc/init.d/autologin start
```

### 3. 配置

`cp autologin.conf.example autologin.conf` 后填写 `USER_ID` / `PASSWORD`，**UTF-8（无 BOM）** 保存（ash 版会主动剥 BOM，但不要依赖它）。配置只在脚本启动时读取，改完需 `/etc/init.d/autologin restart`。

---

## 四、验证

上传后在路由器上做三件事（改脚本的必做）：

```sh
# 1. 语法检查
sh -n /usr/bin/autologin.sh

# 2. urlencode 单元测试（对照 Go url.QueryEscape；把函数体复制出来测，
#    不要直接 source 整个脚本——主循环会跟着跑）
sh -s <<'EOF'
urlencode() { ... }   # 从 autologin.sh 复制
urlencode "P@ss w0rd!"    # 期望 P%40ss%20w0rd%21
urlencode "校园联通"       # 期望 %E6%A0%A1%E5%9B%AD%E8%81%94%E9%80%9A
EOF

# 3. 跑一个周期看日志
/etc/init.d/autologin restart
logread -f | grep autologin
```

断网（未认证）时的正常日志形态：

```
AutoLogin started. Config: /etc/autologin.conf
Fetching authentication redirect URL...
No redirect from http://210.27.177.172. Trying portal auto-detection via http://www.baidu.com...
curl: (6) Couldn't resolve host 'www.baidu.com'
Portal unreachable: http://210.27.177.172
Authentication attempt failed.
Network check failed. HTTP status: 000
Network still unreachable. Retrying in 60 seconds...
```

即每 60 秒（`RETRY_INTERVAL`）重试，接入校园网后第一个周期内自动完成认证，之后休眠 `POLL_INTERVAL`。

---

## 五、踩坑记录（环境限制）

1. **老 dropbear 只提供 `ssh-rsa` 主机密钥**：新版 OpenSSH（8.8+）默认禁用 SHA-1，直连报
   `no matching host key type found. Their offer: ssh-rsa`。
   解决：`ssh -o HostKeyAlgorithms=+ssh-rsa`，或写入 `~/.ssh/config`：
   ```
   Host router <路由器IP>
       HostName <路由器IP>
       User root
       HostKeyAlgorithms +ssh-rsa
       PubkeyAcceptedAlgorithms +ssh-rsa,ssh-ed25519
   ```
2. **老 dropbear 不认 ed25519 公钥**（2020.79 才支持）：免密登录用 **RSA** 密钥
   （`ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_router`），公钥放
   `/etc/dropbear/authorized_keys`（同时放 `~/.ssh/authorized_keys` 双保险），权限 600。
3. **OpenWrt 没有 `/dev/stdin`**：`sh -s <<EOF` 的 stdin 管道方式可用，`. /dev/stdin` 不可用。
4. **dropbear 无 SFTP 子系统**：新版 OpenSSH 的 `scp` 默认走 SFTP，必须 `scp -O` 回退传统协议。
5. **存储空间**：mips 老设备 overlay 通常只有 10~16MB；本目录全部文件 <20KB，脚本方案远比塞一个 Go 二进制现实。
6. **中文服务名编码**：POST body 里 `service` 与 `queryString` 均双重 URL 编码，由 urlencode 按字节处理 UTF-8，无需 iconv；conf 文件保持 UTF-8 无 BOM 即可。

---

## 六、什么时候用哪一版

| 场景 | 用哪版 |
|---|---|
| Linux 服务器 / NAS（有 systemd） | 根目录 bash 版 + `install-service.sh` |
| OpenWrt / Padavan 等路由器固件（busybox ash） | 本目录 ash 版 + procd |
| Windows 常开设备 | 根目录 `autologin.cmd` + `install-startup.cmd` |
| 想要单文件二进制、服务安装更省事 | Go 版 `./autologin -install` |
