# 本机 MCP 服务

应用提供本机 STDIO MCP 服务。客户端按需启动同一应用包中的 `peanut-service-manager --mcp-server` 子进程；它不开放 TCP 监听端口，服务数据与桌面应用共用本机配置和 supervisor。最低系统版本为 macOS 12。

## Codex 配置

打开「设置 → MCP 服务」，使用「复制 Codex 配置」，将内容合并到 `~/.codex/config.toml`。配置形式如下，程序路径以设置页复制的本机安装路径为准：

```toml
[mcp_servers.peanut-service-manager]
command = "/Applications/Peanut Service Manager.app/Contents/MacOS/peanut-service-manager"
args = ["--mcp-server"]
```

保存后重启或重新连接 Codex。其他支持 STDIO 的 MCP 客户端可使用设置页的通用 JSON 配置。需要本机安装的应用包；不要配置仓库里的临时构建路径。

## 使用与安全

- 先调用 `workspace_list` 或 `target_search`，再使用返回的稳定 UUID。项目操作以外的服务操作必须同时指定 `projectID` 和 `environmentID`；响应中包含完整目标路径。
- 服务启停、状态和近期日志通过同一个 supervisor 完成。停止及重启只请求优雅停止；超过等待时间仍在运行时会返回错误，不会强制终止进程。
- 资源列表会隐藏密码和凭据引用。`resource_password_get` 只在显式指定已绑定资源及其项目、环境后返回密码；该结果是明文，应仅在确有需要时读取。
- 对配置的更改与桌面端共用文件锁；如果另一个客户端先修改了数据，本次修改会拒绝并要求重新读取目标。
- 本地密文使用设置中的加密 key；MCP 的设置读取不返回 key。设置更新可修改 key，但不会在结果中回显。

## 提供的工具

`target_search`、`workspace_list`、`project_save`、`project_delete`、`environment_save`、`environment_attach`、`environment_detach`、`environment_delete`、`group_save`、`group_delete`、`service_save`、`service_delete`、`service_start`、`service_stop`、`service_restart`、`service_status`、`service_logs`、`resource_list`、`resource_save`、`resource_delete`、`resource_status`、`resource_password_get`、`resource_password_set`、`binding_save`、`binding_delete`、`settings_get`、`settings_set`。

`service_save` 支持服务绑定 IP（`host`）、端口（`port`）和多个访问域名（`domains` 字符串数组）；绑定地址校验 IPv4 / IPv6，数组每项支持普通域名和完整 HTTP/HTTPS URL。`domains` 替换整份列表，空数组清除，省略时保留；空行和完全重复的条目会被移除，每项均校验。`host` 省略时保留、空字符串清除。

MCP 暂不提供配置文件导入、导出；请在应用设置页使用对应功能。

## 排查

1. 确认 `/Applications/Peanut Service Manager.app/Contents/MacOS/peanut-service-manager` 存在且可执行。
2. 在客户端检查 MCP 连接状态；如果客户端启动失败，检查其 MCP 配置中的 `command` 路径和 `--mcp-server` 参数。
3. 若 supervisor 请求失败，在桌面应用中检查服务状态；MCP 与桌面端共用 supervisor，不需额外安装或单独启动服务。
