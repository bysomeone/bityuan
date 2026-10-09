# Release flow / manual re-packaging

A release happens **only** when a release pull request is merged, and the release page is
published by **github-actions[bot]**: no personal access token (PAT) is involved anywhere, and
nothing is ever pushed straight to master.

## Cutting a release: merge the release pull request

1. **Merge a commit that carries a release tag** (`[[FEAT]]` / `[[FIX]]`, next section) into master.
2. **The bot opens a release pull request on its own**: within a minute, a pull request titled
   `chore(release): X.Y.Z` appears on the `release/pending` branch. If master moves again before it
   is merged, that same pull request is updated -- the branch is rebuilt, the title and the body are
   rewritten -- and a second one is never opened.
3. **Review it.** The diff *is* the release: it bumps `version/version.go` and `README.md` and adds
   one section to `CHANGELOG.md`. The body of the pull request is the semantic-release note; the
   release page, however, is built from that **CHANGELOG section**, so an operator-facing warning
   ("upgrade every node together", ...) belongs in the CHANGELOG diff, where it is reviewed like any
   other change.
   **That edit lives on the branch, and the branch is rebuilt from master -- and force-pushed -- on
   every later merge, so it is dropped if master moves before this pull request is merged.** Review
   and merge it promptly, or apply the warning again after the next rebuild.
4. **Merge it.** Two things to know:
   - the pull request is opened with `GITHUB_TOKEN`, and GitHub **does not run workflows for events a
     `GITHUB_TOKEN` caused**, so it carries no CI status checks at all -- a human has to look;
   - master has required status checks, so the merge goes through the **admin bypass**
     (`enforce_admins` is off).
5. **That push releases.** `publish-release` reads the version, takes the matching section of
   `CHANGELOG.md` as the release body, and creates the tag and the release in a single call, with the
   tag on the merge commit. Meanwhile `build-windows` / `build-macos` / `build-linux` build and
   smoke-test the five packages; only when all three pass does `upload-win-mac` upload them, write
   `SHA256SUMS`, add the System Requirements footer and assert that the asset list is complete.

The version is read from **`version/version.go`**, never from the commit subject, so the release pull
request may be merged with a merge commit, a squash or a rebase. A version whose tag
(`refs/tags/vX.Y.Z`) already exists is never released twice.

### Why the release pull request has no CI

GitHub has one hard rule here: **events caused by `GITHUB_TOKEN` do not start workflow runs.** The bot
creates the branch and the pull request with the built-in token, so no check ever runs on it. That is
not a missing configuration, and it is deliberately not worked around by reintroducing a PAT: it is
the cost of "a human looks before merging".

## 什么样的提交才会发版

发版由 semantic-release 判定，它用的是 **jshint 格式**（`.releaserc.yml` 里 `preset: jshint`），
**只认方括号标签、且必须大写**：

| 提交标题写成 | 结果 |
|---|---|
| `[[FEAT]] 描述` | 发 minor（6.8.x → 6.9.0），CHANGELOG 归入 Features |
| `[[FIX]] 描述` | 发 patch（6.8.21 → 6.8.22），CHANGELOG 归入 Bug Fixes |
| 正文含 `BREAKING CHANGE:` | 发 major |

**其他写法一律不发版**，也不会进 CHANGELOG：`feat: xxx`、`fix(scope): xxx`、`ci: xxx`、纯中文描述等。
所以只改 CI / 文档、又想让版本号往前走时，得单独写一个 `[[FIX]] ...` 的提交——
历史上就是这么做的（见 CHANGELOG 6.8.21 的 "trigger patch release for build and CI fixes"）。

## 谁可以操作

仓库 **write 权限**（能合并 PR 的人）：合并 release PR 就行；下面的手动补包入口在
仓库 → Actions → 选 workflow → **Run workflow**。上传用的是 workflow 自带的 `GITHUB_TOKEN`，
操作者不需要自己的 token，也不需要本地环境。

## 最常用：重新打包并上传（补齐所有平台的包）

**入口**：Actions → **release** → Run workflow，在弹出的输入框里填：

| 参数 | 填什么 | 举例 |
|---|---|---|
| `manual_upload` | **一个已经存在的 release tag**（要带 `v`） | `v6.9.0` |

点 **Run workflow** 就行。它会：

1. 按这个 tag 重新构建**全部 5 个包**：linux、windows `.zip`、windows Qt 安装包、darwin amd64 / arm64；
2. 每个平台起节点跑一次冒烟测试；
3. 校验 Qt 安装包（SFX 脚本完整、无 32 位残留、包内二进制与 zip 一致）；
4. 把这 5 个包**覆盖上传**（`--clobber`）到该 tag 的 release，并刷新 `SHA256SUMS`。

两点注意：

- **不能只补某一个包**——一次触发就是 5 个一起重传（它们必须是同一次构建的产物）；
- 输入框里**必须填 tag，不能填 commit 哈希**（上传目标是已存在的 release）。

## 出问题了怎么判断

