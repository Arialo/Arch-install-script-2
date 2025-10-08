#!/bin/bash

# Arch Linux Post-Installation Configuration Script
# Run this script after the base system installation is complete

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Check if we're in a chroot environment or installed system
if [[ ! -f /etc/arch-release ]] && [[ ! -f /etc/os-release ]]; then
    print_error "This doesn't appear to be an Arch Linux system"
    exit 1
fi

print_status "Arch Linux Post-Installation Configuration"
echo "This script will configure your system after base installation"
echo ""

# Get user configuration
print_status "User Configuration:"
read -p "Enter the username that was created during installation: " username

# Validate user exists
if ! id "$username" &>/dev/null; then
    print_error "User $username does not exist!"
    exit 1
fi

# Timezone configuration
echo ""
print_status "Timezone Configuration:"
echo "Current timezone: $(timedatectl show --property=Timezone --value)"
echo "Examples: America/New_York, Europe/London, Asia/Tokyo, UTC"
echo "You can also run 'timedatectl list-timezones' to see all available timezones"
read -p "Enter your timezone (or press Enter to keep current): " timezone
if [[ -n "$timezone" ]]; then
    timedatectl set-timezone "$timezone"
    print_success "Timezone set to $timezone"
fi

# Hostname configuration
# Generate a fun default hostname
generate_hostname() {
    local prefixes=("turbo" "hyper" "mystic" "ultra" "mega" "cyber" "nano" "quantum" "stellar" "cosmic")
    local colors=("blue" "cyan" "purple" "magenta" "crimson" "azure" "indigo" "violet" "teal" "cobalt")
    local prefix=${prefixes[$RANDOM % ${#prefixes[@]}]}
    local color=${colors[$RANDOM % ${#colors[@]}]}
    local numbers=$(printf "%04d" $((RANDOM % 10000)))
    echo "${prefix}-${color}-${numbers}"
}

default_hostname=$(generate_hostname)
echo "Default hostname suggestion: $default_hostname"
read -p "Enter new hostname (or press Enter to keep current): " new_hostname
if [[ -n "$new_hostname" ]]; then
    # Validate hostname
    if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9-]+$ ]] || [[ ${#new_hostname} -gt 63 ]]; then
        print_warning "Invalid hostname. Using generated default: $default_hostname"
        new_hostname="$default_hostname"
    fi
    
    # Set hostname
    echo "$new_hostname" > /etc/hostname
    hostnamectl set-hostname "$new_hostname"
    
    # Update hosts file
    sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname.localdomain\t$new_hostname/" /etc/hosts
    print_success "Hostname set to $new_hostname"
fi

# Desktop Environment Selection
echo ""
print_status "Desktop Environment Selection:"
echo "1) GNOME (with GDM)"
echo "2) KDE Plasma (with SDDM)"
echo "3) XFCE (with LightDM)"
echo "4) OpenBox (minimal, with LightDM)"
echo "5) Niri (Wayland compositor)"
echo "6) Hyprland (Wayland compositor with SDDM)"
echo "7) Minimal (no desktop environment)"
echo "8) Skip desktop environment installation"

read -p "Select desktop environment (1-8): " de_choice

# AUR Helper Installation Choice
echo ""
print_status "AUR Helper Installation:"
echo "yay is an AUR helper that allows easy installation of AUR packages."
echo "Note: yay installation may sometimes fail due to dependency issues."
read -p "Install yay AUR helper? (y/N): " install_yay
if [[ "$install_yay" =~ ^[Yy]$ ]]; then
    INSTALL_YAY=true
else
    INSTALL_YAY=false
fi

# Set packages based on choice
case $de_choice in
    1)
        DE_PACKAGES="gnome gnome-extra "
        LOGIN_MANAGER="gdm"
        ;;
    2)
        DE_PACKAGES="plasma kde-applications "
        LOGIN_MANAGER="sddm"
        ;;
    3)
        DE_PACKAGES="xfce4 xfce4-goodies "
        LOGIN_MANAGER="lightdm lightdm-gtk-greeter"
        ;;
    4)
        DE_PACKAGES="openbox xorg-server xorg-xinit  pcmanfm lxappearance tint2 feh xterm"
        LOGIN_MANAGER="lightdm lightdm-gtk-greeter"
        ;;
    5)
        DE_PACKAGES="niri  foot wofi waybar"
        LOGIN_MANAGER=""
        ;;
    6)
        DE_PACKAGES="hyprland  kitty wofi waybar hyprpaper hypridle hyprlock"
        LOGIN_MANAGER="sddm"
        ;;
    7)
        DE_PACKAGES=""
        LOGIN_MANAGER=""
        ;;
    8)
        DE_PACKAGES=""
        LOGIN_MANAGER=""
        ;;
    *)
        print_error "Invalid selection. Defaulting to GNOME."
        DE_PACKAGES="gnome gnome-extra "
        LOGIN_MANAGER="gdm"
        ;;
esac

# Install desktop environment if selected
if [[ -n "$DE_PACKAGES" ]]; then
    print_status "Installing desktop environment and packages..."
    pacman -Sy --noconfirm $DE_PACKAGES
    print_success "Desktop environment packages installed"
fi

