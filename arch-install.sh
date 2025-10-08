#!/bin/bash

# Arch Linux Automated Installation Script
# This script provides a customized and mostly automated Arch installation

set -e  # Exit on any error

# State file for tracking installation progress
STATE_FILE="/tmp/arch-install-state"

# Function to check if a step is completed
step_completed() {
    grep -q "^$1=completed$" "$STATE_FILE" 2>/dev/null
}

# Function to mark a step as completed
mark_step_completed() {
    echo "$1=completed" >> "$STATE_FILE"
}

# Function to get state value
get_state_value() {
    grep "^$1=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2
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

# Check if we're in a live environment
if ! grep -q "archiso" /proc/cmdline 2>/dev/null; then
    print_warning "This script is designed to run from an Arch Linux live environment"
    read -p "Continue anyway? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Update system clock
if ! step_completed "clock_sync"; then
    print_status "Updating system clock..."
    timedatectl set-ntp true
    mark_step_completed "clock_sync"
else
    print_status "System clock already synced (skipping)"
fi

# Drive selection
if ! step_completed "drive_selection"; then
    # Display available drives
    print_status "Available drives:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    
    echo ""
    read -p "Enter the drive to install to (e.g., sda, nvme0n1): " DRIVE
    
    # Validate drive exists
    if [[ ! -b "/dev/$DRIVE" ]]; then
        print_error "Drive /dev/$DRIVE does not exist!"
        exit 1
    fi
    
    print_warning "This will COMPLETELY WIPE /dev/$DRIVE"
    read -p "Are you sure you want to continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled"
        exit 0
    fi
    
    echo "DRIVE=$DRIVE" >> "$STATE_FILE"
    mark_step_completed "drive_selection"
else
    DRIVE=$(get_state_value "DRIVE")
    print_status "Using previously selected drive: /dev/$DRIVE (skipping selection)"
fi

# Get partition sizes
if ! step_completed "partition_config"; then
    echo ""
    print_status "Configure partition sizes:"
    echo "Recommended sizes:"
    echo "- EFI: 512M"
    echo "- Root: 30G-50G"
    echo "- Swap: 2G-8G (or equal to RAM for hibernation)"
    echo "- Home: Remaining space"
    echo ""
    
    read -p "EFI partition size (e.g., 512M): " EFI_SIZE
    read -p "Root partition size (e.g., 40G): " ROOT_SIZE
    read -p "Swap partition size (e.g., 4G): " SWAP_SIZE
    read -p "Home partition size (enter 'rest' for remaining space or specific size like 100G): " HOME_SIZE
    
    echo "EFI_SIZE=$EFI_SIZE" >> "$STATE_FILE"
    echo "ROOT_SIZE=$ROOT_SIZE" >> "$STATE_FILE"
    echo "SWAP_SIZE=$SWAP_SIZE" >> "$STATE_FILE"
    echo "HOME_SIZE=$HOME_SIZE" >> "$STATE_FILE"
    mark_step_completed "partition_config"
else
    EFI_SIZE=$(get_state_value "EFI_SIZE")
    ROOT_SIZE=$(get_state_value "ROOT_SIZE")
    SWAP_SIZE=$(get_state_value "SWAP_SIZE")
    HOME_SIZE=$(get_state_value "HOME_SIZE")
    print_status "Using previous partition configuration (skipping)"
fi

# Determine partition naming scheme
if [[ "$DRIVE" =~ nvme ]]; then
    PART_PREFIX="${DRIVE}p"
else
    PART_PREFIX="$DRIVE"
fi

EFI_PART="/dev/${PART_PREFIX}1"
ROOT_PART="/dev/${PART_PREFIX}2"
SWAP_PART="/dev/${PART_PREFIX}3"
HOME_PART="/dev/${PART_PREFIX}4"

# Create partition table and partitions
if ! step_completed "partitioning"; then
    print_status "Creating partitions on /dev/$DRIVE..."
    
    # Clear the drive
    sgdisk --zap-all /dev/$DRIVE
    
    # Create GPT partition table
    sgdisk --clear \
           --new=1:0:+$EFI_SIZE --typecode=1:ef00 --change-name=1:'EFI System' \
           --new=2:0:+$ROOT_SIZE --typecode=2:8300 --change-name=2:'Linux Root' \
           --new=3:0:+$SWAP_SIZE --typecode=3:8200 --change-name=3:'Linux Swap' \
           /dev/$DRIVE
    
    # Create home partition
    if [[ "$HOME_SIZE" == "rest" ]]; then
        sgdisk --new=4:0:0 --typecode=4:8300 --change-name=4:'Linux Home' /dev/$DRIVE
    else
        sgdisk --new=4:0:+$HOME_SIZE --typecode=4:8300 --change-name=4:'Linux Home' /dev/$DRIVE
    fi
    
    # Inform kernel of partition changes
    partprobe /dev/$DRIVE
    sleep 2
    mark_step_completed "partitioning"
else
    print_status "Partitions already created (skipping)"
fi

# Format partitions
if ! step_completed "formatting"; then
    print_status "Formatting partitions..."
    mkfs.fat -F32 $EFI_PART
    mkfs.ext4 -F $ROOT_PART
    mkswap $SWAP_PART
    mkfs.ext4 -F $HOME_PART
    mark_step_completed "formatting"
else
    print_status "Partitions already formatted (skipping)"
fi

# Mount partitions
if ! step_completed "mounting"; then
    print_status "Mounting partitions..."
    mount $ROOT_PART /mnt
    mkdir -p /mnt/boot/efi
    mkdir -p /mnt/home
    mount $EFI_PART /mnt/boot/efi
    mount $HOME_PART /mnt/home/  # This mounts the home partition to /mnt/home (which becomes /home after chroot)
    swapon $SWAP_PART
    mark_step_completed "mounting"
else
    print_status "Partitions already mounted (skipping)"
fi

# Install base system
if ! step_completed "base_install"; then
    print_status "Installing base system..."
    pacstrap /mnt base linux linux-firmware base-devel grub efibootmgr networkmanager nano
    mark_step_completed "base_install"
else
    print_status "Base system already installed (skipping)"
fi

# Generate fstab
if ! step_completed "fstab"; then
    print_status "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    mark_step_completed "fstab"
else
    print_status "fstab already generated (skipping)"
fi

# Get user configuration
if ! step_completed "user_config"; then
    echo ""
    print_status "User Configuration:"
    while true; do
        read -s -p "Enter root password: " root_password
        echo ""
        read -s -p "Confirm root password: " root_password_confirm
        echo ""
        if [[ "$root_password" == "$root_password_confirm" ]]; then
            break
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
    
    read -p "Enter username for main user: " username
    while true; do
        read -s -p "Enter password for $username: " user_password
        echo ""
        read -s -p "Confirm password for $username: " user_password_confirm
        echo ""
        if [[ "$user_password" == "$user_password_confirm" ]]; then
            break
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
    
    echo "username=$username" >> "$STATE_FILE"
    # Note: passwords are not stored in state file for security
    mark_step_completed "user_config"
else
    username=$(get_state_value "username")
    print_status "Using previous user configuration: $username (passwords will be re-entered)"
    echo ""
    while true; do
        read -s -p "Enter root password: " root_password
        echo ""
        read -s -p "Confirm root password: " root_password_confirm
        echo ""
        if [[ "$root_password" == "$root_password_confirm" ]]; then
            break
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
    
    while true; do
        read -s -p "Enter password for $username: " user_password
        echo ""
        read -s -p "Confirm password for $username: " user_password_confirm
        echo ""
        if [[ "$user_password" == "$user_password_confirm" ]]; then
            break
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
fi


# Create chroot script
print_status "Creating configuration script..."
cat > /mnt/config_script.sh << EOF
#!/bin/bash

# Set timezone (default to UTC)
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname (default)
echo "archlinux" > /etc/hostname

# Configure hosts file
cat > /etc/hosts << EOL
127.0.0.1	localhost
::1		localhost
127.0.1.1	archlinux.localdomain	archlinux
EOL

# Set root password
echo "root:$root_password" | chpasswd

# Create user
useradd -m -G wheel,audio,video,optical,storage -s /bin/bash $username
echo "$username:$user_password" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

EOF

# Make script executable
chmod +x /mnt/config_script.sh

# Run configuration script in chroot
if ! step_completed "system_config"; then
    print_status "Configuring system..."
    arch-chroot /mnt /config_script.sh
    mark_step_completed "system_config"
else
    print_status "System already configured (skipping)"
fi

# Cleanup
rm /mnt/config_script.sh

# Copy installation scripts and assets to new system
print_status "Copying installation scripts and assets to new system..."

# Copy the entire git repository to preserve all assets
repo_source_dir="$(dirname "$0")"
repo_dest_dir="/mnt/home/$username/arch-install-assets"

# Create destination directory
mkdir -p "$repo_dest_dir"

# Copy all files from the repository
if cp -r "$repo_source_dir"/* "$repo_dest_dir/" 2>/dev/null; then
    # Make scripts executable
    chmod +x "$repo_dest_dir/arch-install.sh" 2>/dev/null || true
    chmod +x "$repo_dest_dir/arch-post-install.sh" 2>/dev/null || true
    chmod +x "$repo_dest_dir/arch-theme-setup.sh" 2>/dev/null || true
    
    # Set proper ownership
    chown -R $username:$username "$repo_dest_dir"
    
    # Create convenient symlinks in home directory
    ln -sf "$repo_dest_dir/arch-post-install.sh" "/mnt/home/$username/arch-post-install.sh" 2>/dev/null || true
    ln -sf "$repo_dest_dir/arch-theme-setup.sh" "/mnt/home/$username/arch-theme-setup.sh" 2>/dev/null || true
    
    print_success "Repository and scripts copied to /home/$username/arch-install-assets/"
    print_status "Convenient symlinks created in home directory"
else
    print_warning "Could not copy repository - scripts may not be available"
    
    # Fallback: try to copy just the essential scripts
    cp "$repo_source_dir/arch-post-install.sh" "/mnt/home/$username/" 2>/dev/null || true
    cp "$repo_source_dir/arch-theme-setup.sh" "/mnt/home/$username/" 2>/dev/null || true
    
    if [[ -f "/mnt/home/$username/arch-post-install.sh" ]]; then
        chmod +x "/mnt/home/$username/arch-post-install.sh"
        chown $username:$username "/mnt/home/$username/arch-post-install.sh"
    fi
    
    if [[ -f "/mnt/home/$username/arch-theme-setup.sh" ]]; then
        chmod +x "/mnt/home/$username/arch-theme-setup.sh"
        chown $username:$username "/mnt/home/$username/arch-theme-setup.sh"
    fi
fi

# Also copy to root of new system for chroot execution
cp "$(dirname "$0")/arch-post-install.sh" /mnt/arch-post-install.sh 2>/dev/null || {
    print_error "Could not copy post-install script for automatic execution"
    print_warning "You'll need to run the post-install script manually after rebooting"
    
    print_success "Base installation completed successfully!"
    print_status "System specifications:"
    echo "- Drive: /dev/$DRIVE"
    echo "- EFI: $EFI_SIZE"
    echo "- Root: $ROOT_SIZE"  
    echo "- Swap: $SWAP_SIZE"
    echo "- Home: $HOME_SIZE"
    echo "- Username: $username"
    
    print_status "Next steps:"
    echo "1. umount -R /mnt"
    echo "2. reboot"
    echo "3. Remove the installation media"
    echo "4. Boot into your new Arch Linux system"
    echo "5. Log in as root or $username"
    echo "6. Run: sudo ./arch-post-install.sh"
    echo ""
    print_warning "IMPORTANT:"
    echo "- The base system is installed but NO desktop environment yet"
    echo "- Run 'arch-post-install.sh' to configure desktop, timezone, hostname, etc."
    exit 0
}

chmod +x /mnt/arch-post-install.sh

print_success "Base installation completed successfully!"
print_status "System specifications:"
echo "- Drive: /dev/$DRIVE"
echo "- EFI: $EFI_SIZE"
echo "- Root: $ROOT_SIZE"  
echo "- Swap: $SWAP_SIZE"
echo "- Home: $HOME_SIZE"
echo "- Username: $username"
echo ""
print_status "Now running post-installation configuration..."
echo "This will configure desktop environment, timezone, hostname, etc."
echo ""

# Copy state file to new system for post-install script
cp "$STATE_FILE" /mnt/tmp/arch-install-state 2>/dev/null || true

# Run post-install script in chroot
if arch-chroot /mnt /arch-post-install.sh; then
    print_success "Complete installation finished successfully!"
    rm /mnt/arch-post-install.sh  # Cleanup
else
    print_error "Post-installation configuration failed!"
    print_warning "Don't worry - your base system is still intact"
    print_status "You can run the post-install script manually after rebooting:"
    echo "1. Boot into your new system"
    echo "2. Log in as root or $username"
    echo "3. Run: sudo ./arch-post-install.sh"
    rm /mnt/arch-post-install.sh  # Cleanup
fi

print_status "Final steps:"
echo "1. umount -R /mnt"
echo "2. reboot"
echo "3. Remove the installation media"
echo "4. Boot into your new Arch Linux system"
echo ""
print_warning "Note:"
echo "- If post-installation completed successfully, your system is ready to use"
echo "- If it failed, you can re-run ./arch-post-install.sh after booting"
echo "- The post-install script is available in your home directory for future use"