| 现象 | 怎么办 |
|---|---|
| 某个平台的包没上传 | 用上面「重新打包」入口，填那个 tag 重跑一遍 |
| 整个 release 都没出来（tag 都没打） | 先看 release PR 有没有出现（`plan-release` 负责算版本、推分支、开 PR）；再看这次 push 的 `publish-release` / `build-*` 哪一步红了。偶发问题（网络 / runner）重跑那次 run；代码问题就修好后再推一个带 `[[FIX]]` 或 `[[FEAT]]` 的提交 |
| tag 存在、但 release 页面不存在 | 这是唯一必须人动手的状态：`is_release` 只看 tag，所以 CI 不会再为它建 release（每次后续 push 都会跳过发布）。要么手工建（`gh release create vX.Y.Z --target <该提交>`），要么删掉那个 tag 让下一次 push 重新发。删 release 页面（GitHub 保留 tag）、或手工打了 tag，都会落到这里 |
| `check` 说 tag 已存在，或 `publish-release` 说 release 已存在 | 这是**正常保护**：该版本已经发布过，不会再发第二次。要补包走上面的入口；版本号往前走要等下一个 `[[FIX]]` / `[[FEAT]]` |
| 手动补包跑完，release 里还是缺东西 | 看那次 run 里哪个 job 红了。**冒烟测试没通过时上传会被拦住**（故意的：宁可不上传，也不发没验证过的包） |
| 想核对下载到的文件 | release 里有 `SHA256SUMS`，`shasum -a 256 -c SHA256SUMS`（macOS / Linux） |

## What a pull request already checks

Everything in this flow that **writes** -- pushing the branch, opening the pull request, creating the
tag and the release -- can only happen while a release is being cut. Their decision logic and their
scripts, however, run on every pull request, so a release is not the first time they run at all:

| On a pull request | What it proves |
|---|---|
| `check` | the version/tag decision, the same code the release path uses |
| `plan-release` | semantic-release is really started, installs the plugins, loads the configuration and checks that the branch is one it may release from. A broken `.releaserc.yml`, an unresolvable preset or a node setup that drifted shows up here. It does **not** get as far as computing the version on a pull request: semantic-release returns early when it sees a pull request (`isCi && isPr`), so the version and the notes are computed on the push to master instead -- which every merge produces |
| `plan-release` shape check | `release_plan.sh` rewrites the three files for a synthetic version and `release_body.sh` reads the section back; a README title, a `version/version.go` line or a `CHANGELOG.md` header that stopped matching what the scripts expect fails the pull request |
| `lint` | actionlint on the workflow, shellcheck on the release scripts, and `test_release_pr.sh`: the branch push and the lease, replayed against a local bare repository with a stub `gh` (the one part of the flow that cannot run on a pull request at all) |
| `build-*` + smoke tests | the three platforms build and pass their smoke test (already the case before) |

## 机制速查（维护 release.yml 的人看）

| 文件 / job | 干什么 |
|---|---|
| `release.yml` · `check` | 从 `version/version.go` 读版本号；该版本的 tag 已存在 → `is_release=false`，反之 `is_release=true` |
| `release.yml` · `plan-release` | semantic-release **dry run** 只算下一个版本号和 note（dry run 不写文件、不打 tag）：push 时再调 `release_pr.sh` 维护 release PR，PR 时只跑形状检查 |
| `release.yml` · `publish-release` | 合并后从 `CHANGELOG.md` 取该版本的段落当正文，用 `GITHUB_TOKEN` 一次调用打好 tag、建出 release（作者因此是 github-actions[bot]） |
| `release.yml` · `lint` | actionlint 查 workflow、shellcheck 查 `.github/scripts/*.sh`（PR 与 push 都跑） |
| `.releaserc.yml` | 只剩 commit-analyzer / release-notes-generator（负责算版本号与生成 note）；改版本号、写 CHANGELOG、提交、打 tag、发 release 现在都在 workflow 与脚本里做 |
| `.github/scripts/release_plan.sh` | 把版本号写进 `version/version.go`、`README.md`、`CHANGELOG.md`（只改工作区，不碰 git） |
| `.github/scripts/release_pr.sh` | 重建 `release/pending`、提交（作者是 bot）、push（带 `--force-with-lease`）、开或更新 release PR |
| `.github/scripts/release_body.sh` | 从 `CHANGELOG.md` 取某版本的段落：发布时当 release 正文，PR 上被形状检查用来验算 |
| `.github/scripts/check_release_shape.sh` | 合成版本跑一遍 `release_plan.sh` → `release_body.sh` 的往返，验证三个文件与读取逻辑仍然对得上 |
| `.github/scripts/test_release_pr.sh` | 用本地裸仓库 + stub `gh` 跑 `release_pr.sh` 的 git 半部分：首次建分支、master 前进后强推、lease 拒绝竞态、同版本连跑不叠加 |

`CHANGELOG.md` 的段落由 dry run 的 note 写成，所以新条目的提交链接文字是短 sha
（`([5f45ca3](...))`），而 6.9.x 那几条是空的 `([](...))`；这是历史格式本来就有过的两种写法，
不是错误。

## 两个不能碰的地方

- **v6.8.18 release 里的 `bityuan-windows-amd64-qt.exe` 不能删、不能改名、不能覆盖**——
  它是 Qt 安装包的"壳"，打包时会去下载它（76MB）。要换壳得改 `release.yml` 里那一行。
- Qt 包里的钱包 GUI（`bityuan-qt.exe`）还是 2022 年的版本，CI 只替换里面的节点二进制和配置，
  **不验证 GUI**；装完能不能正常用，只能在 Windows 上人工点一遍确认。

## 仓库里遗留的旧入口（不要用）

`Actions → manually auto publish release`（`.github/workflows/automake.yml`）还是旧流程：用
**PAT 跑一次完整 semantic-release，直接往 master 推提交和 tag、并发布 release**，既绕过 release PR
这道人工闸门，release 页作者也会变成 PAT 的持有人。**不要再使用它**，请走上面的 release PR 流程。
