<p align="center">
  <img src="assets/hero.svg" alt="claude-carousel — 并行使用多个 Claude Code 账号，某个账号触及用量上限时自动轮换到下一个" width="100%">
</p>

<p align="center">
  <a href="https://github.com/jungjoongi/claude-carousel/blob/main/LICENSE"><img src="https://img.shields.io/github/license/jungjoongi/claude-carousel?style=flat-square" alt="MIT license"></a>
  <a href="https://github.com/jungjoongi/claude-carousel/stargazers"><img src="https://img.shields.io/github/stars/jungjoongi/claude-carousel?style=flat-square" alt="stars"></a>
  <img src="https://img.shields.io/badge/shell-bash%203.2%2B-89e051?style=flat-square" alt="bash 3.2+">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square" alt="macOS | Linux">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ja.md">日本語</a> ·
  <b>简体中文</b>
</p>

# 🎠 claude-carousel

**一个 bash 脚本，零依赖。** 并行使用多个 Claude Code 账号——其中一个触及用量上限时，也能继续干活。

`cc go` 会启动 Claude Code 并留意 rate limit 提示，一旦发现就自动换用下一个账号重新启动。
没有要编译的东西，没有常驻守护进程，也没有需要手改的配置文件——只要 bash 和你已经装好的 `claude` CLI。

```console
$ cc ls
   PROFILE        ACCOUNT                        CLAUDE_CONFIG_DIR
   -------------- ------------------------------ ------------------
   default *      me@personal.dev                /Users/me/.claude
   work           me@company.com                 /Users/me/.claude-carousel/profiles/work
   oss            me+oss@personal.dev            /Users/me/.claude-carousel/profiles/oss

$ cc go
▶ running as default
⚠ rate limit detected on default — switching to work in 2s (Ctrl-C to stop)
▶ running as work
```

> 上面的 `cc` 是安装脚本会提议为你注册的简短别名。本 README 中的所有示例，换成
> `carousel …` 的写法效果完全相同。

## 一个 bash 脚本，零依赖

整个工具就是一个约 500 行的 bash 脚本，别无其他。

- **除了脚本本身没有任何东西要装。** 在 macOS 自带的 bash 3.2 上直接可用——不需要 Homebrew 的 bash，不需要 Python 运行时，没有要编译的 Rust 二进制，没有 Electron 应用，也没有常驻后台进程。放到 `PATH` 上的任意位置即可，卸载就是删掉一个文件。
- **一次就能通读审查。** 一个夹在你和你的 Claude 账号之间的工具，应该是可读的代码，而不是编译产物。它就是普通的 shell 脚本，几分钟就能从头看到尾；哪天 Claude Code 有变动，你自己就能改。
- **无需迁移。** 你现在登录的账号本身就是 `default` 配置。一切照旧，而且从不劫持或包装 `claude` 命令本身。
- **凭据仍留在操作系统安排的位置。** carousel 不会读取、写入、复制或保存你的 token。它只是把 `CLAUDE_CONFIG_DIR` 指向各配置独立的目录，其余交给 Claude Code 自己的 `/login` 处理——macOS 用钥匙串，Linux 用本地文件。
- **不重复占用磁盘。** `plugins/`、`skills/`、`projects/` 都软链接回原本的 `~/.claude`，所以多一个配置的成本是几十 KB，而不是 800 MB。
- **rate limit 轮换**内置在同一个脚本里，而不是另一个需要记住的模式。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/jungjoongi/claude-carousel/main/install.sh | bash
```

或手动安装：

```bash
git clone https://github.com/jungjoongi/claude-carousel.git
install -m 755 claude-carousel/bin/carousel ~/.local/bin/carousel   # PATH 上的任意位置
```

依赖要求：bash 3.2 及以上、`python3`（macOS 自带，仅用于从 Claude Code 的 JSON 中读取账号邮箱）、
`claude` CLI，以及若要使用 `cc go` 则需要 `script`（macOS 和几乎所有 Linux 发行版都自带）。

## 快速开始

```bash
cc ls                  # 你当前的登录已经显示为 "default"
cc add work            # 创建第二个配置
cc login work          # 登录（就是平常的 Claude Code 登录流程）

cc work                # 以 "work" 身份运行 Claude Code
cc                     # 以默认配置运行
cc use work            # 把 "work" 设为默认

