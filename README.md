# 在无 GMS 的国产 Android TV 设备上跑通 Apple TV —— 全链路调试复盘

> 设备：TCL C3A PRO 智能显示器（代号 G10，Realtek RTD2885P，Android 14，纯 armv7 32 位，zh-CN，dev-keys，出厂无 GMS）
> 结果：Apple TV App 完整可用，Dolby Vision 4K 直连播放，零代理流量
> 本文以generic化的家庭网络为例（主路由 `192.168.1.1`、软路由 `192.168.1.2`、本机 `192.168.1.50`），替换成你自己的地址即可。

## TL;DR

无 GMS 设备看不了 Apple TV 正片的真正根因**不是缺 Google 服务**，而是两层：

1. **Widevine CDM 没有出厂证书**（国产裁剪固件的通病）→ 需要"在线申请证书"（provisioning）→ 而申请要走 Google 的发放服务器 → 大陆网络直连失败（日志表现为 `provideProvisionResponse -10004`）；
2. **Apple 部分 API 域名对大陆解析链 geo-NXDOMAIN**（如 `play.edge.apple.com`、`amp-api.tv.apple.com` 在国内公共 DNS 均不存在）→ 登录页本地化包下载失败 → 界面乱码。

**解法：借一次代理出口完成证书发放（证书持久化在设备里），然后把网关切回主路由直连。** 之后许可证（KB 级）走 Apple 17/8 段直连，视频分段 Apple 会按你的国内出口 IP 自动派给国内 CDN，全程零代理。

## 诊断分层（为什么"预告片能放、正片不能"）

| 层 | 内容 | 症状 |
|---|---|---|
| 无 DRM 内容 | 预告片/花絮（clear 流） | 正常播放 ← 掩蔽性极强 |
| Widevine 证书 | CDM 出厂证书（`/data/misc/mediadrm/`） | `stat failed: ENOENT` → `PROVISION_REQUIRED` → 在线申请失败 |
| FairPlay | Apple 自家 DRM 存储（app 数据目录） | `requestOtp NOT_PROVISIONED:-45061` 每 7 秒重试 |
| 内容密钥 | license 服务器按次发放 | `GenerateKeyRequest` 发出后无响应 |
| 资产 API | TVML/本地化包（`mediaservices.cdn-apple.com` 等） | `en.json.gzip not in cache` → 登录页乱码 |

**DRM Info 显示 L1 ≠ 能播**：L1 只是引擎安全等级；服务端看的是设备证书链（OEM 向 Google/Widevine 采购时出厂烧录）。本机的"L1"引擎 + 空证书组合，正是"预告片能放、正片被拒"的精确解释。

**GMS 证伪**：整个修复过程没有装任何 Google 服务。Fire TV 的 Apple TV 也是无 GMS 版本——Apple 的播放栈不依赖 GMS，缺 GMS 只是国产盒子的伴随症状，不是根因。

## 修复链路（按时间序）

### 第 1 步：侧载官方 App（32 位注意）

APKMirror 的 `.apkm` 解包后 `adb install-multiple`：

```
adb install-multiple -r base.apk split_config.armeabi_v7a.apk split_config.zh.apk split_config.en.apk split_config.xhdpi.apk
```

- 本机为**纯 armeabi-v7a**，官方 16.0.0 仍有 v7a 分片，可行
- 电视 App 用 `LEANBACK_LAUNCHER` 类目，`monkey -c android.intent.category.LAUNCHER` 会报 "No activities found"
- 启动用显式组件：`am start -W -n com.apple.atve.androidtv.appletv/.MainActivity`

### 第 2 步：临时切到代理出口（一次性，为 provisioning）

把设备网关/DNS 指到带国际出口的软路由（本例 `192.168.1.2`），重启 App，日志确认证书发放成功：

```
WVCdm: GetProvisioningRequest cert_type = Widevine
WVCdm: HandleProvisioningResponse response_size = 3852   ← 成功（此前 -10004）
```

证书落盘 `/data/misc/mediadrm/`，**持久有效**（绑 TEE 硬件密钥，恢复出厂才丢，网络怎么切都不影响）。

