> ⚠️ 本项目免费公开源码，仅限个人/非商业用途，禁止倒卖、收费部署及任何未经授权的商业使用。


# Back4app VLESS + Cloudflare Tunnel

一个适合小白使用的 **Back4app + VLESS + WebSocket + Cloudflare Tunnel** 部署方案。

支持两种模式：

* **临时隧道**：无需域名、无需 Cloudflare Token，适合纯小白
* **固定隧道**：使用自己的 Cloudflare 域名，地址固定，更适合长期使用

---

## 功能

* VLESS + WebSocket
* Cloudflare Quick Tunnel 临时隧道
* Cloudflare Named Tunnel 固定隧道
* 自动生成 VLESS 节点
* Cloudflare 隧道断开后自动重连
* Back4app Docker 一键部署
* 无需 VPS
* 无需 SSH

---

## 项目文件

仓库只需要：

```text
.
├── Dockerfile
└── start.sh
```

---

# 方法一：小白版・临时隧道

这是最简单的部署方式。

特点：

```text
无需自己的域名
无需 Cloudflare Token
无需配置 DNS
只需要一个 UUID
```

Cloudflare 会自动生成：

```text
xxxx.trycloudflare.com
```

## 1. Fork 本项目

点击 GitHub：

```text
Fork
```

保存到自己的 GitHub 账号。

---

## 2. 创建 Back4app 应用

进入 Back4app：

```text
New App
→ Containers
→ Import GitHub Repository
```

选择刚刚 Fork 的仓库。

填写：

```text
Branch:
main

Root Directory:
./

Port:
8080
```

---

## 3. 添加 UUID

打开：

```text
Environment Variables
```

添加：

```text
Name:
UUID

Value:
你自己的UUID
```

例如：

```text
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

不会生成 UUID 的 Windows 用户可以打开 PowerShell：

```powershell
[guid]::NewGuid().ToString()
```

---

## 4. Deploy

点击：

```text
Deploy
```

等待部署完成。

然后打开：

```text
Logs
```

看到：

```text
Cloudflare Quick Tunnel 创建成功
```

下面会自动生成：

```text
vless://xxxxxxxxxxxxxxxx
```

复制完整的 `vless://` 链接导入客户端即可。

---

# 方法二：进阶版・固定 Cloudflare Tunnel

如果你有自己的 Cloudflare 域名，推荐使用固定 Tunnel。

优点：

```text
固定域名
容器重启后地址不变
更加适合长期使用
```

例如：

```text
vless.example.com
```

---

## 1. 创建 Cloudflare Tunnel

进入 Cloudflare：

```text
Networking
→ Tunnels
→ Create a tunnel
```

创建一个 Tunnel，例如：

```text
back4app-vless
```

Cloudflare 会给出类似：

```bash
cloudflared tunnel run --token eyJhIjoi........
```

只复制：

```text
eyJhIjoi........
```

也就是 `--token` 后面的内容。

---

## 2. 设置 Published Application

进入刚才创建的 Tunnel：

```text
Routes
→ Add route
→ Published application
```

Hostname：

```text
vless.example.com
```

Service：

```text
HTTP
```

URL：

```text
localhost:8080
```

最终必须是：

```text
http://localhost:8080
```

> 注意：不要设置成 `https://localhost:8080`，否则容易出现 502。

保存。

---

## 3. Back4app 添加环境变量

除了原来的：

```text
UUID
```

再添加：

```text
TUNNEL_TOKEN
```

值：

```text
你的 Cloudflare Tunnel Token
```

以及：

```text
CF_HOST
```

值：

```text
vless.example.com
```

最终：

```text
UUID=你的UUID

TUNNEL_TOKEN=你的Tunnel Token

CF_HOST=vless.example.com
```

重新 Deploy。

---

## 4. 获取固定节点

打开 Back4app：

```text
Logs
```

看到：

```text
Tunnel Mode : 固定隧道 / Named Tunnel
```

随后会自动输出：

```text
vless://xxxxxxxxxxxxxxxx
```

复制即可。

---

# 客户端参数

如果需要手动填写：

```text
协议：
VLESS

端口：
443

加密：
none

传输：
WebSocket

WS Path：
/vless

TLS：
开启
```