cc order default work  # "go" 的轮换顺序
cc go                  # 运行；触及上限就自动换下一个账号
```

开两个终端就能同时使用两个账号。每个配置都有各自的凭据槽位，所以会话之间不会互相抢 token。

## 命令

| 命令 | 说明 |
|---|---|
| `cc ls` | 列出各配置及其登录的账号 |
| `cc add <名称>` | 创建配置 |
| `cc login <名称>` | 为该配置执行 Claude Code 登录流程 |
| `cc <名称> [参数…]` | 以该配置运行 Claude Code（额外参数原样传递） |
| `cc` | 以默认配置运行 |
| `cc use <名称>` | 设置默认配置 |
| `cc whoami` | 查看当前 shell 处于哪个配置 |
| `cc order [名称…]` | 查看或设置轮换顺序 |
| `cc go [参数…]` | 带 rate limit 自动轮换地运行 |
| `cc sync [名称]` | 重新链接来自 `~/.claude` 的共享插件与设置 |
| `cc rm <名称>` | 删除配置（只解除软链接，原文件不动） |
| `cc alias [名称]` | 注册或修改简短的 shell 别名（`--remove` 撤销） |
| `cc doctor` | 环境与排查信息 |

## 更短的别名

`carousel` 敲起来偏长，所以安装脚本会提议注册一个简短别名——默认是 `cc`，按回车即可确认。
你也可以随时自己修改：

```bash
carousel alias cc        # 现在 "cc" 就会运行 carousel
carousel alias           # 查看已注册的别名
carousel alias --remove  # 撤销
```

**为什么用别名，而不直接把可执行文件命名为 `cc`？** 因为 `cc` 同时也是 C 编译器，`PATH` 上
出现名为 `cc` 的可执行文件会被 `make` 之类的工具取用，从而弄坏构建。而 shell 别名只在*你自己*
输入时生效，所以在提示符下 `cc go` 可用，`make` 仍然使用真正的 `/usr/bin/cc`。既拿到短命令，
又没有连带损害。

它会在你的 shell rc 文件（`~/.zshrc`、`~/.bashrc` 或 fish 的 `config.fish`）中写入带标记的代码块，
所以之后修改或删除都很干净：

```bash
# >>> claude-carousel alias >>>
alias cc='carousel'
# <<< claude-carousel alias <<<
```

如果你选的名字已被占用，它会告知你，而不是默默覆盖：

- **你已有的别名**（例如 `alias cc='claude …'`）——会把那一行原样显示出来，并询问是否注释掉。回答否则不改动任何东西。
- **同名的真实命令**——会告诉你那是哪个可执行文件，并再次说明别名只在你自己输入时才会遮蔽它。

## 工作原理

Claude Code 通过 `CLAUDE_CONFIG_DIR` 决定把自己的状态放在哪里。把它指向另一个目录，就身份层面
而言你便得到了一个完全独立的安装：各自的 `.claude.json`（`oauthAccount` 就在其中）、各自的会话
历史、各自的凭据槽位。在 macOS 上，Claude Code 会依据该路径生成钥匙串的服务名，因此每个配置的
OAuth token 会自动落在各自的条目里。

carousel 本质上就是围绕这一个环境变量做的少量管理工作：

```
~/.claude                              ← "default" 配置，不作改动
~/.claude-carousel/
├── default                            ← 默认配置的名称
├── order                              ← `go` 的轮换顺序
├── alias                              ← 已注册的 shell 别名
└── profiles/
    └── work/
        ├── .claude.json               ← 该配置的身份 + 会话状态
        ├── plugins  -> ~/.claude/plugins    (软链接)
        ├── skills   -> ~/.claude/skills     (软链接)
        ├── projects -> ~/.claude/projects   (软链接)
        └── settings.json              ← 每次运行时从 ~/.claude 复制
```

`settings.json` 采用复制而非软链接，因为 Claude Code 会以 atomic write 重写该文件，那样会把软链接
替换成普通文件。

## 关于 rate limit 轮换，说实话

`cc go` 在 pty 中（借助 `script`）运行 Claude Code，把输出照常显示在终端上，同时对捕获的
内容 grep `usage limit`、`rate limit`、`limit will reset` 之类的字样。一旦命中，就切到
`cc order` 中的下一个配置重新启动。

有两点需要明确说明：

1. **这是启发式判断。** Claude Code 的确切措辞可能随版本变化。如果该轮换时没有轮换，请修改脚本
   顶部的 `RATE_LIMIT_PATTERN`——这是一个刻意放在显眼位置的普通 `grep -E` 模式。特别欢迎提交
   更新它的 PR。
2. **需要真实的终端。** 在 CI 等拿不到 pty 的环境里，它不会报错，而是给出警告并在没有轮换的情况下
   照常运行。

## bypass 模式

每次运行都会附加 `--dangerously-skip-permissions`，这样 Claude Code 不会为每个操作停下来询问——
毕竟同时用多个账号的目的通常就在于此。如果你更希望保留确认提示：

```bash
export CAROUSEL_BYPASS=0
```

你自己传入的 `--permission-mode …` 或 skip 参数始终优先于该设置。

## 配置项

| 环境变量 | 默认值 | 用途 |
|---|---|---|
| `CAROUSEL_BYPASS` | `1` | 设为 `0` 时保留 Claude Code 的正常权限提示 |
| `CAROUSEL_HOME` | `~/.claude-carousel` | 配置与设置的存放位置 |
| `CAROUSEL_CLAUDE_BIN` | `claude` | `claude` 可执行文件的路径 |

## 许可证

MIT
