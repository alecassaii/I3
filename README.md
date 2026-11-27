# i3 + emptty
This repo contains a guide to install `i3` with `emptty` (display manager) alongside a port of [shell-ninja](https://github.com/shell-ninja/i3-dotfiles) for void linux.
**The script does NOT install the shell automatically. See the "Post-installation" section below for more.**


# Install
To install the window manager you can follow the [guide](GUIDE.md) or use the install script by cloning the repo:
```bash
git clone https://github.com/alecassaii/I3.git
cd I3
chmod +x install.sh
./install.sh
```

or using this one-line command (**NOT WORKING RIGHT NOW**):
```bash
curl -fsSL https://raw.githubusercontent.com/alecassaii/I3/refs/heads/main/install.sh | bash
```

## Script Options
You can customize the installation by passing any of the following flags to `install.sh`:

| Flag | Description |
| :--- | :--- |
| `-a`, `--autologin` | Enable autologin for the target user |
| `-u`, `--user NAME` | User for autologin (default: current user) |
| `-l`, `--lang LOCALE` | Locale for `emptty` (default: `it_IT.UTF-8`) |
| `-t`, `--tty N` | TTY number for `emptty` (default: `7`) |
| `-T`, `--terminal PKG` | Terminal emulator package (default: `kitty`) |
| `-m`, `--minimal` | Use `xorg-minimal` instead of the `xorg` meta-package |
| `-n`, `--no-start` | Enable `emptty` service without starting it immediately |
| `-y`, `--yes` | Skip confirmation prompts |
| `-d`, `--dry-run` | Show what would be done without making any changes |
| `-h`, `--help` | Show help message and exit |

### Examples
Run locally with custom options:
```bash
./install.sh --autologin --lang en_US.UTF-8 --terminal alacritty
```

Pass flags using the one-line command (`-s --` is required):
```bash
curl -fsSL https://raw.githubusercontent.com/alecassaii/I3/refs/heads/main/install.sh | bash -s -- --autologin --yes
```


# Post-installation
After the installation you can login with your user and password and enjoy your barebone `i3`.  
If you want the shell, run the script inside the `shell/` directory or run this command from the root of the directory:
```bash
./shell/shell.sh
```
