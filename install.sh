#!/bin/bash
# ==========================================================
# KOMPLEKSOWY SKRYPT KONFIGURACYJNY SYSTEMU (LINUX Ubuntu)
# ==========================================================

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERROR='\033[0;31m'
NC='\033[0m'

if [[ "$EUID" -eq 0 ]]; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERROR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}"
    else
        echo -e "${ERROR}✘ Do not run this script as root. Run as a normal user with sudo.${NC}"
    fi
    exit 1
fi

printf '\033[?7h\n'
sudo -v
CURRENT_USER=$(whoami)
SUDOERS_TMP="$(mktemp)"
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
if sudo visudo -cf "$SUDOERS_TMP"; then
    sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
else
    rm -f "$SUDOERS_TMP"
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERROR}✘ Nieprawidłowa składnia reguły sudoers - przerywam.${NC}"
    else
        echo -e "${ERROR}✘ Invalid sudoers rule syntax - aborting.${NC}"
    fi
    exit 1
fi
rm -f "$SUDOERS_TMP"

TMP_LOG="$(mktemp /tmp/install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

printf '\033[?7l' >&3

cleanup_on_exit() {
    local exit_code=$?
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERROR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERROR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    sudo rm -f /etc/sudoers.d/99-temp-installer 2>/dev/null || true
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERROR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    local bar_width=50
    local reserved=12
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 1))}…"
    fi

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ $filled -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ $empty -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
}

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    MSG_PHASE_1="[1/3] Przygotowanie repozytoriów i aktualizacja systemu..."
    MSG_PHASE_2="[2/3] Usuwanie zbędnych pakietów i instalacja aplikacji..."
    MSG_PHASE_3="[3/3] Konfiguracja usług, środowiska ZSH i optymalizacja..."
else
    MSG_PHASE_1="[1/3] Preparing repositories and updating system..."
    MSG_PHASE_2="[2/3] Removing unwanted packages and installing apps..."
    MSG_PHASE_3="[3/3] Configuring services, ZSH environment, and optimization..."
fi

TOTAL_STEPS=12
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DEB_DIR="/tmp/debs_$$"

source /etc/os-release
OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
echo "Wykryty system: ${PRETTY_NAME:-nieznany}, codename: ${OS_CODENAME:-nieznany}"
wait_for_apt() {
    sudo systemctl stop packagekit 2>/dev/null || true
    while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo killall -0 apt apt-get dpkg 2>/dev/null; do
        sleep 3
    done
}

safe_apt_update() {
    local out rc
    set +e
    out=$(sudo apt-get update -yq 2>&1)
    rc=$?
    set -e
    echo "$out"
    [[ $rc -eq 0 ]] && return 0

    local broken_urls
    broken_urls=$(echo "$out" | grep -oP '(?:Błąd|Err):[0-9]+ \Khttps?://\S+' | sort -u)
    local removed=0
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        local host_path="${url#http://}"
        host_path="${host_path#https://}"
        for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
            [[ -f "$f" ]] && if grep -qF "$host_path" "$f" 2>/dev/null; then
                sudo rm -f "$f"
                removed=1
            fi
        done
    done <<< "$broken_urls"

    if [[ $removed -eq 1 ]]; then
        wait_for_apt
        sudo apt-get update -yq || true
    fi
}

add_ppa_and_install() {
    local ppa="$1"; shift
    local packages=("$@")
    if ! command -v add-apt-repository &>/dev/null; then return 1; fi
    if ! sudo add-apt-repository -y "ppa:$ppa" 2>/dev/null; then return 1; fi

    wait_for_apt
    if sudo apt-get update -yq && sudo apt-get install -yq "${packages[@]}"; then
        return 0
    fi

    sudo add-apt-repository --remove -y "ppa:$ppa" 2>/dev/null || true
    wait_for_apt
    sudo apt-get update -yq || true
    return 1
}

# ==========================================================
# ETAP 1/3: PRZYGOTOWANIE REPOZYTORIÓW I AKTUALIZACJA
# ==========================================================
show_progress 0 $TOTAL_STEPS "$MSG_PHASE_1"

if [[ -f "$SCRIPT_DIR/.update.sh" ]]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

wait_for_apt
sudo sed -i '/cdrom/s/^/#/' /etc/apt/sources.list 2>/dev/null || true
sudo dpkg --add-architecture i386 || true

if command -v add-apt-repository &>/dev/null; then
    sudo add-apt-repository -y universe  2>/dev/null || true
    sudo add-apt-repository -y multiverse 2>/dev/null || true
fi

show_progress 1 $TOTAL_STEPS "$MSG_PHASE_1"

wait_for_apt
safe_apt_update
for pkg in curl wget gnupg pciutils; do
    sudo apt-get install -yq "$pkg" || true
