# 卸载与恢复

## 正常卸载

1. 打开菜单栏盾牌。
2. 若会话正在运行，先点“立即停止”。
3. 选择“卸载管理员组件与数据…”，输入管理员密码。
4. 确认 `pmset -g | grep -i SleepDisabled` 显示 `0` 或 `No`。
5. 把“合盖守护.app”移到废纸篓。

应用会移除：

- `/Library/LaunchDaemons/com.xufeiyang.clamshellguardian.helper.plist`
- `/Library/PrivilegedHelperTools/com.xufeiyang.clamshellguardian.helper`
- `/var/db/com.xufeiyang.clamshellguardian.session.json`
- `/var/run/com.xufeiyang.clamshellguardian.sock`
- `/var/log/clamshellguardian-helper.log`
- `~/Library/Application Support/合盖守护/` 中的会话数据

## 紧急恢复

如果应用无法打开，先执行：

```sh
sudo /usr/bin/pmset -a disablesleep 0
pmset -g | grep -i SleepDisabled
```

值恢复为 `0`/`No` 后，Mac 才恢复普通合盖睡眠。不要在状态未确认时将电脑放入包中。
