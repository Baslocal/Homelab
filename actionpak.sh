#!/bin/bash
set -euo pipefail

# Version and URL variables
WAZUH_VERSION="4.8"
KASM_VERSION="1.15.0.06fdc8"
IVENTOY_VERSION="1.0.20"
IVENTOY_URL="https://github.com/ventoy/PXE/releases/download/v${IVENTOY_VERSION}/iventoy-${IVENTOY_VERSION}-linux-free.tar.gz"

# Function to check for root privileges
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to check for required tools
check_dependencies() {
    local deps=("curl" "wget" "sudo")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "$dep could not be found, installing..."
            apt-get update && apt-get install -y "$dep"
        fi
    done
}

# Function to display the menu
display_menu() {
    echo "Homelab -ActionPak- by Bas v1.3"
    echo "Select an option:"
    echo "1. Wazuh Installation Manager"
    echo "2. Nessus"
    echo "3. AntiVirus for Linux (ClamAV)"
    echo "4. Webmin"
    echo "5. Create a service account"
    echo "6. CaaSOS (Docker)"
    echo "7. Tailscale"
    echo "8. Kasm"
    echo "9. PXE network boot iVentoy"
    echo "10. Exit" 
}

# Updated function to install Wazuh
install_wazuh() {
    echo "Installing Wazuh..."
    curl -sO https://packages.wazuh.com/4.8/wazuh-install.sh && sudo bash ./wazuh-install.sh -a -i
    if [ $? -eq 0 ]; then
        echo "Wazuh installation completed successfully."
    else
        echo "Wazuh installation failed. Please check the log for more details."
    fi
    # Clean up
    rm -f wazuh-install.sh
}

# Function to install Nessus
install_nessus() {
    echo "Installing Nessus..."

    # Download Nessus
    curl --request GET \
         --url 'https://www.tenable.com/downloads/api/v2/pages/nessus/files/Nessus-10.8.2-ubuntu1604_amd64.deb' \
         --output 'Nessus-10.8.2-ubuntu1604_amd64.deb'

    # Install Nessus
    sudo dpkg -i Nessus-10.8.2-ubuntu1604_amd64.deb

    # Attempt to resolve dependencies if needed
    sudo apt-get update
    sudo apt-get -f install -y

    # Clean up
    rm Nessus-10.8.2-ubuntu1604_amd64.deb

    echo "Nessus installation completed."
    echo "You can access Nessus by navigating to https://localhost:8834 in your web browser."
    echo "Please follow the prompts to complete the setup process."
    
    echo "To complete the installation, a reboot is required."
    read -p "Would you like to reboot now? (y/n): " reboot_choice
    if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
        echo "Rebooting the system..."
        sudo reboot
    else
        echo "Please remember to reboot your system later to complete the Nessus installation."
        echo "Returning to the main menu..."
    fi
}

# Function to install ClamAV
install_clamav() {
    echo "Installing ClamAV..."
    apt-get update && apt-get install -y clamav clamav-daemon
    systemctl start clamav-daemon
    systemctl enable clamav-daemon
    echo "ClamAV installed and started."

    read -p "Do you want to set up a weekly ClamAV scan? (y/n): " setup_weekly_scan
    if [[ "$setup_weekly_scan" =~ ^[Yy]$ ]]; then
        sudo bash << EOF
# Create the script
cat << 'SCRIPT' > /usr/local/bin/weekly_clamscan.sh
#!/bin/bash

# Update virus definitions
freshclam

# Run a full system scan
clamscan -r / | grep FOUND >> /var/log/clamav/weekly_scan.log

# Optional: Remove infected files (use with caution)
# clamscan -r --remove /
SCRIPT

# Make the script executable
chmod +x /usr/local/bin/weekly_clamscan.sh

# Add the cron job to /etc/crontab instead of user's crontab
echo "0 2 * * 0 root /usr/local/bin/weekly_clamscan.sh" >> /etc/crontab

echo "Weekly ClamAV scan has been set up to run every Sunday at 2:00 AM."
EOF
    else
        echo "Weekly scan setup skipped."
    fi
}

# Function to install Webmin
install_webmin() {
    echo "Installing Webmin..."
    sudo apt install -y wget apt-transport-https software-properties-common
    echo "deb [arch=amd64] http://download.webmin.com/download/repository sarge contrib" | sudo tee /etc/apt/sources.list.d/webmin.list
    wget -q -O- http://www.webmin.com/jcameron-key.asc | sudo apt-key add -
    sudo apt update
    sudo apt install -y webmin
    if [ $? -eq 0 ]; then
        echo "Webmin installation completed successfully."
        echo "You can access Webmin at https://$(hostname -I | cut -d' ' -f1):10000/"
    else
        echo "Webmin installation failed. Please check the log for more details."
    fi
}

# Function to create a service account
create_service_account() {
    echo "Creating a service account..."
    read -p "Enter the username for the new service account: " username
    sudo useradd -m -s /bin/bash "$username"
    sudo passwd "$username"
    echo "Service account $username created."
}

# Function to install CaaSOS
install_caasos() {
    echo "Installing CaaSOS..."
    curl -fsSL https://get.casaos.io | sudo bash
    if [ $? -eq 0 ]; then
        echo "CaaSOS installation completed successfully."
    else
        echo "CaaSOS installation failed. Please check the log for more details."
    fi
}

# Function to install Tailscale
install_tailscale() {
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "Tailscale installed. Run 'sudo tailscale up' to connect to your network."
}

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    echo | sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker $USER
    if [ $? -eq 0 ]; then
        echo "Docker installation completed successfully."
        echo "You may need to log out and log back in for group changes to take effect."
    else
        echo "Docker installation failed. Please check the log for more details."
        return 1
    fi
}

