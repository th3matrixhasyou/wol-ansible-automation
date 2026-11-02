# **salmin_ansible**

====================================
v1.2
====================================
# 🚀 salmin_ansible — Deployment and Management Guide (NLRC Lab)

Centralized Ansible infrastructure automation hub for managing power and host configurations in the 192.168.0.0/24 subnet. 
The project supports incremental migration: new hosts are added as they are configured, and management commands affect only those devices that have explicit MAC addresses defined.

---

## 📁 1. Architecture and Project Structure

The project is divided into environments (green — production, yellow — testing) and contains a complete framework for automation, logging, and deployment.

~/ansible/
├── README.md               # General project documentation
├── README_RUS.md           # Russian-language guide
└── pwrmgmt/
    ├── green/              # Stable pool (Production)
    │   ├── hosts.ini       # Inventory of hosts and MAC addresses
    │   ├── group_vars/     # Encrypted variables (logins/passwords)
    │   ├── poweron.yml     # Remote power-on playbook (WOL)
    │   ├── poweroff.yml    # Shutdown via SSH playbook (shutdown)
    │   ├── poweroff_shutdown.yml # Shutdown via scheduler (SYSTEM)
    │   ├── install_ssh_key.yml   # Distribute SSH keys to nodes
    │   ├── setup_wol_ubuntu_only.yml # Configure Wake-on-LAN on Linux
    │   ├── get_macs.yml    # Automatic MAC address collection from hosts
    │   ├── check_ip.sh     # Host availability check script
    │   ├── wake_pc_pool.sh # Backup power-on bash script
    │   ├── run_on.sh       # Wrapper for running power-on via cron
    │   ├── run_off.sh      # Wrapper for running shutdown via cron
    │   ├── vault_pass.txt  # Master password for Ansible Vault
    │   ├── cron_poweron.log  # Automatic power-on log
    │   ├── cron_poweroff.log # Automatic shutdown log
    │   ├── id_rsa_project  # Private SSH key
    │   └── id_rsa_project.pub # Public SSH key
    └── yellow/             # Testing environment (Staging)

### Purpose of Key Components:
* hosts.ini — centralized inventory file. Hosts without `mac=` are skipped.
* group_vars/all.yml — encrypted credentials for Linux and Windows.
* poweroff.yml — sends `shutdown -h now` directly via SSH.
* poweroff_shutdown.yml — shutdown via system scheduler executed as SYSTEM.
* check_ip.sh — pings all hosts from hosts.ini and lists those that are DOWN.

---

## 🛠 2. Managing the Control Node (Ubuntu)

Install necessary system utilities:
sudo apt update
sudo apt install -y ansible wakeonlan

### Resolving Old Python Version Issues (e.g., Python 3.8)
If `python3.10` cannot be found via apt, use a standalone build:

# Temporarily remove problematic NVIDIA repository lists
sudo mv /etc/apt/sources.list.d/nvidia* /tmp/ 2>/dev/null || true

# Create directory and download the optimized Python 3.10 binary
sudo mkdir -p /opt/python3.10
cd /tmp
wget https://github.com/indygreg/python-build-standalone/releases/download/20240224/cpython-3.10.13+20240224-x86_64-unknown-linux-gnu-install_only.tar.gz

# Extract into the system folder
sudo tar -xzf cpython-3.10.13+20240224-x86_64-unknown-linux-gnu-install_only.tar.gz -C /opt/python3.10 --strip-components=1

# Verify
/opt/python3.10/bin/python3 --version

*After doing this, specify the path in hosts.ini using the parameter:*
`ansible_python_interpreter=/opt/python3.10/bin/python3`

---

## 🔑 3. Managing SSH Keys and Access

If keys are corrupted (error in libcrypto) or need to be recreated:
cd ~/ansible/pwrmgmt/green
rm -f id_rsa_project id_rsa_project.pub
ssh-keygen -t rsa -b 4096 -f id_rsa_project -N ""
chmod 600 id_rsa_project

Distribute keys to target hosts:
ansible-playbook -i hosts.ini install_ssh_key.yml --ask-pass
*(The `--ask-pass` flag prompts for the SSH connection password of the ansible user).*

