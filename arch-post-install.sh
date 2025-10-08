#!/bin/bash

# Arch Linux Post-Installation Configuration Script
# Run this script after the base system installation is complete

set -e  # Exit on any error

# State file for tracking post-installation progress
POST_STATE_FILE="/tmp/arch-post-install-state"

# Try to inherit state from main installation if available
if [[ -f "/tmp/arch-install-state" ]] && [[ ! -f "$POST_STATE_FILE" ]]; then
    cp "/tmp/arch-install-state" "$POST_STATE_FILE"
fi

# Function to check if a step is completed
step_completed() {
    grep -q "^$1=completed$" "$POST_STATE_FILE" 2>/dev/null
}

# Function to mark a step as completed
mark_step_completed() {
    echo "$1=completed" >> "$POST_STATE_FILE"
}

# Function to get state value
get_state_value() {
    grep "^$1=" "$POST_STATE_FILE" 2>/dev/null | cut -d'=' -f2
}

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
if ! step_completed "post_user_config"; then
    print_status "User Configuration:"
    read -p "Enter the username that was created during installation: " username
    
    # Validate user exists
    if ! id "$username" &>/dev/null; then
        print_error "User $username does not exist!"
        exit 1
    fi
    
    echo "username=$username" >> "$POST_STATE_FILE"
    mark_step_completed "post_user_config"
else
    username=$(get_state_value "username")
    print_status "Using previous username: $username (skipping validation)"
    
    # Still validate user exists
    if ! id "$username" &>/dev/null; then
        print_error "User $username does not exist!"
        exit 1
    fi
fi

# Timezone configuration
if ! step_completed "timezone_config"; then
    echo ""
    print_status "Timezone Configuration:"
    echo "Current timezone: $(timedatectl show --property=Timezone --value)"
    echo "Examples: America/New_York, Europe/London, Asia/Tokyo, UTC"
    echo "You can also run 'timedatectl list-timezones' to see all available timezones"
    read -p "Enter your timezone (or press Enter to keep current): " timezone
    if [[ -n "$timezone" ]]; then
        timedatectl set-timezone "$timezone"
        print_success "Timezone set to $timezone"
        echo "timezone=$timezone" >> "$POST_STATE_FILE"
    fi
    mark_step_completed "timezone_config"
else
    print_status "Timezone already configured (skipping)"
fi