# Enable login manager if selected
if [[ -n "$LOGIN_MANAGER" ]]; then
    print_status "Enabling login manager: $LOGIN_MANAGER"
    systemctl enable $(echo $LOGIN_MANAGER | cut -d' ' -f1)
    print_success "Login manager enabled"
fi

# Install additional packages
print_status "Installing additional packages..."
pacman -Sy --noconfirm git wget curl firefox

# Create basic configuration files for window managers
if [[ "$de_choice" == "4" ]]; then
    print_status "Configuring OpenBox..."
    # OpenBox configuration
    mkdir -p /home/$username/.config/openbox
    cat > /home/$username/.config/openbox/autostart << 'OBEOF'
# Auto-start applications
tint2 &
feh --bg-scale /usr/share/pixmaps/archlinux-logo.png &
pcmanfm --desktop &
OBEOF
    
    # Create basic OpenBox menu
    cat > /home/$username/.config/openbox/menu.xml << 'MENUEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
<menu id="root-menu" label="Openbox 3">
  <item label="Terminal">
    <action name="Execute"><command>xterm</command></action>
  </item>
  <item label="File Manager">
    <action name="Execute"><command>pcmanfm</command></action>
  </item>
  <item label="Web Browser">
    <action name="Execute"><command></command></action>
  </item>
  <separator />
  <item label="Log Out">
    <action name="Exit"><prompt>yes</prompt></action>
  </item>
</menu>
</openbox_menu>
MENUEOF

    chown -R $username:$username /home/$username/.config
    print_success "OpenBox configured"
fi

if [[ "$de_choice" == "5" ]]; then
    print_status "Configuring Niri..."
    # Niri configuration
    mkdir -p /home/$username/.config/niri
    cat > /home/$username/.config/niri/config.kdl << 'NIRIEOF'
input {
    keyboard {
        xkb {
            layout "us"
        }
    }
}

binds {
    Mod+T { spawn "foot"; }
    Mod+D { spawn "wofi" "--show" "drun"; }
    Mod+Q { close-window; }
    Mod+Shift+E { quit; }
}

layout {
    gaps 16
}
NIRIEOF

    chown -R $username:$username /home/$username/.config
    print_success "Niri configured"
fi

if [[ "$de_choice" == "6" ]]; then
    print_status "Configuring Hyprland..."
    # Hyprland configuration
    mkdir -p /home/$username/.config/hypr
    cat > /home/$username/.config/hypr/hyprland.conf << 'HYPREOF'
# Monitor configuration
monitor=,preferred,auto,auto

# Execute at launch
exec-once = waybar
exec-once = hyprpaper

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = no
    }
    sensitivity = 0
}

# General configuration
general {
    gaps_in = 5
    gaps_out = 20
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# Decoration
decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animations
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Key bindings
$mainMod = SUPER
bind = $mainMod, T, exec, kitty
bind = $mainMod, Q, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, dolphin
bind = $mainMod, V, togglefloating,
bind = $mainMod, D, exec, wofi --show drun
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,

# Move focus with mainMod + arrow keys
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Switch workspaces with mainMod + [0-9]
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5

# Move active window to a workspace with mainMod + SHIFT + [0-9]
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
HYPREOF

    chown -R $username:$username /home/$username/.config
    print_success "Hyprland configured"
fi

# Install AUR helper if requested
if [[ "$INSTALL_YAY" == true ]]; then
    print_status "Setting up AUR helper..."
    
    # Switch to user for AUR operations
    sudo -u $username bash << 'USEREOF'
    cd /home/$username
    
    # Install yay (AUR helper)
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
    
    print_success() {
        echo -e "\033[0;32m[SUCCESS]\033[0m $1"
    }
    
    print_success "yay AUR helper installed successfully"
USEREOF
    
    if [[ $? -eq 0 ]]; then
        print_success "AUR helper installation completed"
    else
        print_error "AUR helper installation failed - you can install it manually later"
        print_status "To install yay manually:"
        echo "  sudo -u $username git clone https://aur.archlinux.org/yay.git /home/$username/yay"
        echo "  cd /home/$username/yay && sudo -u $username makepkg -si"
    fi
else
    print_status "Skipping AUR helper installation"
fi

# Final system update
print_status "Performing final system update..."
pacman -Syu --noconfirm

print_success "Post-installation configuration completed!"
print_status "System configuration:"
echo "- Username: $username"
if [[ -n "$new_hostname" ]]; then
    echo "- Hostname: $new_hostname"
fi
if [[ -n "$timezone" ]]; then
    echo "- Timezone: $timezone"
fi
echo "- Desktop Environment: $de_choice"
echo "- AUR Helper (yay): $INSTALL_YAY"

print_status "Recommended next steps:"
echo "1. Reboot the system: reboot"
echo "2. Log in with your user account"
if [[ "$de_choice" == "5" ]]; then
    echo "3. For Niri: run 'niri' from TTY or add it to your login manager"
fi
if [[ "$de_choice" == "6" ]]; then
    echo "3. For Hyprland: select Hyprland session from your login manager"
fi
echo "4. Install additional software as needed"

print_warning "Notes:"
echo "- Login managers will start on next boot"
echo "- Configuration files have been created for window managers"
