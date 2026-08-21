#!/usr/bin/env bash
set -e

echo "=================================================="
echo "  MCP Email Connector — Linux Setup Script"
echo "=================================================="

# 1. Check Node.js
if ! command -v node &> /dev/null; then
    echo "[-] Node.js is not installed. Please install Node.js (v18+) first."
    exit 1
fi
echo "[+] Node.js detected: $(node -v)"

# 2. Install stunnel if not present
if ! command -v stunnel &> /dev/null && ! command -v stunnel4 &> /dev/null; then
    echo "[*] Installing stunnel..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y && sudo apt-get install -y stunnel4
    elif command -v yum &> /dev/null; then
        sudo yum install -y stunnel
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y stunnel
    else
        echo "[-] Unsupported package manager. Please install stunnel manually."
        exit 1
    fi
fi
echo "[+] stunnel is installed."

# 3. Configure stunnel for Linux
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUNNEL_CONF="/etc/stunnel/stunnel.conf"

echo "[*] Configuring /etc/stunnel/stunnel.conf..."
sudo mkdir -p /etc/stunnel /var/log/stunnel4
sudo tee "$STUNNEL_CONF" > /dev/null << 'EOF'
debug = 6
output = /var/log/stunnel4/stunnel.log

options = -NO_TLSv1
sslVersionMin = TLSv1
sslVersionMax = TLSv1
ciphers = DEFAULT@SECLEVEL=0

[imaps-bridge]
client = yes
accept = 127.0.0.1:11993
connect = mail.triasmail.co.id:993
verify = 0
EOF

# Enable ENABLED=1 in /etc/default/stunnel4 if on Debian/Ubuntu
if [ -f /etc/default/stunnel4 ]; then
    sudo sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
fi

# 4. Start & enable stunnel service
echo "[*] Starting stunnel service..."
if command -v systemctl &> /dev/null; then
    sudo systemctl restart stunnel4 2>/dev/null || sudo systemctl restart stunnel 2>/dev/null || sudo stunnel /etc/stunnel/stunnel.conf
    sudo systemctl enable stunnel4 2>/dev/null || sudo systemctl enable stunnel 2>/dev/null || true
else
    sudo stunnel /etc/stunnel/stunnel.conf 2>/dev/null || true
fi
echo "[+] stunnel service is active."

# 5. Check .env
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "[!] .env file not found. Creating from .env.example..."
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "[!] Please edit .env with your credentials before running the server."
fi

# 6. Install dependencies and build
echo "[*] Installing npm dependencies..."
cd "$SCRIPT_DIR"
npm install

echo "[*] Building TypeScript..."
npm run build

echo ""
echo "=================================================="
echo "  Setup Completed Successfully!"
echo "=================================================="
echo "To test connection, run: node dist/testConnection.js"
echo "To run MCP server, run:  npm start (or node dist/index.js)"
echo "=================================================="
