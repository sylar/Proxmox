#!/usr/bin/env bash

# Copyright (c) 2024 YourName
# License: MIT

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add newt curl openssl openssh nano mc nginx
$STD apk add python3 py3-pip py3-mysqlclient
$STD apk add mariadb mariadb-client
msg_ok "Installed Dependencies"

msg_info "Configuring MariaDB"
DB_NAME=seafile_db
DB_USER=seafile
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
ROOT_PASS="$(openssl rand -base64 18 | cut -c1-13)"
echo "" >>~/seafile.creds
echo -e "MariaDB Root Password: \e[32m$ROOT_PASS\e[0m" >>~/seafile.creds
echo -e "Seafile Database Name: \e[32m$DB_NAME\e[0m" >>~/seafile.creds
echo -e "Seafile Database User: \e[32m$DB_USER\e[0m" >>~/seafile.creds
echo -e "Seafile Database Password: \e[32m$DB_PASS\e[0m" >>~/seafile.creds

$STD mariadb-install-db --user=mysql --datadir=/var/lib/mysql
$STD rc-service mariadb start
$STD rc-update add mariadb

$STD mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASS'; DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'; FLUSH PRIVILEGES;"

$STD mysql -u root -p"$ROOT_PASS" -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

msg_ok "Configured MariaDB"

msg_info "Installing Seafile"
SEAFILE_VERSION="9.0.10"
ADMIN_EMAIL=admin@seafile.local
ADMIN_PASS="$(openssl rand -base64 18 | cut -c1-13)"
echo "" >>~/seafile.creds
echo -e "Seafile Admin Email: \e[32m$ADMIN_EMAIL\e[0m" >>~/seafile.creds
echo -e "Seafile Admin Password: \e[32m$ADMIN_PASS\e[0m" >>~/seafile.creds

$STD wget https://download.seadrive.org/seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz
$STD tar xzf seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz
$STD mkdir -p /opt/seafile
$STD mv seafile-server-${SEAFILE_VERSION} /opt/seafile/
$STD adduser -D -h /opt/seafile -s /sbin/nologin seafile
$STD chown -R seafile:seafile /opt/seafile
cd /opt/seafile/seafile-server-${SEAFILE_VERSION}

# Get the container's IP address
IP4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)

# Setup Seafile (one-liner)
$STD ./setup-seafile-mysql.sh auto -n seafile -i $IP4 -d /opt/seafile/seafile-data -p 3306 -u $DB_USER -w $DB_PASS -q $DB_NAME

# Configure Seafile
sed -i "s/# SERVICE_URL.*/SERVICE_URL = https:\/\/$IP4/" /opt/seafile/conf/ccnet.conf
sed -i "s/# FILE_SERVER_ROOT.*/FILE_SERVER_ROOT = https:\/\/$IP4\/seafhttp/" /opt/seafile/conf/seafile.conf

msg_ok "Installed Seafile"

msg_info "Configuring Nginx"
$STD openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout /etc/ssl/private/seafile-selfsigned.key -out /etc/ssl/certs/seafile-selfsigned.crt -subj "/C=US/O=Seafile/OU=Domain Control Validated/CN=$IP4"
cat <<EOF >/etc/nginx/http.d/seafile.conf
server {
    listen 80;
    server_name $IP4;
    rewrite ^ https://\$http_host\$request_uri? permanent;
}

server {
    listen 443 ssl http2;
    ssl_certificate /etc/ssl/certs/seafile-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/seafile-selfsigned.key;
    server_name $IP4;

    location / {
        proxy_pass         http://127.0.0.1:8000;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host \$server_name;
        proxy_read_timeout  1200s;
        client_max_body_size 0;
    }

    location /seafhttp {
        rewrite ^/seafhttp(.*)\$ \$1 break;
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        client_max_body_size 0;
        proxy_connect_timeout  36000s;
        proxy_read_timeout  36000s;
        proxy_send_timeout  36000s;
        send_timeout  36000s;
    }
}
EOF
msg_ok "Configured Nginx"

msg_info "Creating Seafile Services"
cat <<'EOF' >/etc/init.d/seafile
#!/sbin/openrc-run

name="Seafile"
command="/opt/seafile/seafile-server-latest/seafile.sh"
command_args="start"
pidfile="/opt/seafile/pids/seaf-server.pid"
start_stop_daemon_args="--chdir /opt/seafile --user seafile"

depend() {
    need net
    use logger dns
    after firewall mariadb
}

start_pre() {
    checkpath --directory --owner seafile:seafile --mode 0755 /opt/seafile/pids
}

stop() {
    ebegin "Stopping Seafile"
    su -s /bin/sh -c "${command} stop" seafile
    eend $?
}
EOF

cat <<'EOF' >/etc/init.d/seahub
#!/sbin/openrc-run

name="Seahub"
command="/opt/seafile/seafile-server-latest/seahub.sh"
command_args="start-fastcgi"
pidfile="/opt/seafile/pids/seahub.pid"
start_stop_daemon_args="--chdir /opt/seafile --user seafile"

depend() {
    need net seafile
    use logger dns
    after firewall
}

start_pre() {
    checkpath --directory --owner seafile:seafile --mode 0755 /opt/seafile/pids
}

stop() {
    ebegin "Stopping Seahub"
    su -s /bin/sh -c "${command} stop" seafile
    eend $?
}
EOF

chmod +x /etc/init.d/seafile /etc/init.d/seahub
$STD rc-update add seafile default
$STD rc-update add seahub default
msg_ok "Created Seafile Services"

msg_info "Starting Services"
$STD rc-service nginx start
$STD rc-update add nginx default
$STD rc-service seafile start
$STD rc-service seahub start
msg_ok "Started Services"

motd_ssh
customize

msg_info "Seafile installation completed"
echo "You can now access Seafile at https://$IP4"
echo "Admin email: $ADMIN_EMAIL"
echo "Admin password: $ADMIN_PASS"
echo "Please change the admin password after first login."