# Hostname configuration
if ! step_completed "hostname_config"; then
    echo ""
    print_status "Hostname Configuration:"
    current_hostname=$(cat /etc/hostname 2>/dev/null || echo "archlinux")
    echo "Current hostname: $current_hostname"
    
    # Generate a fun default hostname
    generate_hostname() {
        local prefixes=("turbo" "hyper" "mystic" "ultra" "mega" "cyber" "nano" "quantum" "stellar" "cosmic")
        local colors=("blue" "cyan" "purple" "magenta" "crimson" "azure" "indigo" "violet" "teal" "cobalt")
        local prefix=${prefixes[$RANDOM % ${#prefixes[@]}]}
        local color=${colors[$RANDOM % ${#colors[@]}]}
        local numbers=$(printf "%04d" $((RANDOM % 10000)))
        
        # Capitalize first letter of each word and remove dash
        prefix="$(tr '[:lower:]' '[:upper:]' <<< ${prefix:0:1})${prefix:1}"
        color="$(tr '[:lower:]' '[:upper:]' <<< ${color:0:1})${color:1}"
        
        echo "${prefix}${color}${numbers}"
    }
    
    # Interactive hostname selection with reroll
    while true; do
        default_hostname=$(generate_hostname)
        echo "Hostname suggestion: $default_hostname"
        echo "Options:"
        echo "  1) Use this hostname"
        echo "  2) Generate another (reroll)"
        echo "  3) Enter custom hostname"
        echo "  4) Keep current hostname"
        
        read -p "Choose option (1-4): " hostname_choice
        
        case $hostname_choice in
            1)
                new_hostname="$default_hostname"
                break
                ;;
            2)
                echo "Generating new hostname..."
                continue
                ;;
            3)
                read -p "Enter custom hostname: " new_hostname
                if [[ -n "$new_hostname" ]]; then
                    break
                else
                    print_warning "Empty hostname entered, generating new suggestion..."
                    continue
                fi
                ;;
            4)
                new_hostname=""
                break
                ;;
            *)
                print_warning "Invalid option. Please choose 1-4."
                continue
                ;;
        esac
    done
    
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
        echo "new_hostname=$new_hostname" >> "$POST_STATE_FILE"
    else
        print_status "Keeping current hostname: $current_hostname"
    fi
    mark_step_completed "hostname_config"
else
    print_status "Hostname already configured (skipping)"
fi

# Desktop Environment Selection
if ! step_completed "de_selection"; then
    echo ""
    print_status "Desktop Environment Selection:"
    echo "1) GNOME (with GDM)"
    echo "2) KDE Plasma (with SDDM)"
    echo "3) XFCE (with LightDM)"
    echo "4) OpenBox (minimal, with LightDM)"
    echo "5) Niri (Wayland compositor with SDDM)"
    echo "6) Hyprland (Wayland compositor with SDDM)"
    echo "7) Minimal (no desktop environment)"
    echo "8) Skip desktop environment installation"
    
    read -p "Select desktop environment (1-8): " de_choice
    echo "de_choice=$de_choice" >> "$POST_STATE_FILE"
    mark_step_completed "de_selection"
else
    de_choice=$(get_state_value "de_choice")
    print_status "Using previous desktop environment selection: $de_choice (skipping)"
fi

# AUR Helper Installation Choice
if ! step_completed "aur_selection"; then
    echo ""
    print_status "AUR Helper Installation:"
    echo "yay is an AUR helper that allows easy installation of AUR packages."
    echo "Note: yay installation may sometimes fail due to dependency issues."
    read -p "Install yay AUR helper? (y/N): " install_yay
    if [[ "$install_yay" =~ ^[Yy]$ ]]; then
        INSTALL_YAY=true
        echo "INSTALL_YAY=true" >> "$POST_STATE_FILE"
    else
        INSTALL_YAY=false
        echo "INSTALL_YAY=false" >> "$POST_STATE_FILE"
    fi
    mark_step_completed "aur_selection"
else
    install_yay_value=$(get_state_value "INSTALL_YAY")
    if [[ "$install_yay_value" == "true" ]]; then
        INSTALL_YAY=true
    else
        INSTALL_YAY=false
    fi
    print_status "Using previous AUR helper selection: $INSTALL_YAY (skipping)"
fi

# Set packages based on choice
case $de_choice in
    1)
        DE_PACKAGES="gnome gnome-extra"
        LOGIN_MANAGER="gdm"
        ;;
    2)
        DE_PACKAGES="plasma kde-applications sddm"
        LOGIN_MANAGER="sddm"
        ;;
    3)
        DE_PACKAGES="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
        LOGIN_MANAGER="lightdm"
        ;;
    4)
        DE_PACKAGES="openbox xorg-server xorg-xinit pcmanfm lxappearance tint2 feh xterm lightdm lightdm-gtk-greeter"
        LOGIN_MANAGER="lightdm"
        ;;
    5)
        DE_PACKAGES="niri foot wofi waybar sddm"
        LOGIN_MANAGER="sddm"
        ;;
    6)
        DE_PACKAGES="hyprland kitty wofi waybar hyprpaper hypridle hyprlock sddm xdg-desktop-portal-hyprland polkit-kde-agent qt5-wayland qt6-wayland thunar pipewire wireplumber pipewire-pulse pipewire-alsa"
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
        DE_PACKAGES="gnome gnome-extra"
        LOGIN_MANAGER="gdm"
        ;;
esac


# Install desktop environment if selected
if ! step_completed "de_install" && [[ -n "$DE_PACKAGES" ]]; then
    print_status "Installing desktop environment and packages..."
    pacman -Sy --noconfirm $DE_PACKAGES
    print_success "Desktop environment packages installed"
    mark_step_completed "de_install"
elif [[ -n "$DE_PACKAGES" ]]; then
    print_status "Desktop environment already installed (skipping)"
fi

# Enable login manager if selected
if ! step_completed "login_manager" && [[ -n "$LOGIN_MANAGER" ]]; then
    print_status "Enabling login manager: $LOGIN_MANAGER"
    systemctl enable $(echo $LOGIN_MANAGER | cut -d' ' -f1)
    print_success "Login manager enabled"
    mark_step_completed "login_manager"
