# macOS 隐私授权

服务由应用包内的 `Contents/Library/LaunchServices/peanut-service-supervisor` 启动。它作为常驻 LaunchAgent 运行，桌面应用和 MCP 共用它。macOS 的责任程序可能是这个 helper，而不是桌面应用或 `/bin/sh`；以系统日志的 `AUTHREQ_SUBJECT` 和 `responsible_path` 为准。

## 构建与身份

使用原有入口 `./scripts/package-app.sh` 或 `./scripts/install-app.sh`。打包必须在 `lipo` 和 `strip` 全部完成后签名，先签嵌套 helper，再签整个应用包。脚本校验所有架构和包内资源，不能把编译器附带的 arm64 linker 签名视为整个通用应用已签名。

默认 ad-hoc 签名不需要开发者账号，适合本机使用。有效签名下的同一文件具有固定的代码要求；改动二进制或重新签名可能改变 CDHash，从而需要重新授权。不能把“每次更新需要重新授权”与“同一安装每次使用都弹窗”混为一谈；后者需要检查实际责任进程、运行映像、磁盘签名以及旧授权的代码要求。

已有证书时，可选用 `security find-identity -v -p codesigning` 列出的完整 SHA-1 指纹，例如 `PSM_CODESIGN_IDENTITY=<指纹> ./scripts/install-app.sh`。脚本只接受有效身份的精确指纹，不自动选择、创建、导入或信任证书。保持同一签名身份和标识有利于跨构建授权连续性；仍需实际核对 designated requirement，不保证切换证书后免授权。

校验已安装版本：

```sh
codesign --verify --all-architectures --strict '/Applications/Peanut Service Manager.app/Contents/Library/LaunchServices/peanut-service-supervisor'
codesign --verify --all-architectures --deep --strict '/Applications/Peanut Service Manager.app'
codesign -d -r- '/Applications/Peanut Service Manager.app/Contents/Library/LaunchServices/peanut-service-supervisor'
```

## 共享运行的更新窗口

安装脚本在构建前检查已安装客户端及已加载 supervisor，存在时停止更新，不覆盖运行中的包、不停止服务。先核对当前真实消费者，由其 owner 在安全窗口正常结束服务和客户端，再卸载自有 LaunchAgent；没有确认窗口时仅准备构建产物。退出桌面应用不代表 MCP 客户端和 supervisor 已退出，也不能因服务端口仍可访问就假定失去 supervisor 不会产生影响。

## 授权对象

完整签名后，2026-10-28 本机实际请求的 `AUTHREQ_SUBJECT` 为 `org.peanutopensource.PeanutServiceManager`，责任进程仍是 supervisor。系统设置 → 隐私与安全性 → 文件与文件夹中对应 `Peanut Service Manager`（花生服务管理器）的“文稿”文件夹；右键“在访达中显示”应定位 `/Applications/Peanut Service Manager.app`。旧的同名 helper 权限条目不能代替这个新主体的授权。

对于仍以 helper 路径为主体的旧安装，在同一页面展开 `peanut-service-supervisor`，核对“文稿”文件夹。存在同名条目时，通过右键“在访达中显示”核对真实位置，安装版 helper 应为：

`/Applications/Peanut Service Manager.app/Contents/Library/LaunchServices/peanut-service-supervisor`

Finder 可用“前往文件夹”定位上述隐藏包内路径。只给需要的目录权限；不默认扩大为完全磁盘访问权限、不修改 TCC 数据库、不全局重置授权。授权开关已开但日志仍提示代码要求不匹配时，先修复和固定程序身份，随后在准确条目上重新授权，并通过实际文件访问确认复用。文件与文件夹列表由系统访问请求产生，不能任意添加文件。

本次实际验证：用户为新应用主体允许一次“文稿”后，恢复 ST、文档站和两个原型服务，五个既有 HTTP 入口均返回 200，观察窗口内没有新的 `AUTHREQ_PROMPTING` 或代码要求不匹配。此结果覆盖本次安装和这些访问路径；不代表未来改动二进制后无需重新授权。

参考：[Apple DTS 对 ad-hoc 签名和责任归属的说明](https://developer.apple.com/forums/thread/125438)、[Apple 代码签名要求说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/)。
