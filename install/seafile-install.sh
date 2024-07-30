#!/bin/sh

# Seafile Installation Script for Alpine Linux on Proxmox LXC

# Set Variables
SEAFILE_VERSION="8.0.5"
SEAFILE_DB_PASSWORD="your_seafile_db_password"
SEAFILE_ADMIN_EMAIL="admin@example.com"
SEAFILE_ADMIN_PASSWORD="your_admin_password"
DOMAIN="yourdomain.com"

# Update and Install Dependencies
echo "Updating system and installing dependencies..."
apk update && apk upgrade
apk add mariadb mariadb-client nginx py3-pip wget curl
pip3 install --upgrade pip

# Setup MariaDB
echo "Setting up MariaDB..."
service mariadb setup
service mariadb start
mysql_secure_installation <<EOF

y
${SEAFILE_DB_PASSWORD}
${SEAFILE_DB_PASSWORD}
y
y
y
y
EOF

# Create Seafile Database and User
echo "Creating Seafile database and user..."
mysql -uroot -p${SEAFILE_DB_PASSWORD} <<EOF
CREATE DATABASE ccnet_db character set = 'utf8';
CREATE DATABASE seafile_db character set = 'utf8';
CREATE DATABASE seahub_db character set = 'utf8';
CREATE USER 'seafile'@'localhost' IDENTIFIED BY '${SEAFILE_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ccnet_db.* to 'seafile'@'localhost';
GRANT ALL PRIVILEGES ON seafile_db.* to 'seafile'@'localhost';
GRANT ALL PRIVILEGES ON seahub_db.* to 'seafile'@'localhost';
FLUSH PRIVILEGES;
EOF

# Download and Install Seafile
echo "Downloading and installing Seafile..."
cd /opt
wget https://download.seadrive.org/seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz
tar -xzf seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz
cd seafile-server-${SEAFILE_VERSION}

# Run Seafile Setup Script
./setup-seafile-mysql.sh auto -n \
  -h localhost \
  -p ${SEAFILE_DB_PASSWORD} \
  -d seafile_db \
  -u seafile \
  -w ${SEAFILE_DB_PASSWORD}

# Configure Nginx for Seafile
echo "Configuring Nginx..."
cat <<EOL >/etc/nginx/conf.d/seafile.conf
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host \$server_name;
    }

    location /seafhttp {
        rewrite ^/seafhttp(.*)$ \$1 break;
        proxy_pass http://127.0.0.1:8082;
        client_max_body_size 0;
        proxy_connect_timeout 36000s;
        proxy_read_timeout 36000s;
    }

    location /media {
        root /opt/seafile-server-latest/seahub;
    }
}
EOL

# Start and Enable Services
echo "Starting Seafile and Nginx services..."
/opt/seafile-server-${SEAFILE_VERSION}/seafile.sh start
/opt/seafile-server-${SEAFILE_VERSION}/seahub.sh start
service nginx restart

# Set up Seafile admin account
echo "Setting up Seafile admin account..."
echo "from seahub_base.models import User; User.objects.create_superuser('${SEAFILE_ADMIN_EMAIL}', '${SEAFILE_ADMIN_PASSWORD}', is_staff=True)" | /opt/seafile-server-${SEAFILE_VERSION}/seaf-sh python3

# Enable Services to Start on Boot
rc-update add mariadb
rc-update add nginx

# Cleanup
echo "Cleaning up..."
rm /opt/seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz

echo "Seafile installation completed. Access the web interface to finalize configuration."