elif [[ -n "$LOGIN_MANAGER" ]]; then
    print_status "Login manager already enabled (skipping)"
fi

# Install additional packages
if ! step_completed "additional_packages"; then
    print_status "Installing additional packages..."
    pacman -Sy --noconfirm git wget curl firefox
    mark_step_completed "additional_packages"
else
    print_status "Additional packages already installed (skipping)"
fi

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
    <action name="Execute"><command>librewolf</command></action>
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
    # Hyprland configuration
    mkdir -p /home/$username/.config/hypr
    cat > /home/$username/.config/hypr/hyprland.conf << 'HYPREOF'
# Monitor configuration
monitor=,preferred,auto,auto

# Environment variables
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_QPA_PLATFORM,wayland;xcb
env = GDK_BACKEND,wayland,x11
env = SDL_VIDEODRIVER,wayland
env = CLUTTER_BACKEND,wayland
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland

# Execute at launch
exec-once = waybar
exec-once = hyprpaper
exec-once = /usr/lib/polkit-kde-authentication-agent-1
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

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
    col.active_border = rgba(74c7ecff) rgba(89b4faff) 45deg
    col.inactive_border = rgba(585b70aa)
    layout = dwindle
    allow_tearing = false
}

# Decoration
decoration {
    rounding = 10
    
    blur {
        enabled = true
        size = 3
        passes = 1
        
        vibrancy = 0.1696
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

# Layout
dwindle {
    pseudotile = yes
    preserve_split = yes
}

master {
    new_is_master = true
}

# Gestures
gestures {
    workspace_swipe = off
}

# Misc
misc {
    force_default_wallpaper = -1
}

# Window rules
windowrulev2 = suppress_events_fullscreen, class:.*

# Key bindings
$mainMod = SUPER

# Application bindings
bind = $mainMod, T, exec, kitty
bind = $mainMod, Q, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, thunar
bind = $mainMod, V, togglefloating,
bind = $mainMod, D, exec, wofi --show drun
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,
bind = $mainMod, F, fullscreen,

# Move focus with mainMod + arrow keys
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Move focus with mainMod + hjkl
bind = $mainMod, h, movefocus, l
bind = $mainMod, l, movefocus, r
bind = $mainMod, k, movefocus, u
bind = $mainMod, j, movefocus, d

# Switch workspaces with mainMod + [0-9]
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move active window to a workspace with mainMod + SHIFT + [0-9]
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# Example special workspace (scratchpad)
bind = $mainMod, S, togglespecialworkspace, magic
bind = $mainMod SHIFT, S, movetoworkspace, special:magic

# Scroll through existing workspaces with mainMod + scroll
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Move/resize windows with mainMod + LMB/RMB and dragging
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Volume and brightness controls
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ +5%
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ -5%
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86AudioPlay, exec, playerctl play-pause
bind = , XF86AudioPause, exec, playerctl play-pause
bind = , XF86AudioNext, exec, playerctl next
bind = , XF86AudioPrev, exec, playerctl previous
HYPREOF

    chown -R $username:$username /home/$username/.config
    print_success "Hyprland configured"
fi

# Configure themes for desktop environments
if ! step_completed "theme_config"; then
    print_status "Configuring Catppuccin themes..."
    
    # Configure GTK themes
    mkdir -p /home/$username/.config/gtk-3.0
    mkdir -p /home/$username/.config/gtk-4.0
    
    # Determine theme names based on what's available
    gtk_theme_name="Catppuccin-Mocha-Standard-Sapphire-Dark"
    icon_theme_name="Tela-dark"
    cursor_theme_name="Vimix-white-cursors"
    
    # Check for alternative theme names if manual installation was used
    if [[ -d "/home/$username/.local/share/themes" ]]; then
        # Find available Catppuccin theme
        available_gtk_theme=$(find "/home/$username/.local/share/themes" -maxdepth 1 -name "*Catppuccin*Mocha*" -type d | head -1 | xargs basename 2>/dev/null)
        if [[ -n "$available_gtk_theme" ]]; then
            gtk_theme_name="$available_gtk_theme"
        fi
    fi
    
    if [[ -d "/home/$username/.local/share/icons" ]]; then
        # Check for Tela or fallback icon themes
        if [[ -d "/home/$username/.local/share/icons/Tela-dark" ]]; then
            icon_theme_name="Tela-dark"
        elif [[ -d "/home/$username/.local/share/icons/Papirus-Dark" ]]; then
            icon_theme_name="Papirus-Dark"
        elif [[ -d "/usr/share/icons/Papirus-Dark" ]]; then
            icon_theme_name="Papirus-Dark"
        fi
        
        # Check for Vimix cursor
        if [[ -d "/home/$username/.local/share/icons/Vimix-white-cursors" ]]; then
            cursor_theme_name="Vimix-white-cursors"
        elif [[ -d "/home/$username/.local/share/icons/Vimix-cursors" ]]; then
            cursor_theme_name="Vimix-cursors"
        fi
    fi
    
    print_status "Using themes: GTK=$gtk_theme_name, Icons=$icon_theme_name, Cursor=$cursor_theme_name"
    
    # GTK 3 configuration
    cat > /home/$username/.config/gtk-3.0/settings.ini << GTKEOF
[Settings]
gtk-theme-name=$gtk_theme_name
gtk-icon-theme-name=$icon_theme_name
gtk-font-name=Cantarell 11
gtk-cursor-theme-name=$cursor_theme_name
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
GTKEOF
    
    # GTK 4 configuration
    cat > /home/$username/.config/gtk-4.0/settings.ini << GTK4EOF
[Settings]
gtk-theme-name=$gtk_theme_name
gtk-icon-theme-name=$icon_theme_name
gtk-font-name=Cantarell 11
gtk-cursor-theme-name=$cursor_theme_name
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
GTK4EOF
    
    # Qt configuration for KDE/SDDM environments
    if [[ "$de_choice" == "2" ]] || [[ "$de_choice" == "5" ]] || [[ "$de_choice" == "6" ]]; then
        mkdir -p /home/$username/.config
        # Use authentic Catppuccin color scheme if available, otherwise use basic config
        catppuccin_color_scheme="CatppuccinMochaSapphire"
        
        # Check if Catppuccin color schemes were installed
        if [[ -f "/home/$username/.local/share/color-schemes/CatppuccinMochaSapphire.colors" ]]; then
            catppuccin_color_scheme="CatppuccinMochaSapphire"
        elif [[ -f "/home/$username/.local/share/color-schemes/CatppuccinMocha.colors" ]]; then
            catppuccin_color_scheme="CatppuccinMocha"
        else
            # Find any Catppuccin Mocha color scheme
            available_scheme=$(find "/home/$username/.local/share/color-schemes" -name "*Catppuccin*Mocha*.colors" | head -1 | xargs basename -s .colors 2>/dev/null)
            if [[ -n "$available_scheme" ]]; then
                catppuccin_color_scheme="$available_scheme"
            fi
        fi
        
        print_status "Using color scheme: $catppuccin_color_scheme"
        
        cat > /home/$username/.config/kdeglobals << KDEEOF
[ColorScheme]
ColorScheme=$catppuccin_color_scheme

[General]
ColorScheme=$catppuccin_color_scheme
Name=Catppuccin Mocha
fixed=Fira Code,10,-1,5,50,0,0,0,0,0
font=Noto Sans,10,-1,5,50,0,0,0,0,0
menuFont=Noto Sans,10,-1,5,50,0,0,0,0,0
smallestReadableFont=Noto Sans,8,-1,5,50,0,0,0,0,0
toolBarFont=Noto Sans,10,-1,5,50,0,0,0,0,0

[Icons]
Theme=$icon_theme_name

[KDE]
lookAndFeelPackage=Catppuccin-Mocha-Sapphire

KDEEOF
        
        # Set the color scheme and look-and-feel in KDE config
        mkdir -p "/home/$username/.config/plasma-org.kde.plasma.desktop-appletsrc.d"
        
        # Create kdeglobals color scheme reference
        if [[ -f "/home/$username/.local/share/color-schemes/$catppuccin_color_scheme.colors" ]]; then
            cat > "/home/$username/.config/kcmcolorsrc" << COLOREOF
[Theme]
ColorScheme=$catppuccin_color_scheme
COLOREOF
        fi
    fi
    
    # Set wallpaper based on desktop environment
    crane_wallpaper=$(get_state_value "crane_wallpaper")
    if [[ -n "$crane_wallpaper" && -f "$crane_wallpaper" ]]; then
        case $de_choice in
            1) # GNOME
                sudo -u $username gsettings set org.gnome.desktop.background picture-uri "file://$crane_wallpaper" 2>/dev/null || true
                sudo -u $username gsettings set org.gnome.desktop.background picture-uri-dark "file://$crane_wallpaper" 2>/dev/null || true
                ;;
            3) # XFCE
                # XFCE wallpaper will be set via autostart script
                mkdir -p /home/$username/.config/autostart
                cat > /home/$username/.config/autostart/wallpaper.desktop << XFCEEOF
