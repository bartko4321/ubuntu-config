# 🐧 Ubuntu Post-Install Setup Script

A comprehensive, automated Bash post-installation script for **Ubuntu** (and other `apt`-based derivatives). It goes well beyond desktop theming: it tunes APT and its repositories, detects your GPU and installs the matching drivers, removes unwanted default KDE/GNOME apps, installs a large set of system/multimedia/gaming packages plus Flatpak, adds external repositories (Google Chrome, Brave, Telegram, Fastfetch, HandBrake) and directly-downloaded `.deb` packages (Discord, ls-fg), configures the firewall, KVM/QEMU/libvirt virtualization, Cloudflare DNS, and sets up a Zsh environment with Oh My Zsh and Powerlevel10k.

The script auto-detects the system language (Polish/English) from the `LANG`/`LC_ALL`/`LC_MESSAGES` locale and prints all status messages accordingly.

---

## 🚀 Script Features

- **Temporary Passwordless Sudo**: Requests the admin password once at the start, then configures a temporary `NOPASSWD` rule (via `/etc/sudoers.d/`, or a `polkit`/`run0` rule on systems without `visudo`) so the rest of the script can run unattended. The rule is automatically removed at the end — including on failure, via an `EXIT` trap.
- **GPU Detection & Driver Setup**: Detects NVIDIA/AMD/Intel GPUs (and hybrid setups) via `lspci`, installs the matching 32-bit Mesa/Vulkan packages (`:i386`), and adds the correct kernel modules (`nvidia`, `nvidia_modeset`, `nvidia_uvm`, `nvidia_drm`, `amdgpu`, `i915`) to `/etc/initramfs-tools/modules`, then rebuilds the initramfs.
- **Bloatware Removal**: Uninstalls a long list of default KDE/GNOME apps not needed on a customized setup (e.g. `nano`, `konqueror`, `kontact`, `kmail`, `korganizer`, `akonadi-server`, `akregator`, `kaddressbook`, `kwalletmanager`, `krfb`, `krdp`, `plasma-vault`, `plasma-welcome`, `epiphany`, `evolution`, `gnome-maps`, `gnome-weather`, `gnome-calendar`, `gnome-clocks`, and more), then cleans up leftover config/cache/data directories in `~/.config`, `~/.cache`, and `~/.local/share`. If a Plasma environment is detected, it also disables the KWallet service.
- **APT & Repository Tuning**: Enables the `i386` architecture, adds the `universe`/`multiverse` repositories, disables the `cdrom` entry in `sources.list`, and `safe_apt_update()` automatically detects and removes broken/unreachable PPA repositories that would otherwise block `apt update`.
- **External Repositories**: Adds the official repositories and GPG keys for Google Chrome and Brave (with fallback between the `keyserver.ubuntu.com` and `keys.openpgp.org` keyservers, and a safe rollback if key retrieval fails).
- **Package Installation**: Installs a large `PACKAGES_INSTALL` set covering dev tools (`build-essential`, `git`, `gcc`, `cmake`, `meson`, `ninja-build`...), office/multimedia apps (LibreOffice, Thunderbird, GIMP, Krita, Kdenlive, Audacity, Mixxx, qBittorrent...), gaming tools (`gamemode`, `mangohud`, `vulkan-tools`, `vkd3d-compiler`, `goverlay`, `winetricks`, `wine`/`wine64`), system tools (`btrfs-progs`, `exfatprogs`, `ntfs-3g`, `os-prober`, `timeshift`, `flatpak`, `p7zip-full`, `rsync`, `inxi`...), and Zsh with the `zsh-syntax-highlighting`/`zsh-autosuggestions` plugins. If the bulk install fails, the script falls back to installing packages one by one and logs which ones actually failed.
- **Extra PPAs & .deb Packages**: Adds PPAs for Telegram, Fastfetch, and HandBrake (with a fallback to a plain `apt install`), and directly downloads and installs the Discord `.deb` package plus the latest `ls-fg`/`ls-fg-vk` releases from GitHub Releases; also installs `faugus-launcher` from a PPA.
- **CDEmu**: Installs `cdemu-daemon`/`cdemu-client` (with a PPA fallback), then masks and disables the service and hides its autostart entries, without removing the files themselves.
- **Flatpak**: Adds the Flathub remote and installs Flatseal and Gear Lever.
- **DNS Configuration**: Sets Cloudflare (`1.1.1.1`/`1.0.0.1` + IPv6) as the global NetworkManager DNS and applies it to the currently active network connection.
- **Virtualization (KVM/QEMU/libvirt)**: Installs `virt-manager`, `qemu-system`, `libvirt-daemon-system`, `ovmf`, `dnsmasq`, imports default `virt-manager` GUI preferences via `dconf load`, enables the `libvirtd`/`virtqemud` service, defines/starts/autostarts the default `libvirt` network, and adds the current user to the `libvirt`/`libvirt-qemu`/`kvm` groups.
- **Firewall & Bluetooth**: Resets and configures UFW (denies incoming traffic by default, allows outgoing, allows `virbr0`/`192.168.122.0/24` traffic and SSH if installed), then enables it; installs and prepares the Bluetooth stack (`bluetooth`, `bluez`, `bluez-firmware`, `bluez-tools`).
- **System Tuning**: Enables `fstrim.timer`, vacuums the systemd journal to entries newer than 2 days (`journalctl --vacuum-time=2d`), sets `GRUB_TIMEOUT=0`, and rebuilds the GRUB configuration.
- **Shell Setup**: If `zsh` is available, sets it as the default shell, installs Oh My Zsh (unattended) and the Powerlevel10k theme, and updates `~/.zshrc` (theme, `git sudo systemd debian` plugins, locale exports, `fastfetch` on login, syntax-highlighting/autosuggestions sourcing).
- **Dotfiles & Config Copy**: Copies an optional `.update.sh` helper script plus `.local`/`.config` directories from the script folder into the user's home directory.
- **Progress Bar & Logging**: Displays a live progress bar across 3 phases / 12 steps, sized to fit the terminal width. On failure (via an `ERR` trap), a detailed log is saved to `~/install_error_<timestamp>.log`.
- **Optional Reboot Prompt**: Unlike a silent forced reboot, this script asks **"Do you want to restart the system now? [Y/N]"** at the end.

