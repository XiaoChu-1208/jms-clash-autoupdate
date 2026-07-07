# jms-clash-autoupdate

> 让 **Clash Verge (Rev)** 在 macOS 上**自动跟随机场订阅刷新节点**——IP 轮换、协议切换、节点上下架都能自动同步，还能在**开盖/唤醒**时立刻刷新。专为 [JustMySocks](https://justmysocks.net/) 这类订阅设计，也适用于结构相同的机场。

## 为什么需要它

**起因：JustMySocks 不提供 Clash 格式的订阅链接。** JMS 给的订阅是 **base64 裸节点列表**（SS / V2Ray 通用格式），不是 Clash 专用的 YAML 订阅。所以你没法在 Clash Verge 里把它当「远程订阅」直接用——直接导入只会得到一堆裸节点，**没有分组、规则、DNS**，必须先**手动转成一份本地（local）YAML**、配好分组和规则才能用。

**而本地 YAML 是死的，节点却是活的。** JMS 的节点 IP 会不定期轮换，有时还会把某个节点在 **SS ↔ VMess** 之间切换、下架或新增。本地 YAML 不会自己跟着变；手动改既烦又容易把协议改错（光换 server IP、协议没跟着换 → 死节点）。

本项目就是来填这个缝：把 `jms2clash` 一次性「订阅 → 本地 YAML」转换，和 `jms-verge-update` 持续「**结构化同步**」合到一起——按「节点稳定标识」对齐后整条节点按订阅重建（协议正确），只替换你分组里的节点成员，**你手配的分组 / 规则 / DNS 原样保留**，改完走 mihomo 的 unix socket **热重载**立即生效。

---

## 能做到什么

- **结构化同步**：换 IP、SS↔VMess 协议切换、节点上下架、新增，全部自动处理。
- **域名优先**：节点名里带稳定域名时（JustMySocks 就有）直接用域名当 server，IP 轮换由 DNS 解析兜住，配置根本不会过期。
- **更新自检 + 自动回滚**：每次真实更新前后各测一次链路；「更新前是通的、更新后不通」自动回滚本次改动，绝不把可用状态改坏。
- **不毁你的配置**：只换分组里的节点成员，分组/规则/DNS 不动；改前所有文件备份 `*.bak`。
- **节点友好名**：把 `JMS-xxx@c70s1...` 这种裸名换成你定的名字（如 `洛杉矶 1`）。
- **可只留某地区**：`only_locations: ["洛杉矶"]` 就只保留洛杉矶节点，保持出口 IP 纯净。
- **三重自动触发**：开机/登录 + 每 N 分钟定时 + **开盖/唤醒**（可选）。
- **空跑零成本**：节点没变化时不写盘、不重载，所以可以高频跑。
- **热重载**：改完通过 unix socket 让 mihomo 立即生效，不用手点。

---

## 环境要求

- macOS
- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev)（至少启动过一次）
- 系统自带 `/usr/bin/python3`（内置 PyYAML，**无需 pip 装任何东西**）
- 「开盖刷新」可选功能需要 [Homebrew](https://brew.sh/)（用来装 `sleepwatcher`）

---

## 快速开始

```sh
git clone https://github.com/XiaoChu-1208/jms-clash-autoupdate.git
cd jms-clash-autoupdate
sh install.sh
```

安装脚本会引导你：

1. 把 `jms-verge-update`、`jms2clash` 装进 `~/.local/bin`（并建简称 `jmsup`）；
2. 粘贴你的**订阅链接**，写进 `~/.config/jms-clash-autoupdate/config.yaml`（权限 600，不会进 git）；
3. 设定**定时间隔**（默认 30 分钟）并加载 launchd 任务；
4. 询问是否启用**开盖/唤醒刷新**（用 sleepwatcher）；
5. 立即试跑一次。

> 也可以一行把订阅给它：`sh install.sh "https://你的订阅链接"`

### 还没有 Clash 配置？先生成一份

如果你 Clash Verge 里还没有可用的 profile，用 `jms2clash` 从订阅生成一份，再在 Clash Verge 里 **导入本地文件 → 选中它**：

```sh
jms2clash               # 默认输出 ~/Desktop/jms.yaml
```

之后 `jmsup` 就会自动同步这个被选中的 profile。

---

## 日常使用

| 命令 | 作用 |
|---|---|
| `jmsup` | 手动同步一次（= `jms-verge-update`） |
| `jmsup --dry-run` | 只预览会改什么，不落盘、不重载 |
| `jmsup "https://另一个订阅"` | 临时用别的订阅 |
| `jms2clash` | 从订阅**全新生成**一份 Clash 配置（推倒重建用） |

日志在 `~/Library/Logs/jms-verge-update.log`，输出长这样：

```
  ✎ 节点      协议    旧 IP            新 IP            状态
  = c70s1    SS     192.0.2.10       192.0.2.10       未变
  ✎ c70s2    SS     192.0.2.11       198.51.100.22    换 IP
  ✗ c70s4    VMess  203.0.113.30     —                已下架
```

---

## 配置说明（`~/.config/jms-clash-autoupdate/config.yaml`）

完整示例见 [`config.example.yaml`](./config.example.yaml)。

```yaml
# 必填：订阅链接（注意：你的付费账号密钥，别公开、别提交进 git）
sub_url: "https://你的订阅链接"

# 选填：节点稳定标识正则。机场节点名/地址里那个跨更新不变的串。
# JustMySocks 一般是 c70s1 / c70s2 / c70s801 这种，所以默认就够用。
node_key_pattern: "c70s\\d+"

# 选填：友好名。键=标识(小写)，值=显示名。建议名字末尾保留「· 标识」。
names:
  c70s1: "洛杉矶 1 · c70s1"
  c70s2: "洛杉矶 2 · c70s2"

# 选填：只保留友好名里含这些关键词的节点（留空=全保留）。需配合 names。
only_locations:
  - "洛杉矶"

# 选填：节点名里带稳定域名时用域名当 server（默认 true，名字里没域名则无效果）。
prefer_domain: true

# 选填：更新前后连通性自检地址；更新前通、更新后不通会自动回滚本次改动。
probe_url: "https://www.google.com/generate_204"
```

订阅链接、环境变量、配置三者优先级：**命令行参数 > 环境变量 `JMS_SUB_URL` > 配置文件 `sub_url`**。

---

## 它是怎么工作的

```
机场订阅(base64 裸节点列表)
        │  fetch（强制直连，绕开代理，避免"代理死了拉不到订阅"的死循环）
        ▼
解析 ss:// / vmess:// → 按 node_key_pattern 对齐成 {标识: 节点}
        │  套用 names 友好名；only_locations 过滤
        ▼
读取 Clash Verge 当前选中的 profile（从 profiles.yaml 的 current 自动定位）
        │  对照旧节点 → 打印 换IP/协议变/下架/新增 报告
        ▼
若有变化：重建 proxies + 收敛分组成员 + 修 selected 选中项
        │  （分组结构/规则/DNS 原样保留；旧文件全部备份 *.bak）
        ▼
PUT /configs（mihomo unix socket）热重载 → 立即生效
```

三重触发：

| 时机 | 机制 |
|---|---|
| 开机 / 登录 | launchd `RunAtLoad` |
| 运行中每 N 分钟 | launchd `StartInterval` |
| 开盖 / 唤醒（可选） | sleepwatcher → `~/.wakeup` |

---

## 卸载

```sh
sh uninstall.sh
```

会移除脚本、launchd 任务、`~/.wakeup`；**不动**你的 Clash Verge 配置和订阅配置。彻底清配置：`rm -rf ~/.config/jms-clash-autoupdate`。

---

## 安全提醒

- 订阅链接 = 你的付费账号密钥。配置文件权限是 `600`，且 `.gitignore` 已排除 `config.yaml`——**别把它提交到任何公开仓库**。
- 脚本只读写 Clash Verge 自己的数据目录，改前一律备份 `*.bak`，可随时回滚。

## 适配其它机场

核心同步逻辑通用，关键是 `node_key_pattern` 能不能在你的节点名里找到一个**跨更新稳定的标识**。JustMySocks 用 `c70sN` 开箱即用；别的机场先 `jmsup --dry-run` 看「节点」列对不对得上，对不上就改这个正则。完全没有稳定标识的机场（每次名字全变）不适用本工具的增量同步，但 `jms2clash` 仍可用来生成配置。

## License

[MIT](./LICENSE)