临时 Tunnel：

```text
地址：
xxxx.trycloudflare.com

Host：
xxxx.trycloudflare.com

SNI：
xxxx.trycloudflare.com
```

固定 Tunnel：

```text
地址：
vless.example.com

Host：
vless.example.com

SNI：
vless.example.com
```

---

# 可选环境变量

### WS_PATH

默认：

```text
/vless
```

想修改可以添加：

```text
WS_PATH=/abc
```

客户端 Path 也必须同步修改。

### CF_PROTOCOL

默认：

```text
auto
```

如果日志经常出现 QUIC、UDP、timeout 等错误，可以尝试：

```text
CF_PROTOCOL=http2
```

---

# 临时隧道和固定隧道怎么选？

| 模式           | 临时 Tunnel | 固定 Tunnel |
| ------------ | --------- | --------- |
| 自己的域名        | 不需要       | 需要        |
| Tunnel Token | 不需要       | 需要        |
| 部署难度         | ⭐         | ⭐⭐⭐       |
| 域名固定         | ❌         | ✅         |
| 重启后地址        | 可能变化      | 不变        |
| 推荐用途         | 测试/小白     | 长期使用      |

程序会自动判断：

```text
只有 UUID
↓
自动使用 Quick Tunnel
```

如果检测到：

```text
TUNNEL_TOKEN
```

则自动切换：

```text
Named Tunnel
```

所以不需要修改代码。

---

# 常见问题

## 1. 部署成功但节点 -1

首先查看：

```text
Back4app
→ Logs
```

以及：

```text
Metrics
```

检查 CPU、RAM 和 Cloudflare Tunnel 是否断线。

临时 `trycloudflare.com` Tunnel 本身更适合测试，如果长期使用建议切换固定 Tunnel。

---

## 2. 固定 Tunnel 出现 502

Cloudflare Tunnel 的 Service 必须设置：

```text
http://localhost:8080
```

不要设置：

```text
https://localhost:8080
```

---

## 3. 临时节点突然失效

Quick Tunnel 重启后：

```text
xxxx.trycloudflare.com
```

可能发生变化。

重新进入：

```text
Back4app → Logs
```

复制最新生成的 VLESS 节点即可。

---

## 4. 修改 GitHub 代码后没有更新

如果 Back4app：

```text
Autodeploy = No
```

需要手动重新：

```text
Deploy
```

建议开启：

```text
Autodeploy = Yes
```

以后 GitHub 更新后会自动重新部署。

---

# 推荐配置

### 纯小白

```text
UUID
```

就够了。

### 长期使用

```text
UUID
TUNNEL_TOKEN
CF_HOST
```

推荐固定 Cloudflare Tunnel。

---

## 架构

```text
客户端
   ↓
VLESS + WS + TLS
   ↓
Cloudflare
   ↓
Cloudflare Tunnel
   ↓
Back4app
   ↓
Nginx
   ↓
Xray
```

---

## 注意

## 📄 License / 使用许可

本项目**免费公开源码，仅限个人学习、研究、测试及其他非商业用途使用**。

### ✅ 允许

* 个人学习与研究
* 个人部署和使用
* 非商业测试
* 修改源码用于个人项目
* 在保留原作者及许可证信息的情况下进行非商业分享

### ❌ 禁止

未经作者明确书面授权，不得将本项目用于任何商业用途，包括但不限于：

* 出售本项目源码或修改版本
* 收费提供部署服务
* 将本项目打包后收费销售
* 用于付费订阅、付费节点或商业代理服务
* 以本项目为基础提供收费 SaaS / 托管服务
* 删除作者信息后重新发布、倒卖
* 其他直接或间接以盈利为目的的使用

### ⚠️ 商业授权

如需用于商业项目、收费服务或其他盈利场景，请先取得作者授权。

本项目建议采用：

**PolyForm Noncommercial License 1.0.0**

即：

> 免费用于个人及非商业用途，未经授权禁止商业使用。

---

## 免责声明

本项目仅用于个人学习、技术研究和网络环境测试。

使用者应自行遵守所在地法律法规以及 Back4app、Cloudflare 等第三方平台的服务条款。

因使用本项目产生的任何直接或间接后果，由使用者自行承担。