done
sudo mkdir -p /etc/apt/keyrings
sudo chmod 755 /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/google-chrome.gpg ]; then
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/google-chrome.gpg
    sudo chmod 644 /etc/apt/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
fi

show_progress 2 $TOTAL_STEPS "$MSG_PHASE_1"

sudo mkdir -p /usr/share/keyrings
sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
BRAVE_KEY_ID="0686B78420038257"
BRAVE_GNUPGHOME="$(mktemp -d)"
BRAVE_KEY_OK=0
if gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keyserver.ubuntu.com --recv-keys "$BRAVE_KEY_ID" 2>/dev/null \
    || gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keys.openpgp.org --recv-keys "$BRAVE_KEY_ID" 2>/dev/null; then
    if gpg --homedir "$BRAVE_GNUPGHOME" --export "$BRAVE_KEY_ID" | sudo tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null \
        && [[ -s /usr/share/keyrings/brave-browser-archive-keyring.gpg ]]; then
        BRAVE_KEY_OK=1
    fi
fi
rm -rf "$BRAVE_GNUPGHOME"

if [[ "$BRAVE_KEY_OK" -eq 1 ]]; then
    sudo chmod 644 /usr/share/keyrings/brave-browser-archive-keyring.gpg
    if ! sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources; then
        sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg /etc/apt/sources.list.d/brave-browser-release.sources
    fi
else
    sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
fi

show_progress 3 $TOTAL_STEPS "$MSG_PHASE_1"

wait_for_apt
safe_apt_update
sudo apt-get upgrade -yq || true
sudo apt-get autoremove -yq || true

# ==========================================================
# ETAP 2/3: USUWANIE PAKIETÓW I INSTALACJA APKLIKACJI
# ==========================================================
show_progress 4 $TOTAL_STEPS "$MSG_PHASE_2"

# Pakiety do całkowitego usunięcia z systemu
PACKAGES_REMOVE=(
    nano konqueror plasma-browser-integration plasma-vault krdp krfb
    plasma-thunderbolt kontact kmail kontrast plasma-welcome kaddressbook
    kdepim-runtime akonadi-server akregator korganizer epiphany decibels
    gnome-user-docs gnome-contacts gnome-maps gnome-weather gnome-calendar
    gnome-clocks kwalletmanager evolution evolution-common evolution-plugins
    evolution-ews
)

wait_for_apt
for pkg in "${PACKAGES_REMOVE[@]}"; do
    sudo apt-get purge -yq "$pkg" 2>/dev/null || true
done
sudo apt-get autoremove --purge -yq || true

# Czyszczenie pozostałości po usuniętych programach z katalogu domowego
rm -rf ~/.local/share/akonadi ~/.local/share/kmail2 ~/.local/share/local-mail ~/.local/share/contacts ~/.local/share/korganizer ~/.local/share/akregator ~/.local/share/kontact ~/.local/share/konqueror
rm -rf ~/.config/akonadi* ~/.config/kmail* ~/.config/kontact* ~/.config/korganizer* ~/.config/kaddressbook* ~/.config/akregator* ~/.config/emailidentities ~/.config/mailtransports
rm -rf ~/.cache/akonadi* ~/.cache/kmail* ~/.cache/kontact* ~/.cache/korganizer* ~/.cache/kaddressbook* ~/.cache/akregator* ~/.cache/konqueror*
rm -rf ~/.local/share/{epiphany,decibels,gnome-user-docs,gnome-contacts,gnome-maps,gnome-weather,gnome-calendar,gnome-clocks,evolution}
rm -rf ~/.config/{epiphany,decibels,gnome-user-docs,gnome-contacts,gnome-maps,gnome-weather,gnome-calendar,gnome-clocks,evolution}
rm -rf ~/.cache/{epiphany,decibels,gnome-user-docs,gnome-contacts,gnome-maps,gnome-weather,gnome-calendar,gnome-clocks,evolution}

wait_for_apt
sudo apt-get install -yq linux-firmware || true

PACKAGES_INSTALL=(
    google-chrome-stable brave-origin thunderbird qbittorrent
    libreoffice gmic mixxx kdenlive soundconverter vlc gimp krita qmmp audacity
    vim dconf-editor dconf-cli hunspell-pl bleachbit profile-sync-daemon git build-essential
    unrar-free mc btrfs-progs exfatprogs ntfs-3g os-prober
    adb fastboot fsarchiver inxi pv rsync
    p7zip-full makeself zenity innoextract needrestart flatpak timeshift
    python3-defusedxml python3-packaging python3-pip pipx python3-tqdm
    libayatana-appindicator3-1 gamemode vulkan-tools mangohud
    vkd3d-compiler goverlay winetricks
    gcc make cmake meson ninja-build
    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly
    zsh zsh-syntax-highlighting zsh-autosuggestions
)

