# WindTerm macOS 修复集

本目录是针对 **WindTerm 2.7.0 (macOS, x86_64)** 的几个已确认问题的修复与诊断工具。

所有改动都是**可逆、幂等、可重复执行**的，不会破坏原始安装。

| 问题 | 类型 | 状态 |
|---|---|---|
| A. keyboard-interactive 认证时崩溃 | 可修复 | ✅ 已修复（客户端持久化补丁） |
| B. macOS 提示「Intel 组件将不再支持」 | 不可客户端修复 | ⚠️ 已诊断，附替代路径 |
| C. 捆绑 libssh 0.9.5 已 EOL、新工具链编译不过 | 可修复 | ✅ 已修复（可编译 + arm64） |

---

## A. keyboard-interactive 认证崩溃

### 现象

连接提供 `keyboard-interactive` 认证的 SSH 服务器时，WindTerm 在认证阶段**直接崩溃退出**（不是报错、不是连不上）。

实测环境：macOS 26.7 (arm64) + Rosetta 2 + WindTerm 2.7.0，目标服务器 `:6122`（非 22 端口），
认证方式 `publickey,password,keyboard-interactive`。

### 崩溃证据

三份系统崩溃报告签名完全一致：

```
EXC_BAD_ACCESS (SIGSEGV)
KERN_INVALID_ADDRESS at 0x8        <- 空指针解引用
Thread: QThread
  0  Ssh::Session::authInteractive(QByteArray const&)
  1  SshBridge::authInteractive(QVariant const&, QByteArray const&)::$_5
  2  SshOperator::execute()
  3  QTimer::timerEvent(QTimerEvent*)
```

`0x8` 是典型的「访问空对象的第 8 字节成员」。故障点在 WindTerm 闭源的应用层，
`src/` 里没有对应源码，因此**无法从源码侧修**。

### 根因

服务端声明支持 `keyboard-interactive`，客户端便会尝试该认证方式并进入
`authInteractive` 路径，该路径在拿不到交互提示对象时未做空值检查，直接解引用。

与端口号无关——非 22 端口只是让会话走到认证这一步，容易被误判成「非 22 端口的 SFTP 问题」。

### 修复

关闭客户端的 keyboard-interactive 尝试，只走 password / publickey：

```bash
cd fixes/windterm-kbdint-crash
./install.sh                    # 打补丁 + 安装 LaunchAgent
```

- `fix-windterm-kbdint.sh` —— 把 `session.config` 里 `ssh.authKeyboardInteractive` 置为 `false`；
  幂等；修改后自动用 `plutil` 校验 JSON，校验失败自动回滚。
- `install.sh` —— 安装 LaunchAgent，在**登录时**和**配置目录被改动时**（升级/重装会触发）
  自动重新应用补丁，实现「永久」生效。
- `uninstall.sh` —— 卸载并恢复默认值。

手动执行（不装 LaunchAgent）：

```bash
./fix-windterm-kbdint.sh /Applications/WindTerm.app
```

> LaunchAgent 需要在你自己的**终端.app**里加载。在非 GUI 会话/受限进程中
> `launchctl bootstrap` 会返回 `5: Input/output error`，属正常现象，脚本会提示手动命令。

### 另一种修法（服务端）

不想动客户端，可以在服务器 `sshd_config` 关闭该认证方式：

```
KbdInteractiveAuthentication no
```

重启 sshd 即可。代价是所有依赖 keyboard-interactive 的客户端都会受影响。

---

## B. 「Intel 组件将不再支持」

### 诊断结果

```
[1] 主程序架构      Mach-O 64-bit executable x86_64
[3] Mach-O 文件总数 39，非 64 位组件 0
```

应用内 39 个 Mach-O 全部是 **x86_64 单架构**，没有任何 32 位或异架构组件。

所以系统提示的「包含一个与 macOS 后续版本不兼容的组件」，指的是**整个应用是 Intel 单架构**，
并不存在某个可以单独替换掉的坏组件。

运行诊断：

```bash
./fixes/intel-deprecation/check-intel-deprecation.sh
```

### 为什么不能在客户端修复

WindTerm 只开放了基础模块（libssh / Pty / Widgets / Utility），
SSH 会话、SFTP、UI 等应用层是闭源的，**无法重新编译出 arm64 版本**。
官方 Release 至今（2.7.0）也只提供 `Mac_Portable_x86_64`。

### 可选路径

1. 继续用 Rosetta 2 运行——目前完全可用，Apple 尚未移除该能力；
2. 关注上游是否发布 arm64 构建；
3. 迁移到原生 arm64 终端（WezTerm / iTerm2 / Tabby）。

---

## C. 捆绑 libssh 0.9.5

### 问题

`src/libssh` 基于 libssh **0.9.5**（2021 年），上游早已 EOL。
在 macOS 14+ / Xcode 16+ / OpenSSL 3 环境下直接编译失败：

```
src/init.c:272:24: error: a function declaration without a prototype is
deprecated in all versions of C [-Werror,-Wstrict-prototypes]
```

### 已修改

| 文件 | 修改 |
|---|---|
| `src/libssh/src/init.c` | `is_ssh_initialized()` → `is_ssh_initialized(void)`（与头文件声明对齐） |
| `src/libssh/examples/sshnetcat.c` | `cleanup_pcap()` → `cleanup_pcap(void)` |
| `src/libssh/tests/sftp_stress/main.c` | `signal_stop()` / `thread()` 补 `void` |
| `src/libssh/CMakeLists.txt` | `cmake_minimum_required` 3.3.0 → **3.10**（CMake 4.x 已移除对 <3.5 的兼容） |

### 验证

```bash
cd fixes/libssh-modern
./build.sh              # 默认 arm64
ARCH=x86_64 ./build.sh  # Intel
```

实测结果（macOS 26.7 / Apple Silicon / CMake 3.31.5 / OpenSSL 3.6.3）：

```
configure exit=0
build     exit=0   (0 errors)
lib/libssh.dylib: Mach-O 64-bit dynamically linked shared library arm64
  -> /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib
```

### 局限（重要）

这只是让 0.9.5 **在新工具链上能编译、能跑**，并没有把它升级到 0.10/0.11。
WindTerm 在 libssh 上做了私有改造（pageant、external socket、额外的
hmac-md5-96 / hmac-sha1-96 等），整体升版本需要重新移植这些补丁，
且无法用闭源的应用层做回归验证，风险高于收益。

若确实要升版本，建议单独开分支，逐项对齐上述私有补丁后再合入。
