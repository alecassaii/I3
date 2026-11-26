# Installing and Configuring i3 with emptty on Void Linux
**Note on shell prerequisites:** The file-writing commands contained in this guide (based on `tee` and *heredoc* `EOF`) are designed to be compatible with the **Bash** shell. If you are using an alternative shell such as `fish` or `zsh`, start an interactive session first by running:

 ``` bash
 bash
 ```




## 1. Installing Base Packages

Synchronize the system repositories and install the Xorg display server, the `i3` window manager, the `emptty` display manager, the session services (`dbus`, `elogind`), and a terminal emulator (`kitty`):

```bash
sudo xbps-install -Syu
sudo xbps-install -S xorg xinit i3 i3status dmenu emptty dbus elogind kitty
```

*(Note: if you prefer a minimal installation instead of the `xorg` meta-package, use `xorg-minimal` and manually add the video drivers for your graphics card. Instead of `kitty`, you can install any other terminal such as `alacritty` or `xterm`).*

### Verification
Check that the main packages are installed (`ii`):

```bash
xbps-query -l | grep -E "i3|emptty"
```




## 2. Enabling System Services (runit)

Void Linux uses **runit** as its init system and does not automatically start daemons after installation. Create the symbolic links to enable `dbus` and `elogind`:

```bash
sudo ln -sv /etc/sv/dbus /var/service/
sudo ln -sv /etc/sv/elogind /var/service/
```

### Verification
Make sure both services are active (the output must start with `run:`):

```bash
sudo sv status dbus elogind
```




## 3. Configuring `emptty`

The `i3` package automatically generates the session file `/usr/share/xsessions/i3.desktop`, making a custom `~/.xinitrc` file unnecessary. Overwrite the `/etc/emptty/conf` file with the standard configuration via `tee`:

```bash
sudo tee /etc/emptty/conf > /dev/null << 'EOF'
TTY_NUMBER=7
SWITCH_TTY=true
PRINT_ISSUE=true
DEFAULT_USER=
AUTOLOGIN=false
AUTOLOGIN_SESSION=
LANG=it_IT.UTF-8
DBUS_LAUNCH=true
ALWAYS_DONT_SWITCH=false
EOF
```

### Main Parameters
* **`TTY_NUMBER=7`:** On Void Linux, virtual terminals `tty1`–`tty6` are occupied by `agetty` by default; `tty7` is free and avoids conflicts.
* **`DBUS_LAUNCH=true`:** Starts a D-Bus user session alongside i3, ensuring the proper functioning of file managers, notifications, and GTK/Flatpak portals.

### **Optional**: Enabling Autologin
If you want to log directly into i3 without entering a password at boot, run these commands:
```bash
sudo usermod -aG nopasswdlogin $(whoami)

sudo tee /etc/emptty/conf > /dev/null << 'EOF'
TTY_NUMBER=7
SWITCH_TTY=true
PRINT_ISSUE=true
DEFAULT_USER=<tuo_utente>
AUTOLOGIN=true
AUTOLOGIN_SESSION=i3
LANG=it_IT.UTF-8
DBUS_LAUNCH=true
ALWAYS_DONT_SWITCH=false
EOF
```
### Verification
Check the actual contents of the configuration file:

```bash
cat /etc/emptty/conf
```




## 4. Starting the `emptty` Service

If you have another display manager active (e.g., `lightdm`, `sddm`, `gdm`), remove its symbolic link from `/var/service/` first. Next, enable `emptty`:

```bash
sudo ln -sv /etc/sv/emptty /var/service/
```

The service will start immediately and switch you to `tty7`, displaying the text-based login prompt.

### Verification
If you run the check from another TTY, verify that the daemon is running:

```bash
sudo sv status emptty
```




## 5. First Login to i3

1. On the `emptty` login screen (also accessible via `Ctrl+Alt+F7`), enter your **username** and **password** (use the arrow keys to select `i3` if other desktop environments are present).
2. On first launch, `i3-config-wizard` will run: follow the on-screen instructions to generate `~/.config/i3/config` and choose the `$mod` modifier key (`Super`/`Win` or `Alt`).

### Verification
* Press `$mod+Enter` to open the terminal emulator.
* Press `$mod+d` to open `dmenu` at the top of the screen.
