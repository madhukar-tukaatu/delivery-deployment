#!/usr/bin/env bash
# ==============================================================================
# One-Command Initial Setup Script for Delivery Demo Server (VPS)
# IP: 103.160.22.123
# Target: Ubuntu 22.04 / 24.04 LTS
# ==============================================================================

set -euo pipefail

COLOR_GREEN="\033[0;32m"
COLOR_BLUE="\033[0;34m"
COLOR_YELLOW="\033[1;33m"
COLOR_RESET="\033[0m"

log() {
  echo -e "${COLOR_GREEN}==> $1${COLOR_RESET}"
}

warn() {
  echo -e "${COLOR_YELLOW}==> WARNING: $1${COLOR_RESET}"
}

# 1. System packages & updates
log "Updating system packages..."
apt-get update -y
apt-get install -y curl wget git ufw htop unzip fail2ban ca-certificates gnupg

# 2. Configure 4GB Swap (Essential to prevent out-of-memory during Next.js builds)
if ! grep -q '/swapfile' /etc/fstab; then
  log "Setting up 4GB Swap memory..."
  fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log "Swap created successfully."
else
  log "Swapfile already exists."
fi

# 3. Configure Firewall (UFW)
log "Configuring basic firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000/tcp  # Direct frontend demo port if needed
ufw allow 8081/tcp  # Direct backend demo port if needed
ufw allow 8080/tcp  # WebSockets reverb demo port if needed
ufw --force enable

# 4. Install Docker & Docker Compose Plugin
if ! command -v docker &> /dev/null; then
  log "Installing Docker & Docker Compose..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  log "Docker installed: $(docker --version)"
else
  log "Docker is already installed."
fi

# 5. Base Project Directory
log "Creating project directory at /var/www/delivery..."
mkdir -p /var/www/delivery
cd /var/www/delivery

# 6. SSH Deploy Key for GitHub
SSH_KEY_PATH="/root/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY_PATH" ]; then
  log "Generating SSH Deploy Key for GitHub..."
  ssh-keygen -t ed25519 -C "vps-demo@tukaatu" -f "$SSH_KEY_PATH" -N ""
fi

# Configure GitHub in known_hosts
ssh-keyscan -H github.com >> /root/.ssh/known_hosts 2>/dev/null

echo ""
echo -e "${COLOR_BLUE}=================================================================${COLOR_RESET}"
echo -e "${COLOR_BLUE}ACTION REQUIRED: Copy this SSH Public Key to your GitHub Repos:${COLOR_BLUE}"
echo -e "${COLOR_BLUE}=================================================================${COLOR_RESET}"
cat "${SSH_KEY_PATH}.pub"
echo -e "${COLOR_BLUE}=================================================================${COLOR_RESET}"
echo "Add this key to GitHub repository Settings -> Deploy Keys for:"
echo " 1) delivery-deployment"
echo " 2) delivery-backend"
echo " 3) delivery-frontend"
echo -e "${COLOR_BLUE}=================================================================${COLOR_RESET}"
echo ""

read -p "Press ENTER after adding the key to GitHub to continue cloning..."

# 7. Clone Repositories
BRANCH="deploy"

clone_or_checkout() {
  local repo_name="$1"
  local git_url="$2"

  if [ -d "$repo_name/.git" ]; then
    log "Repository $repo_name already exists. Pulling latest $BRANCH..."
    git -C "$repo_name" fetch origin "$BRANCH" 2>/dev/null || git -C "$repo_name" fetch origin main
    git -C "$repo_name" checkout "$BRANCH" 2>/dev/null || git -C "$repo_name" checkout -b "$BRANCH"
  else
    log "Cloning $repo_name..."
    git clone "$git_url" "$repo_name"
    cd "$repo_name"
    git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"
    cd /var/www/delivery
  fi
}

clone_or_checkout "delivery-deployment" "git@github.com:madhukar-tukaatu/delivery-deployment.git"
clone_or_checkout "delivery-backend" "git@github.com:madhukar-tukaatu/delivery-backend.git"
clone_or_checkout "delivery-frontend" "git@github.com:madhukar-tukaatu/delivery-frontend.git"

# 8. Create .env.production in delivery-deployment if missing
ENV_FILE="/var/www/delivery/delivery-deployment/.env.production"
if [ ! -f "$ENV_FILE" ]; then
  log "Creating .env.production from template..."
  cp /var/www/delivery/delivery-deployment/.env.deployment.example "$ENV_FILE"
  
  # Generate random DB and Redis passwords
  RANDOM_DB_PASS=$(openssl rand -hex 12)
  RANDOM_ROOT_PASS=$(openssl rand -hex 16)
  RANDOM_REDIS_PASS=$(openssl rand -hex 12)
  
  sed -i "s/COMPOSE_PROJECT_NAME=delivery/COMPOSE_PROJECT_NAME=delivery-demo/g" "$ENV_FILE"
  sed -i "s/APP_ENV=production/APP_ENV=development/g" "$ENV_FILE"
  sed -i "s/APP_DEBUG=false/APP_DEBUG=true/g" "$ENV_FILE"
  sed -i "s/delivery_dms/delivery_demo/g" "$ENV_FILE"
  sed -i "s/DB_PASSWORD=CHANGE_ME/DB_PASSWORD=$RANDOM_DB_PASS/g" "$ENV_FILE"
  sed -i "s/MYSQL_PASSWORD=CHANGE_ME/MYSQL_PASSWORD=$RANDOM_DB_PASS/g" "$ENV_FILE"
  sed -i "s/MYSQL_ROOT_PASSWORD=CHANGE_ME/MYSQL_ROOT_PASSWORD=$RANDOM_ROOT_PASS/g" "$ENV_FILE"
  sed -i "s/REDIS_PASSWORD=CHANGE_ME/REDIS_PASSWORD=$RANDOM_REDIS_PASS/g" "$ENV_FILE"
  
  log "Generated initial passwords in $ENV_FILE"
fi

log "Initial VPS setup complete!"
echo "Now run:"
echo "  cd /var/www/delivery/delivery-deployment"
echo "  docker compose --env-file .env.production up -d --build"
echo "  docker compose --env-file .env.production exec -T backend-app php artisan key:generate --force"
echo "  docker compose --env-file .env.production exec -T backend-app php artisan migrate --force"