---

## 📋 4. Configuring Inventory (hosts.ini)

Example inventory configuration:

[pc_pool]
192.168.0.216 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project ansible_python_interpreter=/opt/python3.10/bin/python3 mac=d8:5e:d3:53:39:17
192.168.0.217 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project mac=d8:5e:d3:53:39:00
192.168.0.228 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project

*(Host .228 without the mac parameter will be automatically skipped).*

---

## 🪟 5. Preparing Target PCs (Windows)

### Creating the Ansible Administrator (run in PowerShell as Administrator):
$Password = ConvertTo-SecureString "engNN!52" -AsPlainText -Force
New-LocalUser -Name "ansible" -Password $Password -FullName "ANSIBLE" -Description "The Matrix has You..." -PasswordNeverExpires
Add-LocalGroupMember -Group "Administrators" -Member "ansible"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Force

### Configuring Wake-on-LAN (WoL) in Windows:
1. **Fast Startup:** Control Panel -> Power Options -> "Choose what the power buttons do" -> uncheck "Turn on fast startup".
2. **Device Manager -> Network Adapters -> Adapter Properties:**
   * **Power Management:** enable "Allow this device to wake the computer" and "Only allow a magic packet to wake the computer".
   * **Advanced:**
     * `Energy Efficient Ethernet` — Disabled
     * `Enable PME` — Enabled
     * `Ultra Low Power Mode` — Disabled
     * `Wake on Link Settings` — Disabled
     * `Wake on Pattern Match` — Disabled

---

## 🚀 6. Running Pipelines and Management Commands

### Time Synchronization (Moscow, NTP)
sudo timedatectl set-timezone Europe/Moscow
sudo timedatectl set-ntp on
timedatectl

### Ansible Command Reference:
* **Check host availability:**
  `./check_ip.sh`
* **Configure Wake-on-LAN service on Linux:**
  `ansible-playbook -i hosts.ini setup_wol_ubuntu_only.yml --ask-become-pass`
* **Power on computers (WOL):**
  `ansible-playbook -i hosts.ini poweron.yml --vault-password-file vault_pass.txt`
* **Power on via Bash script:**
  `chmod +x wake_pc_pool.sh && ./wake_pc_pool.sh`
* **Power off via SSH:**
  `ansible-playbook -i hosts.ini poweroff.yml --vault-password-file vault_pass.txt`
* **Power off via scheduler (SYSTEM):**
  `ansible-playbook -i hosts.ini poweroff_shutdown.yml --vault-password-file vault_pass.txt`

---

## ⏰ 7. Scheduled Automation (Cron)

### Step 1. Securing the Vault Password
cd /home/neo/ansible/pwrmgmt/green
echo "your_vault_password" > vault_pass.txt
chmod 600 vault_pass.txt

### Step 2. Creating Wrapper Scripts with Logging

* **`run_off.sh` (Shutdown):**
#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green
echo -e "\n========================================" >> cron_poweroff.log
echo "=== Execution: $(date '+%Y-%m-%d %H:%M:%S') ===" >> cron_poweroff.log
echo "========================================" >> cron_poweroff.log
/usr/bin/ansible-playbook -i hosts.ini poweroff.yml --vault-password-file vault_pass.txt >> cron_poweroff.log 2>&1

* **`run_on.sh` (Power On):**
#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green
echo -e "\n========================================" >> cron_poweron.log
echo "=== Execution: $(date '+%Y-%m-%d %H:%M:%S') ===" >> cron_poweron.log
echo "========================================" >> cron_poweron.log
/usr/bin/ansible-playbook -i hosts.ini poweron.yml --vault-password-file vault_pass.txt >> cron_poweron.log 2>&1

Grant execution permissions:
`chmod +x run_off.sh run_on.sh`

### Step 3. Configuring Crontab
`crontab -e`

Add the schedule:
# Shutdown on weekdays (Mon-Fri) at 18:00 and safety backup at 18:15
0 18 * * 1-5 /home/neo/ansible/pwrmgmt/green/run_off.sh
15 18 * * 1-5 /home/neo/ansible/pwrmgmt/green/run_off.sh

