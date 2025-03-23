# Auto-Installer-Forge
An automated tool that processes ROMs containing **payload.bin**, converts them into a ready-to-flash **super.img**, and generates a fully automated installation package for Fastboot or Recovery, which can later be flashed using my custom flasher scripts.

## Test runs - copy and paste in termux or adb shell with root access

```bash
su -c "cd / && mkdir -p /dev/tmp && cd /dev/tmp && curl -sSL -o auto_installer https://raw.githubusercontent.com/arkt-7/Auto-Installer-Forge/main/auto_installer && chmod 777 auto_installer && su -c ./auto_installer"
```