### 第 3 步：网关切回主路由 + DNS 留在过滤网关

- 网关 → 主路由（直连出口），DNS → 软路由上的去广告 DNS
- **证书不重拿**（日志无 PROVISION_REQUIRED）
- license 每次播放都请求，但走 Apple 17/8 段（`17.253.87.x`，大陆直连可达，KB 级）
- 视频分段：Apple 按国内 IP 派 **国内 CDN**（本例拿到 115.231.32.x 金山云边缘 ×3）+ Akamai，4K Dolby Vision 直接拉满

### 证书 vs 密钥（高频问题）

| 东西 | 获取频率 | 存储 | 失效条件 |
|---|---|---|---|
| Widevine 设备证书 | 一次 | `/data/misc/mediadrm/` | 恢复出厂（数年有效期，到期自动续） |
| FairPlay 存储 | 一次 | App 数据目录 | 卸载/清数据 |
| 内容密钥（license） | 每次播放 | 内存会话 | 会话结束 |

**推论：代理出口只需要借一次。** 之后无论切回什么网络，证书都在；只有"连不上 license/CDN 服务器"才会影响播放。

## 流量归因（谁在吃代理带宽）

切换前在本例观察到的分流（透明代理网关、规则模式）：

| 流量 | 目标 | 走向 |
|---|---|---|
| API/许可证（几 KB） | 17.253.87.206（Apple 自家 HK 边缘） | 直连（Apple 17/8 段） |
| 静态图/资产 | 国内 CDN（金山云/浙江电信） | 直连（GeoIP CN） |
| 视频分段 | Fastly/Akamai 国际边缘 | **代理兜底规则 ← 大头在这里** |

两个反直觉结论：

1. **视频用哪个 CDN 是 Apple 服务端按你的出口 IP 指派的**，本地 DNS 特判（nameserver-policy 之类）改变不了它。出口在境外 → Fastly 国际边缘（吃代理）；出口在国内 → 国内 CDN（白嫖直连）。这也是"第 3 步切回主路由"省流量的原理。
2. 走代理出口时，一台 4K Dolby Vision 的设备一小时可以吃掉几十 GB 的代理流量——如果你的节点按倍率计费，务必先做归因再长期挂代理。

归因方法（不依赖任何特定代理软件）：多数现代代理内核提供**连接级 REST API**（每条连接带 up/down 累计字节 + 命中的规则/链路），播放期间采样几次做差值即可；设备侧则用 `/proc/net/tcp{,6}` 按 uid 过滤 + 小端十六进制解码（见 `scripts/`），或 `dumpsys netstats` 差值算总吞吐。

## 盲操工具箱（这类设备的特殊坑）

- **截屏可能被禁**：面板带 `FLAG_SECURE + FLAG_SUPPORTS_PROTECTED_BUFFERS`（Widevine L1 保护路径的一部分）→ `screencap` 输出 0 字节
- **替代眼睛**：`uiautomator dump`（原生设置界面可读控件树；Apple TV 界面是 TVML/Luna 引擎渲染，树里看不到，只能靠 logcat）
- **TV Settings 输入向导的 IME 坑**：`input text` 后软键盘自动弹出，此时 ENTER/DOWN/CENTER 会被键盘吃掉（表现为莫名输入 q/k 等杂字）。稳定节奏：`input text` → `KEYCODE_BACK`（收键盘）→ `KEYCODE_ENTER`（提交），每步用 uidump 验证
- **adb 通道**：改 Wi-Fi 配置时连接必闪断，记得提前准备好重连循环；`adb connect <ip>:5555` + 相同静态 IP 可秒回
- **日志分析**：优先 `adb logcat -d -v time` 一次性 dump（后台流任务易断、文件编码/锁问题多），设备缓冲区几分钟就会轮转，要趁早 dump

## 旁路由玩家注意（通用检查，与具体软件无关）

