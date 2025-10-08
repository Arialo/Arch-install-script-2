#!/bin/bash

# Arch Linux Theme Setup Script
# Run this script after first login to install themes when directories exist

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

# Check if running as user (not root)
if [[ $EUID -eq 0 ]]; then
   print_error "This script should NOT be run as root. Run as your user account."
   exit 1
fi

# State file for tracking completion
THEME_STATE_FILE="$HOME/.config/arch-theme-setup-completed"

# Check if already completed
if [[ -f "$THEME_STATE_FILE" ]]; then
    print_status "Theme setup already completed. Remove $THEME_STATE_FILE to run again."
    exit 0
fi

print_status "Arch Linux Theme Setup - Post-Login Theme Installation"
echo "This will install themes now that desktop environment directories exist."
echo ""

# Detect current desktop environment
if [[ "$XDG_CURRENT_DESKTOP" == "KDE" ]]; then
    DE_TYPE="kde"
    print_status "Detected: KDE Plasma"
elif [[ "$XDG_CURRENT_DESKTOP" == "GNOME" ]]; then
    DE_TYPE="gnome"
    print_status "Detected: GNOME"
elif [[ "$XDG_CURRENT_DESKTOP" == "XFCE" ]]; then
    DE_TYPE="xfce"
    print_status "Detected: XFCE"
elif [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]]; then
    DE_TYPE="hyprland"
    print_status "Detected: Hyprland"
else
    DE_TYPE="generic"
    print_status "Detected: Generic/Unknown desktop environment"
fi

# Use system repository copy if available, otherwise try local copy, otherwise clone from GitHub
if [[ -d "/opt/arch-install-assets" ]]; then
    print_status "Using system repository copy..."
    repo_dir="/opt/arch-install-assets"
    cleanup_repo=false  # Don't delete the permanent system copy
    print_success "Using system repository copy"
elif [[ -d "$HOME/arch-install-assets" ]]; then
    print_status "Using local repository copy..."
    repo_dir="$HOME/arch-install-assets"
    cleanup_repo=false  # Don't delete the permanent local copy
    print_success "Using local repository copy"
else
    print_status "Downloading themes and assets from GitHub..."
    repo_dir="$HOME/.cache/arch-theme-setup"
    rm -rf "$repo_dir"  # Clean any previous downloads
    cleanup_repo=true   # Clean up the temporary download
    
    if git clone https://github.com/Arialo/Arch-install-script-2.git "$repo_dir"; then
        print_success "Repository cloned successfully"
    else
        print_error "Failed to clone repository"
        exit 1
    fi
fi

# Create theme directories (they should exist now after first login)
themes_dir="$HOME/.local/share/themes"
icons_dir="$HOME/.local/share/icons"
color_schemes_dir="$HOME/.local/share/color-schemes"

mkdir -p "$themes_dir" "$icons_dir" "$color_schemes_dir"
print_status "Theme directories created/verified"