[Desktop Entry]
Type=Application
Name=Set Wallpaper
Exec=feh --bg-scale "$crane_wallpaper"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
XFCEEOF
                ;;
            4) # OpenBox
                # Update OpenBox autostart to use crane wallpaper
                sed -i "s|feh --bg-scale.*|feh --bg-scale \"$crane_wallpaper\" \&|" /home/$username/.config/openbox/autostart
                ;;
            6) # Hyprland
                # Update Hyprland config for wallpaper
                mkdir -p /home/$username/.config/hypr
                
                # Create hyprpaper config
                cat > /home/$username/.config/hypr/hyprpaper.conf << HYPRPAPEREOF
preload = $crane_wallpaper
wallpaper = ,$crane_wallpaper
splash = false
ipc = on
HYPRPAPEREOF
                
                # Add wallpaper to Hyprland config if not already present
                if ! grep -q "exec-once = hyprpaper" /home/$username/.config/hypr/hyprland.conf; then
                    echo "exec-once = hyprpaper" >> /home/$username/.config/hypr/hyprland.conf
                fi
                ;;
        esac
    fi
    
    # Set cursor theme system-wide
    mkdir -p /home/$username/.icons/default
    cat > /home/$username/.icons/default/index.theme << CURSOREOF
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=$cursor_theme_name
CURSOREOF
    
    # Ensure proper ownership
    chown -R $username:$username /home/$username/.config
    chown -R $username:$username /home/$username/.icons
    # Wallpapers are handled in their own download section
    
    print_success "Catppuccin themes configured"
    mark_step_completed "theme_config"