1. **透明代理网关可能截获发往自身 53 端口的流量**，让你的 DNS 过滤链（去广告/多上游竞速 DNS）被旁路。验证方法：查 DNS 服务的查询日志里有没有该客户端的记录；如果没有，客户端实际用的是代理内核的内置 DNS。
2. **多上游"竞速"型 DNS 会放大利害**：国内上游对 geo-NXDOMAIN 域名秒回 NXDOMAIN，国外上游经代理慢一拍 → 竞速模式下坏答案永远获胜。需要国外视角的域名要走分组规则而不是混合竞速池。
3. 静态 IP 配置只管 IPv4；**IPv6 仍走 RA** → 挂代理网关的设备 v6 流量会绕过代理（经典 v6-bypass 坑），要么在网关侧处理，要么按需过滤 AAAA。

## 本仓库脚本

| 脚本 | 用途 |
|---|---|
| `scripts/uidump-tree.ps1` | uidump XML → 可读控件树（文本/可点/焦点/边界），盲操的"眼睛" |
| `scripts/logcat-urls.ps1` | 从 logcat 提取指定进程访问过的所有 URL |
| `scripts/tcp-uid-sampler.ps1` | 采样 `/proc/net/tcp{,6}` 中指定 uid 的 ESTABLISHED 远端（hex 小端解码） |
| `scripts/conns-api-snapshot.sh` | 对提供连接级 JSON API 的代理网关做多次快照（凭据走环境变量） |
| `scripts/conns-parse.ps1` | 解析快照序列：按客户端/链路聚合下载字节增量，流量归因 |

脚本均参数化，无任何环境硬编码。

## 运行环境

- **前置**：`adb`（platform-tools）在 PATH 里；设备已开启网络调试（`adb connect <ip>:5555`）或 USB 调试
- **`.ps1` 脚本需要 PowerShell**：
  - **Windows**：系统自带 Windows PowerShell 5.1 即可（`powershell -File ...`），或 PowerShell 7（`pwsh -File ...`）
  - **macOS / Linux**：自带终端**不能**直接运行 PowerShell 脚本，先装一次 PowerShell 7，之后任何终端都能用：
    ```bash
    # macOS (Homebrew)
    brew install --cask powershell
    # Linux (Snap，任意发行版)
    sudo snap install powershell --classic
    # Linux (Debian/Ubuntu，先添加微软 apt 源后)
    sudo apt install powershell
    ```
    安装后：`pwsh -File scripts/uidump-tree.ps1 -Path ./uidump.xml`
  - 脚本只用基础 cmdlet，5.1 与 7.x 均兼容；跨平台注意路径分隔符传参时用 `/` 也行
- **`.sh` 脚本**（conns-api-snapshot.sh）是 POSIX shell，macOS/Linux 原生可跑，Windows 用 WSL/Git Bash

## 脚本实战：一次完整调试的用法串讲

以"设备能开 App、正片放不了"为例，按阶段串起来：

```powershell
# ① 定位应用进程与 uid（后续所有脚本都要用）
$serial = '192.168.1.50:5555'
$pkg    = 'com.apple.atve.androidtv.appletv'
adb -s $serial shell pidof $pkg                    # 进程 pid（日志过滤用）
adb -s $serial shell dumpsys package $pkg | Select-String 'appId'   # uid（连接采样用）

# ② 抓一轮干净日志，看 DRM/网络层在抱怨什么
adb -s $serial logcat -c
# …在设备上复现一次播放失败…
adb -s $serial logcat -d -v time > .\logcat.txt
Select-String .\logcat.txt -Pattern 'WVCdm','FAIRPLAY','rovision','GenerateKeyRequest'

# ③ 它到底连了谁？连接级采样（播放进行时跑 2-4 分钟）
pwsh -File .\scripts\tcp-uid-sampler.ps1 -Serial $serial -Uid 10134 -Minutes 2

# ④ 想看它访问过的域名（用于 DNS 视角比对）
pwsh -File .\scripts\logcat-urls.ps1 -Log .\logcat.txt -PidFilter <pid>

# ⑤ 需要盲操设置界面时，uidump 当眼睛（FLAG_SECURE 设备截图是 0 字节）
adb -s $serial shell uiautomator dump /sdcard/uidump.xml
adb -s $serial pull /sdcard/uidump.xml .
pwsh -File .\scripts\uidump-tree.ps1 -Path .\uidump.xml

# ⑥ 流量归因（代理网关侧，凭据走环境变量，不落盘不进历史）
$env:CONNS_API='http://192.168.1.2:9090/connections'; $env:CONNS_SECRET='<你的secret>'
sh ./scripts/conns-api-snapshot.sh > .\snapshots.txt      # 播放期间采样
pwsh -File .\scripts\conns-parse.ps1 -File .\snapshots.txt -SourceIP 192.168.1.50
```