# Install Catppuccin GTK theme
print_status "Installing Catppuccin GTK theme..."
if [[ -f "$repo_dir/Catppuccin-gtk-main.zip" ]]; then
    cd "$HOME/.cache"
    unzip -q "$repo_dir/Catppuccin-gtk-main.zip"
    if [[ -d "$HOME/.cache/Catppuccin-gtk-main/themes" ]]; then
        cp -r "$HOME/.cache/Catppuccin-gtk-main/themes"/* "$themes_dir/" 2>/dev/null || true
        rm -rf "$HOME/.cache/Catppuccin-gtk-main"
        print_success "Catppuccin GTK theme installed"
        
        # Set GTK theme
        if command -v gsettings >/dev/null 2>&1; then
            # Find available Catppuccin theme
            available_theme=$(find "$themes_dir" -maxdepth 1 -name "*Catppuccin*Mocha*Sapphire*" -type d | head -1 | xargs basename 2>/dev/null)
            if [[ -n "$available_theme" ]]; then
                gsettings set org.gnome.desktop.interface gtk-theme "$available_theme" 2>/dev/null || true
                print_success "GTK theme applied: $available_theme"
            fi
        fi
    fi
else
    print_warning "Catppuccin GTK theme not found in repository"
fi

# Install Vimix cursor theme
print_status "Installing Vimix cursor theme..."
if [[ -f "$repo_dir/Vimix-cursors-master.zip" ]]; then
    cd "$HOME/.cache"
    unzip -q "$repo_dir/Vimix-cursors-master.zip"
    if [[ -d "$HOME/.cache/Vimix-cursors-master" ]]; then
        cd "$HOME/.cache/Vimix-cursors-master"
        ./install.sh -d "$icons_dir" 2>/dev/null || {
            # Manual installation if script fails
            cp -r dist/* "$icons_dir/" 2>/dev/null || true
        }
        rm -rf "$HOME/.cache/Vimix-cursors-master"
        print_success "Vimix cursor theme installed"
        
        # Set cursor theme
        if command -v gsettings >/dev/null 2>&1; then
            gsettings set org.gnome.desktop.interface cursor-theme 'Vimix-white-cursors' 2>/dev/null || true
        fi
    fi
else
    print_warning "Vimix cursor theme not found in repository"
fi

# Install Azure Glassy Dark icons
print_status "Installing Azure Glassy Dark icons..."
if [[ -f "$repo_dir/Azure-Glassy-Dark-icons.tar.gz" ]]; then
    cd "$icons_dir"
    tar -xzf "$repo_dir/Azure-Glassy-Dark-icons.tar.gz" 2>/dev/null || true
    print_success "Azure Glassy Dark icons installed"
    
    # Set icon theme
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface icon-theme 'Azure-Glassy-Dark' 2>/dev/null || true
    fi
else
    print_warning "Azure Glassy Dark icons not found in repository"
fi

# Install color schemes for KDE
if [[ "$DE_TYPE" == "kde" ]] || [[ "$DE_TYPE" == "hyprland" ]]; then
    print_status "Installing Catppuccin color schemes..."
    if [[ -d "$repo_dir/colors" ]]; then
        cp -r "$repo_dir/colors"/* "$color_schemes_dir/" 2>/dev/null || true
        print_success "Catppuccin color schemes installed"
        
        # Apply KDE color scheme
        if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
            # Try to apply Catppuccin color scheme
            if [[ -f "$color_schemes_dir/CatppuccinMochaSapphire.colors" ]]; then
                plasma-apply-colorscheme CatppuccinMochaSapphire 2>/dev/null || true
                print_success "Catppuccin Mocha Sapphire color scheme applied"
            fi
        fi
    else
        print_warning "Color schemes not found in repository"
    fi
fi

# Set wallpaper if available
print_status "Setting up wallpaper..."
if [[ -f "$repo_dir/crane.png" ]]; then
    wallpaper_dir="$HOME/.local/share/wallpapers"
    mkdir -p "$wallpaper_dir"
    cp "$repo_dir/crane.png" "$wallpaper_dir/"
    crane_wallpaper="$wallpaper_dir/crane.png"
    
    # Set wallpaper based on desktop environment
    case "$DE_TYPE" in
        gnome)
            if command -v gsettings >/dev/null 2>&1; then
                gsettings set org.gnome.desktop.background picture-uri "file://$crane_wallpaper" 2>/dev/null || true
                gsettings set org.gnome.desktop.background picture-uri-dark "file://$crane_wallpaper" 2>/dev/null || true
                print_success "Wallpaper set for GNOME"
            fi
            ;;
        kde)
            # KDE wallpaper setting (requires additional setup)
            print_status "Wallpaper copied for KDE - set manually in System Settings"
            ;;
        xfce)
            if command -v xfconf-query >/dev/null 2>&1; then
                xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "$crane_wallpaper" 2>/dev/null || true
                print_success "Wallpaper set for XFCE"
            fi
            ;;
        hyprland)
            # Hyprland wallpaper via hyprpaper config
            if [[ -f "$HOME/.config/hypr/hyprpaper.conf" ]]; then
                sed -i "s|preload = .*|preload = $crane_wallpaper|" "$HOME/.config/hypr/hyprpaper.conf"
                sed -i "s|wallpaper = .*|wallpaper = ,$crane_wallpaper|" "$HOME/.config/hypr/hyprpaper.conf"
                print_success "Wallpaper configured for Hyprland"
            fi
            ;;
    esac
else
    print_warning "Crane wallpaper not found in repository"
fi

# Create theme configuration files
print_status "Creating theme configuration files..."

# GTK theme configuration
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

# Find installed theme name
gtk_theme_name="Catppuccin-Mocha-Standard-Sapphire-Dark"
if [[ -d "$themes_dir" ]]; then
    available_gtk_theme=$(find "$themes_dir" -maxdepth 1 -name "*Catppuccin*Mocha*" -type d | head -1 | xargs basename 2>/dev/null)
    if [[ -n "$available_gtk_theme" ]]; then
        gtk_theme_name="$available_gtk_theme"
    fi
fi

# Find installed icon theme name
icon_theme_name="Azure-Glassy-Dark"
if [[ -d "$icons_dir/Papirus-Dark" ]]; then
    icon_theme_name="Papirus-Dark"
elif [[ -d "$icons_dir/Tela-dark" ]]; then
    icon_theme_name="Tela-dark"
fi

# GTK 3 configuration
cat > "$HOME/.config/gtk-3.0/settings.ini" << EOF
[Settings]
gtk-theme-name=$gtk_theme_name
gtk-icon-theme-name=$icon_theme_name
gtk-font-name=Cantarell 11
gtk-cursor-theme-name=Vimix-white-cursors
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF

# GTK 4 configuration
cat > "$HOME/.config/gtk-4.0/settings.ini" << EOF
[Settings]
gtk-theme-name=$gtk_theme_name
gtk-icon-theme-name=$icon_theme_name
gtk-font-name=Cantarell 11
gtk-cursor-theme-name=Vimix-white-cursors
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF

print_success "Theme configuration files created"

# Cleanup (only if we downloaded a temporary copy)
if [[ "$cleanup_repo" == true ]]; then
    rm -rf "$repo_dir"
fi

# Mark as completed
touch "$THEME_STATE_FILE"

print_success "Theme setup completed successfully!"
print_status "Themes installed and configured:"
echo "  - GTK Theme: $gtk_theme_name"
echo "  - Icon Theme: $icon_theme_name"
echo "  - Cursor Theme: Vimix-white-cursors"
echo "  - Wallpaper: crane.png (if supported by DE)"
echo ""
print_status "You may need to:"
echo "  1. Log out and back in to see all changes"
echo "  2. Restart your desktop environment"  
echo "  3. Manually set wallpaper in some desktop environments"
echo ""
print_warning "This script has been marked as completed."
print_warning "Remove $THEME_STATE_FILE to run it again."