wait_for_apt
if ! sudo apt-get install -yq "${PACKAGES_INSTALL[@]}"; then
    FAILED_PACKAGES=()
    for pkg in "${PACKAGES_INSTALL[@]}"; do
        if ! sudo apt-get install -yq "$pkg" > "/tmp/install-${pkg}.log" 2>&1; then
            FAILED_PACKAGES+=("$pkg")
        fi
    done
fi

show_progress 5 $TOTAL_STEPS "$MSG_PHASE_2"

if command -v flatpak &>/dev/null; then
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    sudo flatpak install -y flathub com.github.tchx84.Flatseal || true
    sudo flatpak install -y flathub it.mijorus.gearlever || true
fi

show_progress 6 $TOTAL_STEPS "$MSG_PHASE_2"

add_ppa_and_install "atareao/telegram" telegram || true
add_ppa_and_install "zhangsongcui3371/fastfetch" fastfetch || true
if ! add_ppa_and_install "stebbins/handbrake-releases" handbrake handbrake-cli; then
    wait_for_apt
    sudo apt-get install -yq handbrake handbrake-cli || true
fi

wait_for_apt
if ! sudo apt-get install -yq cdemu-daemon cdemu-client; then
    add_ppa_and_install "cdemu/ppa" cdemu-daemon cdemu-client || true
fi

wait_for_apt
sudo apt-get install -yq wine wine64 || true

show_progress 7 $TOTAL_STEPS "$MSG_PHASE_2"

VGA_INFO=$(lspci -nn | grep -iE "VGA|3D|Display" || true)
MODULES_FILE="/etc/initramfs-tools/modules"
add_module() { grep -q "^$1" "$MODULES_FILE" || echo "$1" | sudo tee -a "$MODULES_FILE" > /dev/null; }

HAS_NVIDIA=0; HAS_AMD=0; HAS_INTEL=0
echo "$VGA_INFO" | grep -iq "NVIDIA" && HAS_NVIDIA=1
echo "$VGA_INFO" | grep -iq "AMD"    && HAS_AMD=1
echo "$VGA_INFO" | grep -iq "Intel"  && HAS_INTEL=1

wait_for_apt

if [[ "$HAS_AMD" -eq 1 || "$HAS_INTEL" -eq 1 || ( "$HAS_NVIDIA" -eq 0 && "$HAS_AMD" -eq 0 && "$HAS_INTEL" -eq 0 ) ]]; then
    sudo apt-get install -yq libgl1-mesa-dri:i386 mesa-vulkan-drivers:i386 || true
fi
[[ "$HAS_AMD" -eq 1 ]]   && add_module "amdgpu"
[[ "$HAS_INTEL" -eq 1 ]] && add_module "i915"

if [[ "$HAS_NVIDIA" -eq 1 ]]; then
    NVIDIA_BRANCH=$(dpkg -l 2>/dev/null | grep -oP '^ii\s+nvidia-driver-\K[0-9]+' | sort -un | tail -1)
    if [[ -n "$NVIDIA_BRANCH" ]]; then
        sudo apt-get install -yq "libnvidia-gl-${NVIDIA_BRANCH}:i386" || true
    fi
    add_module "nvidia"
    add_module "nvidia_modeset"
    add_module "nvidia_uvm"
    add_module "nvidia_drm"
fi

sudo update-initramfs -u || true
wait_for_apt
sudo apt-get install -yq "linux-headers-$(uname -r)" || true

show_progress 8 $TOTAL_STEPS "$MSG_PHASE_2"

mkdir -p "$DEB_DIR"
download_deb() { wget -q --timeout=30 -O "$3" "$2" || rm -f "$3"; }
get_github_deb_url() { curl -sf "https://api.github.com/repos/${1}/releases/latest" | grep "browser_download_url.*${2}" | cut -d '"' -f 4 || true; }

download_deb "Discord" "https://discord.com/api/download?platform=linux&format=deb" "$DEB_DIR/discord.deb"
LSFG_URL=$(get_github_deb_url "YuriSizov/ls-fg" "ls-fg_.*deb")
LSFG_VK_URL=$(get_github_deb_url "YuriSizov/ls-fg-vk" "deb")
[[ -n "$LSFG_URL" ]] && download_deb "ls-fg" "$LSFG_URL" "$DEB_DIR/lsfg.deb"
[[ -n "$LSFG_VK_URL" ]] && download_deb "ls-fg-vk" "$LSFG_VK_URL" "$DEB_DIR/lsfg-vk.deb"

add_ppa_and_install "faugus/faugus-launcher" faugus-launcher || true

