#!/bin/bash

# Arch Linux Automated Installation Script
# This script provides a customized and mostly automated Arch installation

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

# Check if we're in a live environment
if ! grep -q "archiso" /proc/cmdline 2>/dev/null; then
    print_warning "This script is designed to run from an Arch Linux live environment"
    read -p "Continue anyway? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Update system clock
print_status "Updating system clock..."
timedatectl set-ntp true

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

# Get partition sizes
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

# Format partitions
print_status "Formatting partitions..."
mkfs.fat -F32 $EFI_PART
mkfs.ext4 -F $ROOT_PART
mkswap $SWAP_PART
mkfs.ext4 -F $HOME_PART

# Mount partitions
print_status "Mounting partitions..."
mount $ROOT_PART /mnt
mkdir -p /mnt/boot/efi
mkdir -p /mnt/home
mount $EFI_PART /mnt/boot/efi
mount $HOME_PART /mnt/home
swapon $SWAP_PART

# Install base system
print_status "Installing base system..."
pacstrap /mnt base linux linux-firmware base-devel grub efibootmgr networkmanager nano

# Generate fstab
print_status "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Get user configuration
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

# Desktop Environment Selection
echo ""
print_status "Desktop Environment Selection:"
echo "1) GNOME (with GDM)"
echo "2) KDE Plasma (with SDDM)"
echo "3) XFCE (with LightDM)"
echo "4) i3 (with LightDM)"
echo "5) Minimal (no desktop environment)"

read -p "Select desktop environment (1-5): " de_choice

case $de_choice in
    1)
        DE_PACKAGES="gnome gnome-extra"
        LOGIN_MANAGER="gdm"
        ;;
    2)
        DE_PACKAGES="plasma kde-applications"
        LOGIN_MANAGER="sddm"
        ;;
    3)
        DE_PACKAGES="xfce4 xfce4-goodies"
        LOGIN_MANAGER="lightdm lightdm-gtk-greeter"
        ;;
    4)
        DE_PACKAGES="i3-wm i3status i3lock dmenu xorg-server xorg-xinit"
        LOGIN_MANAGER="lightdm lightdm-gtk-greeter"
        ;;
    5)
        DE_PACKAGES=""
        LOGIN_MANAGER=""
        ;;
    *)
        print_error "Invalid selection. Defaulting to GNOME."
        DE_PACKAGES="gnome gnome-extra"
        LOGIN_MANAGER="gdm"
        ;;
esac

# Create chroot script
print_status "Creating configuration script..."
cat > /mnt/config_script.sh << EOF
#!/bin/bash

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
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

# Install desktop environment if selected
if [[ -n "$DE_PACKAGES" ]]; then
    pacman -Sy --noconfirm $DE_PACKAGES
fi

# Enable login manager if selected
if [[ -n "$LOGIN_MANAGER" ]]; then
    systemctl enable \$(echo $LOGIN_MANAGER | cut -d' ' -f1)
fi

# Install additional packages
pacman -Sy --noconfirm git wget curl firefox

EOF

# Make script executable
chmod +x /mnt/config_script.sh

# Run configuration script in chroot
print_status "Configuring system..."
arch-chroot /mnt /config_script.sh

# Install AUR helper and librewolf
print_status "Setting up AUR helper and installing librewolf..."
arch-chroot /mnt /bin/bash << EOF
# Switch to user for AUR operations
sudo -u $username bash << 'USEREOF'
cd /home/$username

# Install yay (AUR helper)
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay

# Install librewolf
yay -S --noconfirm librewolf-bin

USEREOF
EOF

# Cleanup
rm /mnt/config_script.sh

print_success "Installation completed successfully!"
print_status "System specifications:"
echo "- Drive: /dev/$DRIVE"
echo "- EFI: $EFI_SIZE"
echo "- Root: $ROOT_SIZE"  
echo "- Swap: $SWAP_SIZE"
echo "- Home: $HOME_SIZE"
echo "- Username: $username"
echo "- Desktop Environment: $de_choice"

print_status "Next steps:"
echo "1. umount -R /mnt"
echo "2. reboot"
echo "3. Remove the installation media"
echo "4. Boot into your new Arch Linux system"

print_warning "Don't forget to:"
echo "- Configure your timezone: sudo timedatectl set-timezone YOUR_TIMEZONE"
echo "- Update the system: sudo pacman -Syu"
echo "- Install additional software as needed"