else
    print_status "Themes already configured (skipping)"
fi

# Fix home directory permissions for desktop environment compatibility
if ! step_completed "home_permissions"; then
    print_status "Setting proper home directory permissions for desktop environments..."
    
    # Ensure home directory has correct ownership and permissions
    chown -R $username:$username "/home/$username"
    chmod 755 "/home/$username"
    
    # Fix common permission issues with desktop directories
    desktop_dirs=(".config" ".local" ".cache" "Desktop" "Documents" "Downloads" "Pictures" "Videos" "Music")
    
    for dir in "${desktop_dirs[@]}"; do
        if [[ -d "/home/$username/$dir" ]]; then
            chown -R $username:$username "/home/$username/$dir"
            chmod -R 755 "/home/$username/$dir"
        fi
    done
    
    # Create missing desktop directories with proper permissions
    sudo -u $username mkdir -p "/home/$username/Desktop" "/home/$username/Documents" "/home/$username/Downloads" "/home/$username/Pictures" "/home/$username/Videos" "/home/$username/Music"
    
    # Ensure XDG directories are properly configured
    sudo -u $username mkdir -p "/home/$username/.config" "/home/$username/.local/share" "/home/$username/.cache"
    
    print_success "Home directory permissions configured for desktop environment compatibility"
    mark_step_completed "home_permissions"
else
    print_status "Home directory permissions already configured (skipping)"
fi

# Install AUR helper if requested
if [[ "$INSTALL_YAY" == true ]] && ! step_completed "yay_install"; then
    print_status "Setting up AUR helper..."
    
    # Switch to user for AUR operations
    if sudo -u $username bash << 'USEREOF'
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
    then
        print_success "AUR helper installation completed"
        mark_step_completed "yay_install"
    else
        print_error "AUR helper installation failed - you can install it manually later"
        print_status "To install yay manually:"
        echo "  sudo -u $username git clone https://aur.archlinux.org/yay.git /home/$username/yay"
        echo "  cd /home/$username/yay && sudo -u $username makepkg -si"
    fi
