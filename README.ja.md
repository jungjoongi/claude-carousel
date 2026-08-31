<p align="center">
  <img src="assets/hero.svg" alt="claude-carousel — 複数の Claude Code アカウントを並行して使い、利用上限に達したら自動で次のアカウントへ切り替えます" width="100%">
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
  <b>日本語</b> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

# 🎠 claude-carousel

**bash スクリプト 1 本、依存ゼロ。** 複数の Claude Code アカウントを並行して使い、ひとつが
利用上限に達しても作業を続けられます。

`cc go` は Claude Code を起動したあと rate limit のメッセージを監視し、検出したら次の
アカウントで自動的に再起動します。ビルドするものも、常駐デーモンも、手で編集する設定ファイルも
ありません — bash とすでに入っている `claude` CLI だけで動きます。

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

> 上の `cc` は、インストーラーが登録を提案する短い alias です。この README のすべての例は
> `carousel …` と書いても同じように動きます。

## bash スクリプト 1 本、依存ゼロ

ツール全体が約 500 行の bash スクリプト 1 本です。それ以外には何もありません。

- **スクリプト以外に入れるものがありません。** macOS 標準の bash 3.2 でそのまま動きます — Homebrew の bash も、Python ランタイムも、ビルドが必要な Rust バイナリも、Electron アプリも、常駐デーモンもありません。`PATH` のどこかに置けば完了、アンインストールはファイル 1 つを削除するだけです。
- **一度に読み切れます。** 自分と Claude アカウントの間に入るツールなら、コンパイル済みのバイナリではなく読めるコードであるべきです。数分で上から下まで目を通せる普通のシェルスクリプトで、Claude Code 側に変更があった日には自分で直せます。
- **移行作業なし。** いま使っているログインがそのまま `default` プロファイルになります。従来どおり動き、`claude` コマンド自体を横取りしたりラップしたりはしません。
- **認証情報は OS が置く場所のまま。** carousel はトークンを読み書き・コピー・保存しません。`CLAUDE_CONFIG_DIR` をプロファイルごとのディレクトリに向けるだけで、あとは Claude Code の `/login` が処理します — macOS はキーチェーン、Linux はローカルファイル。
- **ディスクの重複なし。** `plugins/`、`skills/`、`projects/` は元の `~/.claude` へシンボリックリンクされるので、プロファイルを 1 つ増やすコストは 800 MB ではなく数十 KB です。
- **rate limit ローテーション**が別モードではなく同じスクリプトに入っています。

## インストール

```bash
curl -fsSL https://raw.githubusercontent.com/jungjoongi/claude-carousel/main/install.sh | bash
```

手動で入れる場合:

```bash
git clone https://github.com/jungjoongi/claude-carousel.git
install -m 755 claude-carousel/bin/carousel ~/.local/bin/carousel   # PATH 上のどこでも
```

必要なもの: bash 3.2 以上、`python3`（macOS に標準搭載。Claude Code の JSON からアカウントの
メールアドレスを読むためだけに使います）、`claude` CLI、そして `cc go` を使うなら
`script`（macOS とほぼすべての Linux ディストリビューションに標準搭載）。

## クイックスタート

```bash
cc ls                  # いまのログインが既に "default" として表示されます
cc add work            # 2 つ目のプロファイルを作成
cc login work          # ログイン（通常の Claude Code のログイン手順）

cc work                # "work" として Claude Code を起動
cc                     # デフォルトのプロファイルで起動
cc use work            # "work" をデフォルトに設定

cc order default work  # "go" が回る順番
cc go                  # 上限に達したら次のアカウントへ自動で切り替え
```

ターミナルを 2 つ開けば、2 つのアカウントを同時に使えます。プロファイルごとに認証スロットが
分かれているため、セッション同士がトークンを取り合うことはありません。

## コマンド

| コマンド | 説明 |
|---|---|
| `cc ls` | プロファイル一覧と、それぞれがログインしているアカウントを表示 |
| `cc add <名前>` | プロファイルを作成 |
| `cc login <名前>` | そのプロファイルで Claude Code のログイン手順を実行 |
| `cc <名前> [引数…]` | そのプロファイルで Claude Code を起動（追加引数はそのまま渡す） |
| `cc` | デフォルトのプロファイルで起動 |
| `cc use <名前>` | デフォルトのプロファイルを設定 |
| `cc whoami` | いまのシェルがどのプロファイルかを表示 |
| `cc order [名前…]` | ローテーション順の確認・設定 |
| `cc go [引数…]` | rate limit の自動ローテーション付きで起動 |
| `cc sync [名前]` | `~/.claude` の共有プラグイン・設定を再リンク |
| `cc rm <名前>` | プロファイルを削除（シンボリックリンクのみ解除、元は無傷） |
| `cc alias [名前]` | 短いシェル alias を登録・変更（`--remove` で解除） |
| `cc doctor` | 環境とトラブルシューティング情報 |

