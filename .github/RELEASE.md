# 手动发布 / 补包操作

正常情况下不用看这份文档：合并到 master 后 CI 会自动发版并上传全部 5 个包。
这里只讲**自动流程出问题时，怎么手动把包装上去**。

## 谁可以操作

仓库 **write 权限**（能合并 PR 的人）：仓库 → Actions → 选 workflow → **Run workflow**。
上传用的是仓库里的 `GH_TOKEN` secret，操作者不需要自己的 token，也不需要本地环境。

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

## Package file names

Every package carries the release version — for v6.9.1:

| Package | File name |
|---|---|
| Linux | `bityuan-linux-amd64-6.9.1.tar.gz` |
| Windows zip | `bityuan-windows-amd64-6.9.1.zip` |
| Windows Qt installer | `bityuan-windows-amd64-qt-6.9.1.exe` |
| macOS | `bityuan-darwin-amd64-6.9.1.tar.gz`, `bityuan-darwin-arm64-6.9.1.tar.gz` |

The version comes from `version/version.go` (the `Check release commit` job outputs
it as `version`), never from `git describe` — on the automatic path the tag does
not exist yet when the builds start, so `git describe` would name the packages
after the previous release.

Every archive carries `CHANGELOG.md`, the Windows zip included, so a package that
has been downloaded and unpacked still says which version it is.

## Upgrade Notes (who writes one, and where)

The "what an operator has to do" block on a release page comes from the **pull requests
merged in that release** — specifically the text under a `Release note` heading in each
pull request description. **One note per pull request, not per commit**: a PR carrying
three `fix:` commits has one note, and the page shows one bullet.