elif [[ "$INSTALL_YAY" == true ]]; then
    print_status "yay AUR helper already installed (skipping)"
else
    print_status "Skipping AUR helper installation"
fi

# Install LibreWolf from AUR if yay is available and installed
if ! step_completed "librewolf_install"; then
    if command -v yay >/dev/null 2>&1; then
        print_status "Installing LibreWolf from AUR..."
        if sudo -u $username yay -S --noconfirm librewolf-bin; then
            print_success "LibreWolf installed successfully"
            mark_step_completed "librewolf_install"
        else
            print_error "LibreWolf installation failed"
            print_status "You can install it manually later with: yay -S librewolf-bin"
        fi
    else
        print_warning "yay not available - skipping LibreWolf installation"
        print_status "Install yay first, then run: yay -S librewolf-bin"
    fi
else
    print_status "LibreWolf already installed (skipping)"
fi

# Install themes and assets from unified repository
if ! step_completed "theme_install"; then
    print_status "Installing themes and assets from unified repository..."
    
    # Clone the unified repository
    repo_dir="/tmp/arch-install-assets"
    if sudo -u $username git clone https://github.com/Arialo/Arch-install-script-2.git "$repo_dir"; then
        print_success "Repository cloned successfully"
        
        # Create theme directories
        themes_dir="/home/$username/.local/share/themes"
        icons_dir="/home/$username/.local/share/icons"
        color_schemes_dir="/home/$username/.local/share/color-schemes"
        mkdir -p "$themes_dir" "$icons_dir" "$color_schemes_dir"
        
        # Ensure .local directory exists and has proper ownership
        mkdir -p "/home/$username/.local/share"
        chown -R $username:$username "/home/$username/.local"
        
        # Install Catppuccin GTK theme
        print_status "Installing Catppuccin GTK theme..."
        if [[ -f "$repo_dir/Catppuccin-gtk-main.zip" ]]; then
            cd "/tmp"
            sudo -u $username unzip -q "$repo_dir/Catppuccin-gtk-main.zip"
            if [[ -d "/tmp/Catppuccin-gtk-main/themes" ]]; then
                sudo -u $username cp -r /tmp/Catppuccin-gtk-main/themes/* "$themes_dir/" 2>/dev/null || true
                sudo -u $username rm -rf "/tmp/Catppuccin-gtk-main"
                print_success "Catppuccin GTK theme installed from repository"
            fi
        else
            print_warning "Catppuccin GTK theme not found in repository"
        fi
        
        # Install Vimix cursor theme
        print_status "Installing Vimix cursor theme..."
        if [[ -f "$repo_dir/Vimix-cursors-master.zip" ]]; then
            cd "/tmp"
            sudo -u $username unzip -q "$repo_dir/Vimix-cursors-master.zip"
            if [[ -d "/tmp/Vimix-cursors-master" ]]; then
                cd "/tmp/Vimix-cursors-master"
                sudo -u $username ./install.sh -d "$icons_dir" 2>/dev/null || {
                    # Manual installation if script fails
                    sudo -u $username cp -r dist/* "$icons_dir/" 2>/dev/null || true
                }
                sudo -u $username rm -rf "/tmp/Vimix-cursors-master"
                print_success "Vimix cursor theme installed from repository"
            fi
        else
            print_warning "Vimix cursor theme not found in repository"
        fi
        
        # Install Azure Glassy Dark icons
        print_status "Installing Azure Glassy Dark icons..."
        if [[ -f "$repo_dir/Azure-Glassy-Dark-icons.tar.gz" ]]; then
            cd "$icons_dir"
            sudo -u $username tar -xzf "$repo_dir/Azure-Glassy-Dark-icons.tar.gz" 2>/dev/null || true
            print_success "Azure Glassy Dark icons installed from repository"
        else
            print_warning "Azure Glassy Dark icons not found in repository"
        fi
        
        # Install color schemes
        print_status "Installing Catppuccin color schemes..."
        if [[ -d "$repo_dir/colors" ]]; then
            sudo -u $username cp -r "$repo_dir/colors"/* "$color_schemes_dir/" 2>/dev/null || true
            print_success "Catppuccin color schemes installed from repository"
        else
            print_warning "Color schemes not found in repository"
        fi
        
        # Set proper ownership and permissions for all user files
        print_status "Setting proper ownership and permissions..."
        
        # Fix ownership of all theme directories
        chown -R $username:$username "$themes_dir" "$icons_dir" "$color_schemes_dir"
        
        # Fix home directory permissions for KDE/SDDM compatibility
        chown -R $username:$username "/home/$username"
        chmod 755 "/home/$username"  # Home directory needs to be readable
        
        # Ensure .local and subdirectories have proper permissions
        chmod -R 755 "/home/$username/.local"
        
        # Ensure .config directory exists and has proper permissions
        mkdir -p "/home/$username/.config"
        chown -R $username:$username "/home/$username/.config"
        chmod -R 755 "/home/$username/.config"
        
        # Set specific permissions for theme directories
        find "$themes_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$themes_dir" -type f -exec chmod 644 {} \; 2>/dev/null || true
        find "$icons_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$icons_dir" -type f -exec chmod 644 {} \; 2>/dev/null || true
        find "$color_schemes_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$color_schemes_dir" -type f -exec chmod 644 {} \; 2>/dev/null || true
        
        print_success "Ownership and permissions set correctly for KDE compatibility"
        
        # Cleanup
        sudo -u $username rm -rf "$repo_dir"
        
        print_success "All themes and assets installed from unified repository"
        mark_step_completed "theme_install"
    else
        print_error "Failed to clone unified repository"
        print_status "Falling back to yay installation..."
        
        # Fallback to yay if repository fails
        if command -v yay >/dev/null 2>&1; then
            if sudo -u $username yay -S --noconfirm catppuccin-gtk-theme-mocha vimix-cursor-theme papirus-icon-theme; then
                print_success "Fallback theme installation completed via yay"
                mark_step_completed "theme_install"
            else
                print_warning "Both repository and yay installation failed"
            fi
        else
            print_warning "Repository failed and yay not available - themes may be missing"
        fi
    fi
else
    print_status "Themes already installed (skipping)"
fi

# Download wallpaper from unified repository
if ! step_completed "wallpaper_download"; then
    print_status "Setting up wallpaper from unified repository..."
    
    # Create custom wallpaper directory structure
    wallpaper_dir="/home/$username/.local/share/wallpapers"
    mkdir -p "$wallpaper_dir"
    chown -R $username:$username "/home/$username/.local"
    
    # Clone repository temporarily to get wallpaper
    repo_dir="/tmp/arch-install-wallpaper"
    if sudo -u $username git clone https://github.com/Arialo/Arch-install-script-2.git "$repo_dir"; then
        print_success "Repository cloned for wallpaper"
        
        # Copy crane wallpaper from repository
        if [[ -f "$repo_dir/crane.png" ]]; then
            sudo -u $username cp "$repo_dir/crane.png" "$wallpaper_dir/"
            crane_wallpaper="$wallpaper_dir/crane.png"
            echo "crane_wallpaper=$crane_wallpaper" >> "$POST_STATE_FILE"
            print_success "Crane wallpaper installed from repository: $crane_wallpaper"
        else
            print_warning "Crane wallpaper not found in repository"
        fi
        
        # Cleanup
        sudo -u $username rm -rf "$repo_dir"
        
        # Ensure proper ownership
        chown -R $username:$username "$wallpaper_dir"
        mark_step_completed "wallpaper_download"
    else
        print_error "Failed to clone repository for wallpaper"
        print_status "Wallpaper will not be set"
    fi
else
    print_status "Wallpapers already downloaded (skipping)"
fi

# Final system update
if ! step_completed "final_update"; then
    print_status "Performing final system update..."
    pacman -Syu --noconfirm
    mark_step_completed "final_update"
else
    print_status "System already updated (skipping)"
fi

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
echo "- LibreWolf and other packages should now be available"
echo "- Login managers will start on next boot"
echo "- Configuration files have been created for window managers"