# Function to install Kasm
install_kasm() {
    echo "Installing Kasm..."

    # Always install Docker first
    echo "Installing Docker first..."
    if ! install_docker; then
        echo "Docker installation failed. Aborting Kasm installation."
        return 1
    fi

    # Reload the user's group assignments to apply docker group without logging out
    exec sudo su -l $USER << EOF
    cd /tmp
    if [ ! -f kasm_release_1.15.0.06fdc8.tar.gz ]; then
        echo "Downloading Kasm..."
        curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_1.15.0.06fdc8.tar.gz
        if [ $? -ne 0 ]; then
            echo "Failed to download Kasm. Please check your internet connection and try again."
            exit 1
        fi
    fi

    if [ ! -d kasm_release ]; then
        echo "Extracting Kasm..."
        tar -xf kasm_release_1.15.0.06fdc8.tar.gz
        if [ $? -ne 0 ]; then
            echo "Failed to extract Kasm. Please check if the downloaded file is corrupted."
            exit 1
        fi
    fi

    echo "Running first Kasm installation..."
    sudo bash kasm_release/install.sh -e << EEOF
y
y
admin
password
password
EEOF

    echo "Running second Kasm installation..."
    sudo bash kasm_release/install.sh -e << EEOF
y
y
admin
password
password
EEOF

    if [ $? -eq 0 ]; then
        echo "Kasm installation completed successfully."
        echo "Now, let's set a new password for the admin user."
        
        # Prompt for new password
        read -s -p "Enter new password for admin user: " new_password
        echo
        read -s -p "Confirm new password: " confirm_password
        echo

        if [ "$new_password" = "$confirm_password" ]; then
            # Change the admin password
            if sudo /opt/kasm/bin/utils/kasm_user_mgr -m admin -p "$new_password"; then
                echo "Admin password has been successfully changed."
            else
                echo "Failed to change admin password. Please change it manually after logging in."
            fi
        else
            echo "Passwords do not match. Please change the admin password manually after logging in."
        fi

        echo "You can now access Kasm at https://$(hostname -I | cut -d' ' -f1):8443"
        echo "Login with username: admin and the password you just set."
    else
        echo "An error occurred during Kasm installation."
        echo "Please check the log file for more details: /tmp/kasm_install.log"
        echo "You can try running the installation manually with:"
        echo "cd /tmp/kasm_release && sudo bash install.sh"
    fi
EOF
}

# Function to install iVentoy
install_iventoy() {
    echo "Setting up iVentoy..."
    # Set variables
    local PACKAGE_NAME="iventoy-${IVENTOY_VERSION}-linux-free.tar.gz"
    local EXTRACTED_DIR="iventoy-${IVENTOY_VERSION}"
    local INSTALL_DIR="/opt/iventoy"
    local STARTUP_SCRIPT="/usr/local/bin/iventoy_startup.sh"
    local LOG_FILE="/var/log/iventoy_startup.log"
    local SERVICE_FILE="/etc/systemd/system/iventoy.service"

    # Check if iVentoy is already installed
    if [ -d "$INSTALL_DIR/$EXTRACTED_DIR" ]; then
        echo "iVentoy is already installed. Skipping installation."
        return
    fi

    # Create installation directory
    mkdir -p "$INSTALL_DIR"

    # Download iVentoy
    if ! wget -O "$INSTALL_DIR/$PACKAGE_NAME" "$IVENTOY_URL"; then
        echo "Failed to download iVentoy. Exiting."
        return 1
    fi

    # Extract the package
    if ! tar -zxvf "$INSTALL_DIR/$PACKAGE_NAME" -C "$INSTALL_DIR"; then
        echo "Failed to extract iVentoy. Exiting."
        return 1
    fi

    # Clean up the tar.gz file
    rm -f "$INSTALL_DIR/$PACKAGE_NAME"

    # Create startup script
    cat << EOF > "$STARTUP_SCRIPT"
#!/bin/bash
LOG_FILE="$LOG_FILE"
touch "\$LOG_FILE"
chmod 644 "\$LOG_FILE"
echo "\$(date): Starting iVentoy" >> "\$LOG_FILE"
cd "$INSTALL_DIR/$EXTRACTED_DIR" && ./iventoy.sh start >> "\$LOG_FILE" 2>&1
echo "\$(date): iVentoy startup completed" >> "\$LOG_FILE"
EOF

    # Make the startup script executable
    chmod +x "$STARTUP_SCRIPT"

    # Create systemd service file
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=iVentoy Startup Service
After=network.target

[Service]
ExecStart=$STARTUP_SCRIPT
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable and start the service
    systemctl daemon-reload
    systemctl enable iventoy.service
    if ! systemctl start iventoy.service; then
        echo "Failed to start iVentoy service. Please check the logs."
        return 1
    fi

    echo "iVentoy setup completed and service started."
    echo "To check the status of the service, use: systemctl status iventoy.service"
}

# Main script
check_root
check_dependencies

echo "Homelab -ActionPak- by Bas v1.3"
echo "Updating system..."
if ! apt-get update && apt-get upgrade -y; then
    echo "Failed to update system. Proceeding with caution."
fi

# Trap Ctrl+C
trap 'echo "Script interrupted. Exiting..."; exit 1' INT

while true; do
    display_menu
    read -p "Enter your choice: " choice
    case $choice in
        1) install_wazuh ;;
        2) install_nessus ;;
        3) install_clamav ;;
        4) install_webmin ;;
        5) create_service_account ;;
        6) install_caasos ;;
        7) install_tailscale ;;
        8) install_kasm ;;
        9) install_iventoy ;;
        10) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
    echo
    read -p "Press Enter to continue..."
    clear
done