A heading is the convention (rather than the fenced ```release-note block Kubernetes
uses) because a PR body is often written without the repository's template, and a heading
needs no convention to be remembered. `.github/pull_request_template.md` carries it:

```
## Release note

Nodes older than 6.9.0 are dropped at the p2p layer and blacklisted for 24 hours,
so upgrade every node together.
```

Everything under the heading, up to the next heading, is the note. Naming is loose:
`Release notes` / `release-note` work too, case-insensitively.

- the consequence for an operator, not a restatement of the diff
- English: it is published on the release page
- one or two sentences (~300 characters): the page renders it as a single bullet, so a
  long note reads badly there. Over 300 characters warns; over 600 the check fails and
  the detail belongs in the pull request body
- `NONE` under the heading when the release genuinely has nothing an operator has to act
  on — an explicit "I checked"
- the template's comment is stripped, so an untouched template counts as "no note" and
  the check fails

**Whether a PR needs one is not a documentation convention**:
`.github/scripts/release_commit.sh` reads the preset out of `.releaserc.yml` and applies
that preset's default releaseRules — under angular that is `feat:` / `fix:` / `perf:` /
`revert:`, plus any commit carrying `BREAKING CHANGE:`; under jshint, `[[FEAT]]` /
`[[FIX]]`. A PR with no such commit is not asked for a note — and if one is written
anyway it is still collected, because the collection step is deliberately inclusive: a
`chore(deps)` bump that carries a real fix is exactly the case where the author knows
something the classifier cannot. An unknown preset — or a
`releaseRules` block, which overrides the preset defaults — makes the script exit 2 and
fail the check rather than quietly applying stale rules.

**Enforced in CI** (`.github/workflows/release-note.yml`, pull requests only): a PR whose
commits cut a release must declare a note, and the failure message prints the block
format. **A change to an operator-visible file only warns** — a path is a hint, not a
verdict (`bityuan.toml` can be touched for a comment; a real impact can land in a file not
on the list), so that step just points the reviewer at the note. **Whether a note is true
is review's call**: CI can ask whether one exists, not whether it matches the diff.

## Release page footer

Added as soon as the release exists, before any asset is uploaded: `release-linux` calls
`.github/scripts/add_release_footer.sh` right after semantic-release, and it appends
**Upgrade Notes** (previous section) and **System Requirements** to the release body. It
lives there rather than in the upload job because an upload can fail, and a failed upload
should not leave the page without "what an operator has to do".

The script walks the commits between the previous tag and this one, maps each to its pull
request, and renders one bullet per PR from the text under that PR's `Release note`
heading. A commit that
never went through a pull request (pushed straight to master) falls back to a
`Release-Note:` line in its own body.

- The macOS line is the `minos` of the darwin binaries — currently 14.0, from building on
  the `macos-14` runner (`otool -l bityuan | grep -A4 LC_BUILD_VERSION`). Moving to a newer
  runner moves the floor; keep the line in step.
- A release whose body already carries "System Requirements" is skipped, so re-running
  cannot double-append. To repair the block on an older release, run the script locally
  (needs `gh` logged in):
  `GH_TOKEN=$(gh auth token) bash .github/scripts/add_release_footer.sh v6.9.1`

## 另一个入口：手动跑一次发版（automake）

**入口**：Actions → **manually auto publish release** → Run workflow（输入随便填）。

用途：push 没能触发发布流程时，手动跑一遍 semantic-release。它会打 tag、发 release、上传 linux 包。

⚠️ **它不能"强制"发版**：如果自上一个 tag 以来没有 `feat:` / `fix:` 这类发版类型的提交，
它会判定"无需发布"直接退出，什么都不做。想发版得先有一个发版类型的提交。

## 什么样的提交才会发版

semantic-release decides, using the **Angular preset** — the conventional-commits
standard (`preset: angular` in `.releaserc.yml`), the same one chain33 and plugin
use. Subjects take the form `type(scope): description`:

| Commit subject | Result |
|---|---|
| `feat: description` | minor release (6.9.x → 6.10.0), CHANGELOG under Features |
| `fix: description` | patch release (6.9.1 → 6.9.2), CHANGELOG under Bug Fixes |
| `perf: description` | patch release |
| `revert: description` | patch release |
| body contains `BREAKING CHANGE:` | major release (any type, not just feat/fix) |

(The table is `@semantic-release/commit-analyzer`'s default releaseRules; on the CI
side `.github/scripts/release_commit.sh` reads `.releaserc.yml` and applies the same set.)

`chore:` / `docs:` / `ci:` / `test:` / `refactor:` trigger no release and never
reach the CHANGELOG. Note what follows from that: **the CHANGELOG is the release
notes, so anything users or operators need to know has to be a `feat:` or a
`fix:`** — including a dependency bump that carries a real fix. One PR may hold
several `fix:` commits; each becomes its own bullet. The pull request itself carries one
release note (see "Upgrade Notes" below); CI checks for it.

Before v6.9.1 this repo used the jshint preset, which recognised only `[[FEAT]]` /
`[[FIX]]` subjects and silently ignored `fix:` / `feat:`. Older CHANGELOG entries
still read that way.

## 出问题了怎么判断

| 现象 | 怎么办 |
|---|---|
| 某个平台的包没上传 | 用上面「重新打包」入口，填那个 tag 重跑一遍 |
| 整个 release 都没出来（tag 都没打） | 看 `release` workflow 里 **Release Linux** 的日志：偶发问题（网络 / runner）就重跑那次失败的 run；代码问题就修好后再推一个带 `fix:` 或 `feat:` 的提交 |
| 手动补包跑完，release 里还是缺东西 | 看那次 run 里哪个 job 红了。**冒烟测试没通过时上传会被拦住**（故意的：宁可不上传，也不发没验证过的包） |
| 想核对下载到的文件 | release 里有 `SHA256SUMS`，`shasum -a 256 -c SHA256SUMS`（macOS / Linux） |

## 两个不能碰的地方

- **v6.8.18 release 里的 `bityuan-windows-amd64-qt.exe` 不能删、不能改名、不能覆盖**——
  它是 Qt 安装包的"壳"，打包时会去下载它（76MB）。这是**唯一保留无版本号**的资产，
  CI 用它打出来的包是带版本号的。要换壳得改 `release.yml` 里那一行。
- Qt 包里的钱包 GUI（`bityuan-qt.exe`）还是 2022 年的版本，CI 只替换里面的节点二进制和配置，
  **不验证 GUI**；装完能不能正常用，只能在 Windows 上人工点一遍确认。