## 短い alias

`carousel` はタイプ数が多いので、インストーラーが短い alias を提案します — 既定は `cc` で、
Enter を押すだけで登録されます。あとから自分で変えることもできます。

```bash
carousel alias cc        # これで "cc" が carousel を実行
carousel alias           # 登録済みの alias を表示
carousel alias --remove  # 解除
```

**バイナリ名を単に `cc` にせず alias を使う理由は？** `cc` は C コンパイラでもあるため、
`PATH` に `cc` という名前のバイナリを置くと `make` などがそれを拾い、ビルドが壊れます。
シェルの alias は *自分で* 打ったときだけ効くので、プロンプトでは `cc go` が使えて、`make` は
本物の `/usr/bin/cc` を使い続けます。短いコマンドだけを手に入れ、副作用はありません。

シェルの rc ファイル（`~/.zshrc`、`~/.bashrc`、fish の `config.fish`）に目印付きのブロックとして
書き込むので、あとで変更・削除してもきれいに戻せます。

```bash
# >>> claude-carousel alias >>>
alias cc='carousel'
# <<< claude-carousel alias <<<
```

選んだ名前が既に使われている場合、黙って上書きせずに知らせます。

- **既にある自分の alias**（例: `alias cc='claude …'`）— その行をそのまま見せ、コメントアウトしてよいか尋ねます。断れば何も変更しません。
- **同名の実在するコマンド** — どのバイナリかを知らせ、alias が優先されるのは自分で打ったときだけだと改めて伝えます。

## 仕組み

Claude Code は `CLAUDE_CONFIG_DIR` を見て自分の状態をどこに置くかを決めます。これを別の
ディレクトリに向けると、識別情報の観点では完全に独立したインストールになります — 独自の
`.claude.json`（`oauthAccount` がここに入っています）、独自のセッション履歴、独自の認証スロット。
macOS では Claude Code がそのパスからキーチェーンのサービス名を作るため、プロファイルごとの
OAuth トークンが自動的に別々の項目へ保存されます。

carousel は本質的に、その環境変数 1 つを取り巻く少しの管理作業です。

```
~/.claude                              ← "default" プロファイル、手を加えない
~/.claude-carousel/
├── default                            ← デフォルトのプロファイル名
├── order                              ← `go` のローテーション順
├── alias                              ← 登録したシェル alias 名
└── profiles/
    └── work/
        ├── .claude.json               ← このプロファイルの識別情報 + セッション状態
        ├── plugins  -> ~/.claude/plugins    (シンボリックリンク)
        ├── skills   -> ~/.claude/skills     (シンボリックリンク)
        ├── projects -> ~/.claude/projects   (シンボリックリンク)
        └── settings.json              ← 起動ごとに ~/.claude からコピー
```

`settings.json` はシンボリックリンクではなくコピーです。Claude Code がこのファイルを atomic
write で書き直すため、シンボリックリンクが通常ファイルに置き換わってしまうからです。

## rate limit ローテーションについて、正直に

`cc go` は Claude Code を pty の中で（`script` を使って）実行し、出力はそのまま
ターミナルに流しつつ、記録した内容から `usage limit`、`rate limit`、`limit will reset` などの
文言を grep します。見つかれば `cc order` の次のプロファイルへ移って再起動します。

はっきり書いておくべき点が 2 つあります。

1. **ヒューリスティックです。** Claude Code の正確な文言はリリースごとに変わりえます。
   ローテーションが発動すべきなのにしない場合は、スクリプト冒頭の `RATE_LIMIT_PATTERN` を
   編集してください — あえて目立つ 1 か所に置いた、ごく普通の `grep -E` パターンです。
   これを更新する PR は特に歓迎します。
2. **実際のターミナルが必要です。** CI のように pty が与えられない環境では、失敗せずに警告を
   出し、ローテーションなしでそのまま実行します。

## bypass モード

すべての起動に `--dangerously-skip-permissions` が付きます。操作ごとの確認で止まらずに進み、
そもそも複数アカウントを回す目的はたいていそこにあるからです。確認プロンプトを残したい場合:

```bash
export CAROUSEL_BYPASS=0
```

自分で `--permission-mode …` や skip フラグを渡した場合は、この設定より常に優先されます。

## 設定

| 環境変数 | デフォルト | 用途 |
|---|---|---|
| `CAROUSEL_BYPASS` | `1` | `0` で Claude Code の通常の権限プロンプトを維持 |
| `CAROUSEL_HOME` | `~/.claude-carousel` | プロファイルと設定の保存場所 |
| `CAROUSEL_CLAUDE_BIN` | `claude` | `claude` バイナリのパス |

## ライセンス

MIT