shopt -s nullglob
DEB_FILES=("$DEB_DIR"/*.deb)
if [[ ${#DEB_FILES[@]} -gt 0 ]]; then
    wait_for_apt
    for deb in "${DEB_FILES[@]}"; do
        sudo apt-get install -yq "$deb" || true
    done
fi
shopt -u nullglob
rm -rf "$DEB_DIR"

# ==========================================================
# ETAP 3/3: WIRTUALIZACJA, FIREWALL, ZSH, OPTYMALIZACJA
# ==========================================================
show_progress 9 $TOTAL_STEPS "$MSG_PHASE_3"

wait_for_apt
sudo apt-get install -yq virt-manager qemu-system qemu-utils libvirt-daemon-system libvirt-clients ovmf dnsmasq bluetooth bluez bluez-firmware bluez-tools ufw || true

for svc in libvirtd virtqemud; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        sudo systemctl enable --now "${svc}.service" || true
        break
    fi
done

if ! sudo virsh net-info default &>/dev/null; then
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default 2>/dev/null || true

show_progress 10 $TOTAL_STEPS "$MSG_PHASE_3"

if command -v ufw &>/dev/null; then
    [[ -f /etc/default/ufw ]] && sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw || true
    sudo ufw --force reset || true
    sudo ufw default deny incoming || true
    sudo ufw default allow outgoing || true
    sudo ufw allow in  on virbr0 || true
    sudo ufw allow out on virbr0 || true
    sudo ufw allow from 192.168.122.0/24 || true
    if dpkg -s openssh-server &>/dev/null || [[ -x /usr/sbin/sshd ]] \
        || systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        sudo ufw allow ssh || true
    fi
    sudo ufw --force enable || true
fi

for grp in libvirt libvirt-qemu kvm; do
    getent group "$grp" &>/dev/null && sudo usermod -aG "$grp" "$CURRENT_USER" || true
done

sudo systemctl enable fstrim.timer || true
sudo journalctl --vacuum-time=2d || true
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub || true
sudo update-grub || true

ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" ipv4.dns "1.1.1.1,1.0.0.1" ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002" || true
    sudo nmcli connection up "$ACTIVE_CONN" || true
fi

show_progress 11 $TOTAL_STEPS "$MSG_PHASE_3"

if command -v zsh &>/dev/null; then
    sudo chsh -s /usr/bin/zsh "$CURRENT_USER" || true
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
    fi
    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || true
    fi
    ZSHRC="$HOME/.zshrc"
    if [[ -f "$ZSHRC" ]]; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC" || true
        sed -i 's/^plugins=(.*/plugins=(git sudo systemd debian)/' "$ZSHRC" || true
        grep -q "LC_ALL=pl_PL.UTF-8" "$ZSHRC" || echo "export LC_ALL=pl_PL.UTF-8" >> "$ZSHRC"
        grep -q "^fastfetch"         "$ZSHRC" || echo "fastfetch"                  >> "$ZSHRC"
        grep -q "zsh-syntax-highlighting.zsh" "$ZSHRC" || echo "source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> "$ZSHRC"
        grep -q "zsh-autosuggestions.zsh"     "$ZSHRC" || echo "source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"         >> "$ZSHRC"
    fi
fi

mkdir -p ~/.config ~/.local
if [[ -d "$SCRIPT_DIR/.config" ]]; then cp -af "$SCRIPT_DIR/.config/." ~/.config/; fi
if [[ -d "$SCRIPT_DIR/.local" ]]; then cp -af "$SCRIPT_DIR/.local/." ~/.local/; fi

if [[ -d "$SCRIPT_DIR/bleachbit" ]]; then
    sudo mkdir -p /root/.config/bleachbit
    sudo cp -af "$SCRIPT_DIR/bleachbit/." /root/.config/bleachbit/
fi

show_progress 12 $TOTAL_STEPS "$MSG_PHASE_3"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

# ==========================================================
# RESTART SYSTEMU (Prompt)
# ==========================================================
if [[ "$SCRIPT_LANG" == "pl" ]]; then
    RESTART_PROMPT="Czy chcesz teraz zrestartować system? [T/N]: "
else
    RESTART_PROMPT="Do you want to restart the system now? [Y/N]: "
fi

if [[ -e /dev/tty ]] && (exec < /dev/tty) 2>/dev/null; then
    echo -en "${INFO}==> ${RESTART_PROMPT}${NC}" >&3
    RESTART_CHOICE=""
    read -r RESTART_CHOICE < /dev/tty || true
    case "$RESTART_CHOICE" in
        [YyTt]*)
            systemctl reboot
            ;;
        *)
            exit 0
            ;;
    esac
else
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${WARN}⚠ Brak terminala interaktywnego - pomijam pytanie o restart. Uruchom 'sudo reboot' ręcznie.${NC}" >&3
    else
        echo -e "${WARN}⚠ No interactive terminal - skipping restart prompt. Run 'sudo reboot' manually.${NC}" >&3
    fi
fi