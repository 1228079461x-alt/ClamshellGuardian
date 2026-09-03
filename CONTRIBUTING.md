# 参与贡献

欢迎提交可复现的问题、Apple Silicon 型号兼容结果和代码改进。提交 Pull Request 前请运行：

```sh
swift run ClamshellGuardianPolicyTests
./scripts/build.sh
```

涉及 Helper、IPC、安装流程、截止条件或 `pmset` 的改动必须附测试，并说明失败时如何确保 `SleepDisabled` 恢复。真实闭盖测试只能在接电、坚硬且通风的桌面上进行；测试后必须记录 `pmset -g` 的恢复结果。

请勿在 issue 或日志中上传 Mac 序列号、Hardware UUID、Wi‑Fi 密码或私人项目内容。