诊断口诀：**日志看"卡在哪一层"，连接采样看"连了谁"，网关归因看"字节走了哪条道"**——三层证据对齐，基本没有定位不了的流媒体问题。

## AI 协作调试提示词

如果你打算让 AI 助手（ZCode / Claude Code / Cursor 等）代跑这套流程，直接把下面这段贴给它：

```text
我在一台无 GMS 的 Android TV 设备（已开 adb，地址 <IP:5555>）上调试 Apple TV App：
症状是预告片能播、DRM 正片失败/登录页乱码。请按以下流程帮我定位，每一步先展示命令与
输出再行动，不要跳步，不要修改设备上与本问题无关的任何设置。

已知坑位速查（前人实证，先验证再展开，别从头摸索）：
- 预告片能播+正片不能 = Widevine CDM 无出厂证书；logcat 关键词 provideProvisionResponse -10004
  （在线证书发放失败）。修复=借一次国际出口完成 provisioning，证书会持久化在
  /data/misc/mediadrm/，之后切回直连也不失效（恢复出厂才丢）。
- 登录页乱码 = App 本地化包(Assets/Localization/*.json.gzip)拉取失败，属资产 API 域名
  在大陆 DNS 视角 geo-NXDOMAIN 一类，检查 DNS 出口视角，而不是 App 本身。
- 面板 FLAG_SECURE 会让 screencap 输出 0 字节，直接改用 uiautomator dump 盲操。
- 电视设置输入向导：input text 后软键盘会吃掉 ENTER/DPAD，节奏是 text→BACK→ENTER。
- GMS 不是问题根源：全程不需要安装任何 Google 服务，别往装 GMS 的方向走。

请按此顺序执行：
1) dumpsys package 拿 uid/pid，logcat -d 抓启动+播放尝试日志，对照上面的坑位速查定位卡层；
2) 播放期间用 /proc/net/tcp{,6} 按 uid 采样远端 IP，解码后归类（Apple 17/8、国内 CDN、Fastly/Akamai）；
3) 有代理网关的连接级 API 就做差值归因，回答"视频流量走代理还是直连、大概多少 Mbps"；
4) 结论按"根因-证据-修复-回滚"四段输出，修复动作先列方案等我确认。
仓库 README 里有这些脚本的参数说明。
```

## 致谢

本仓库的根因分析、全链路调试、文档与脚本，均由 AI Agent **ZCode**（GLM）在与仓库所有者的结对会话中完成——包括在面板禁止截屏的设备上用 UI 树盲操完成静态网络切换、从 logcat 与连接采样中定位证书发放失败、以及流量归因实验的设计与执行。

## 最终网络配置（本例，地址已示例化）

| 项 | 值 |
|---|---|
| Wi-Fi | 静态 IP `192.168.1.50/24` |
| 网关 | `192.168.1.1`（主路由，直连出口） |
| DNS1 | `192.168.1.2`（软路由上的去广告 DNS） |
| DNS2 | 留空（避免国内兜底把 geo-NXDOMAIN 带回来） |
| 回滚 | 设置 → 网络 → IP 设置 → 改回 DHCP |

## 参考

- Apple TV (Android TV) 官方包：`com.apple.atve.androidtv.appletv`
- Widevine 机制：https://developers.google.com/widevine/drm/overview
- Apple TV App 兼容设备列表：https://support.apple.com/zh-cn/102472

## License

[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.zh-hans)（署名—相同方式共享 4.0 国际）——完整法务文本见 [LICENSE](LICENSE)。

你可以自由使用、修改和再分发本仓库内容（包括商用），条件是：**注明出处**，且演绎作品以**同一许可证**继续开放。