# Power on on weekdays (Mon-Fri) sharp at 09:30
30 9 * * 1-5 /home/neo/ansible/pwrmgmt/green/run_on.sh

### Monitoring and Checking Logs:
* Check schedule: `crontab -l`
* Shutdown logs: `cat cron_poweroff.log`
* Power-on logs: `cat cron_poweron.log`

---

## 8. Updated check_ip.sh Script

Replace the file contents with the following variant:

#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green
INI_FILE="hosts.ini"
LOG_FILE="check_ip.log"

# Add a separator and timestamp to the log
echo -e "\n========================================" >> "$LOG_FILE"
echo "=== Check started: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

if [[ ! -f "$INI_FILE" ]]; then
    echo "Error: $INI_FILE not found!" >> "$LOG_FILE"
    exit 1
fi

while IFS= read -r line; do
    # Strip leading/trailing whitespace
    line=$(echo "$line" | xargs)

    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Extract the first word (can be an IP, section header, or variable)
    first_word=$(echo "$line" | awk '{print $1}')

    # Skip section headers like [pc_pool] or [windows_pool:vars]
    [[ "$first_word" =~ ^\[ ]] && continue

    # Check if the first word looks like an IP address (starts with a digit)
    [[ ! "$first_word" =~ ^[0-9] ]] && continue

    # Strip port if specified (e.g., 192.168.0.246:101 -> 192.168.0.246)
    ip=$(echo "$first_word" | cut -d: -f1)

    if ! ping -c 1 -W 1 "$ip" &>/dev/null; then
        echo "DOWN: $ip" >> "$LOG_FILE"
    fi
done < "$INI_FILE"

### Adding to Cron
Open the scheduler editor:
`crontab -e`

Add a line to run the script every day at 20:00:
# Check host availability daily at 20:00
0 20 * * * /home/neo/ansible/pwrmgmt/green/check_ip.sh

Save the file and exit (depending on the editor: nano — `Ctrl + O`, `Enter`, `Ctrl + X`; vim — `Esc`, then `:wq` and `Enter`).

### How to view results:
`cat /home/neo/ansible/pwrmgmt/green/check_ip.log`

---

====================================
v1.0
====================================

Central Ansible infrastructure automation hub for NLRC Lab. Manages configuration, deployment, and orchestration across segmented environments. Serves as the primary repository for Infrastructure as Code (IaC) maintenance and automated system operations.

iWTC PC Power Management (Ansible)
A collection of Ansible playbooks for automated power management of a PC pool in the 192.168.34.0/24 subnet. The project supports incremental migration: new machines are added to the general pool as they are configured, and management commands affect exclusively those hosts that have explicit MAC addresses defined.

Project Structure
Plaintext
├── hosts.ini            # Centralized inventory listing hosts and MAC addresses
├── poweroff.yml         # Playbook for remote shutdown of configured PCs
├── wake_ready.yml       # Playbook for waking up (Wake-on-LAN) configured PCs
└── id_rsa_project       # Private SSH key for node access

Requirements
* Installed Ansible on the control machine (localhost).
* The `wakeonlan` utility on the control machine (for sending magic packets).
* Configured SSH access to target PCs under the `ansible` user using the `id_rsa_project` private key.
* Configured passwordless sudo (or readiness to enter sudo password interactively during shutdown) on target hosts.

Configuring Inventory (hosts.ini)
All hosts are described under the `[pc_pool]` group.
If a computer is configured (ready for power management), the `mac=XX:XX:XX:XX:XX:XX` parameter is added to it.
If a computer is not yet configured (in the process of commissioning), the `mac` parameter is omitted. Playbooks automatically skip such hosts.

Example hosts.ini file:

[pc_pool]
192.168.0.216 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project ansible_python_interpreter=/opt/python3.10/bin/python3 mac=d8:5e:d3:53:39:17
192.168.0.217 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project mac=d8:5e:d3:53:39:00

# Host without a MAC address (will be skipped by automation):
192.168.0.228 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project

Usage

1. Shutting Down Configured Computers
The playbook connects via SSH to each host from `pc_pool`, checks for the `mac` parameter, and performs a safe shutdown (`shutdown -h now`).

    ansible-playbook -i hosts.ini poweroff.yml -K

*(The `-K` flag is used if target nodes require a sudo password prompt).*

2. Waking Up Configured Computers (Wake-on-LAN)
The playbook runs locally (`localhost`), scans the `pc_pool` inventory, finds all machines with a populated `mac` parameter, and sends a WOL broadcast packet (`192.168.0.255`).

    ansible-playbook -i hosts.ini wake_ready.yml

How to add a new computer to the project:
* Configure the OS and base environment on the target PC.
* Ensure the `ansible` user and SSH key (`id_rsa_project`) have proper access.
* Find the MAC address of the target machine's network interface.
* Add the host IP address to the `[pc_pool]` section of `hosts.ini` along with the `mac=XX:XX:XX:XX:XX:XX` parameter.
* Afterwards, the computer will automatically be accounted for when running power-on and power-off playbooks.

---

====================================
v1.1
====================================

Project Deployment and Management Guide (Power Management Ansible Project)

1. Deploying the Project on a New Machine (Control Node)
If you are moving the project to a clean machine (e.g., running Ubuntu), complete the following steps to prepare the environment:

* Install Ansible and necessary system utilities:

    sudo apt update
    sudo apt install -y ansible wakeonlan

* Move project files to your working directory (e.g., `~/ansible/pwrmgmt/yellow/`).

2. Generating and Recreating SSH Keys (Troubleshooting Access Issues)
If you encounter authorization errors, a corrupted key file (`error in libcrypto`), or need to completely refresh the security key pair:

* Delete old keys (if corrupted) in the project folder:

    rm -f id_rsa_project id_rsa_project.pub

* Generate a new RSA key pair without a passphrase (`-N ""`):

    ssh-keygen -t rsa -b 4096 -f id_rsa_project -N ""

* Set correct permissions on the private key (SSH strictly requires 600 permissions, otherwise it will output a `bad permissions` error):

    chmod 600 id_rsa_project

* Distribute the new keys to target hosts (the module will prompt for the `ansible` user SSH password on remote machines):

    ansible-playbook -i hosts.ini install_ssh_key.yml --ask-pass

3. Description of Project Files
Your project utilizes the following key files:

* `hosts.ini` — Inventory file. Defines IP addresses of target computers (part of the `pc_pool` group) grouped for power management.
* `install_ssh_key.yml` — Playbook for initial security configuration. Connects to hosts and adds your public key (`id_rsa_project.pub`) to `~/.ssh/authorized_keys` on remote machines.
* `setup_wol_ubuntu_only.yml` — Wake-on-LAN configuration playbook. Automatically checks network interfaces, creates a system `wol.service` using `ethtool`, and activates magic packet listening mode (`wol g`).
* `poweron.yml` — Playbook for remote computer power-on. Runs locally (`localhost`) and sends Magic Packets to the subnet broadcast address for each MAC address in the inventory.
* `poweroff.yml` — Playbook for centralized shutdown of all computers from the pool (`hosts: pc_pool`). Runs in parallel mode (`strategy: free`) and sends the `shutdown -h now` command.
* `get_macs.yml` — Auxiliary universal playbook for automatically collecting MAC addresses of network interfaces from target machines.

4. Running Pipelines and Playbooks (With Correct Keys)
To ensure all commands execute without failures or permission errors, use the following commands:

* Step 1. Configuring Wake-on-LAN Service on Hosts
Performs `ethtool` and `wol.service` configuration on remote servers/PCs. Since this task requires administrative privileges on target machines, the `--ask-become-pass` flag must be used:

    ansible-playbook -i hosts.ini setup_wol_ubuntu_only.yml --ask-become-pass

*(When prompted for BECOME password:, enter the superuser sudo password of the remote machine).*

* Step 2. Powering On Computers (Wake-on-LAN)
Initiates sending wake-up network packets (executed on the control machine `localhost`):

    ansible-playbook -i hosts.ini poweron.yml

* Step 3. Shutting Down Computers
Sends a safe shutdown signal to all active hosts in the pool:

    ansible-playbook -i hosts.ini poweroff.yml --ask-become-pass