---

## 🔍 Module Details

### 1. Permissions & Preparation
Verifies the script is **not** run as root, requests the password once, and configures a temporary `NOPASSWD` rule (sudoers or polkit/`run0`), copies optional dotfiles (`.update.sh`), and sets up error logging and the progress bar.

### 2. Repositories & System Update
Enables the `i386` architecture and `universe`/`multiverse` repositories, disables the `cdrom` entry, adds the Google Chrome and Brave repositories and GPG keys, then performs a full update (`apt-get update && apt-get upgrade`) with automatic detection and removal of broken repositories.

### 3. App Removal & Package Installation
Removes the predefined list of unwanted KDE/GNOME apps along with their home-directory leftovers, installs `linux-firmware`, a large set of system/office/multimedia/gaming packages, sets up Flatpak/Flathub, adds PPAs (Telegram, Fastfetch, HandBrake) and CDEmu, downloads and installs `.deb` packages (Discord, ls-fg, ls-fg-vk), and finally installs Wine.

### 4. GPU Detection & Drivers
Detects the GPU vendor via `lspci`, installs the matching 32-bit Mesa/Vulkan packages and, for NVIDIA, the `libnvidia-gl-<version>:i386` package matching the already-installed driver, adds the correct kernel modules to `initramfs-tools/modules`, rebuilds the initramfs, and installs the matching kernel headers.

### 5. Virtualization, Firewall & Bluetooth
Installs the full KVM/QEMU/libvirt stack along with `virt-manager`, imports default GUI settings via `dconf load`, starts the libvirt service and the default NAT network, adds the user to the relevant groups, configures and enables UFW, and installs the Bluetooth stack.

### 6. System & Network Tuning
Enables `fstrim.timer`, vacuums the systemd journal, shortens the GRUB timeout to 0 seconds, and sets Cloudflare as the DNS — both globally in NetworkManager and on the active connection.

### 7. Shell & Finalization
Sets up Zsh + Oh My Zsh + Powerlevel10k (if `zsh` is present), copies the `.config`/`.local` directories, disables KWallet on Plasma environments, removes the temporary sudo/polkit rule, and prompts the user to reboot.

---

 🚀 How to Run

1. Clone the repository to your disk
   ```bash
   git clone https://github.com/syscore88/ubuntu-config.git
   ```

2. Navigate to the folder
   ```bash
   cd ubuntu-config
   ```

3. Make the script executable
   ```bash
   chmod +x install.sh
   ```

4. Run the script
   > ⚠️ **IMPORTANT:** Run the script as a **regular user** (NOT as root/sudo). The script will ask for the administrator password at the start to configure temporary elevated privileges.
   ```bash
   ./install.sh
   ```

---

### ☕ Support the Project

If you find this tool helpful and it saved you some time, consider buying me a coffee to support further development! 

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/bartekszczecinski)

---

If you find this project useful, leave a star! ⭐

---

## ⚠️ Requirements & Notes

- A base **Ubuntu** installation (or an `apt`/`dpkg`-based system) with an internet connection — packages are installed from official repositories, PPAs, Flathub, and directly from GitHub/vendor sites (Discord, ls-fg).
- `sudo` access for the current user.
- The optional files `.update.sh`, `.local/`, `.config/`, placed alongside `install.sh`, are automatically detected and copied.
- The script **installs a large number of packages** (development tools, multimedia, gaming, and a full KVM/QEMU virtualization stack) — review the `PACKAGES_REMOVE` / `PACKAGES_INSTALL` lists and the PPA/`.deb` sections before running if you want a lighter setup.
- Most commands end with `|| true`, so a single failed step (e.g. an unreachable repository or missing package) won't abort the whole run — on a critical failure, check the generated `install_error_<timestamp>.log` file in your home directory for details.
- The GRUB configuration step (`GRUB_TIMEOUT=0`) assumes the system already boots correctly with a working GRUB bootloader in place.
