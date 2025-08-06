#!/bin/bash

echo "#########################################################"
echo " Script de Instalacao GLPI no Ubuntu 22 com Nginx"
echo "#########################################################"

# --- CONFIGURAÇÃO PADRÃO (VALORES PADRÃO) ---
# Se não forem passados como parâmetros, o script usará estes valores.
GLPI_VERSION="10.0.15"
DB_NAME="glpidb"
DB_USER="glpiuser"
DB_PASS="?GHo5zm@jj&9?r#m"

# --- PARSE DOS ARGUMENTOS DE LINHA DE COMANDO ---
# O 'getopts' é uma forma robusta de processar argumentos no shell.
while getopts "v:d:u:p:" opt; do
    case ${opt} in
        v) GLPI_VERSION=$OPTARG ;;
        d) DB_NAME=$OPTARG ;;
        u) DB_USER=$OPTARG ;;
        p) DB_PASS=$OPTARG ;;
        *)
            echo "Uso: $0 [-v <versao_glpi>] [-d <nome_db>] [-u <usuario_db>] [-p <senha_db>]"
            exit 1
            ;;
    esac
done

# --- VALIDAÇÕES BÁSICAS ---
if [ "$DB_PASS" == "sua_senha_forte_aqui" ]; then
    echo "Aviso: A senha do banco de dados não foi fornecida ou foi mantida no valor padrão."
    echo "Por favor, defina uma senha forte para produção."
fi

echo "Iniciando a instalação com as seguintes configurações:"
echo "GLPI Versão: ${GLPI_VERSION}"
echo "Banco de Dados: ${DB_NAME}"
echo "Usuário do DB: ${DB_USER}"
echo "Senha do DB: (oculto)"

# 1. Atualiza a lista de pacotes
sudo apt update -y

# 2. Instala softwares necessários e PHP-FPM com extensões
sudo apt install -y \
	nginx mariadb-server \
	php8.1-fpm php8.1-dom php8.1-fileinfo php8.1-json \
	php8.1-xml php8.1-curl php8.1-gd php8.1-intl \
	php8.1-mysqli php8.1-bz2 php8.1-zip php8.1-exif \
	php8.1-ldap php8.1-opcache php8.1-mbstring \
	wget

# 3. Criar banco de dados e usuário
sudo mysql -e "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mysql -e "GRANT SELECT ON mysql.time_zone_name TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# 4. Carregar timezones no MySQL
sudo mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -u root mysql

# 5. Configurar PHP-FPM
sudo sed -i 's/^;date.timezone =/date.timezone = America\/Sao_Paulo/' /etc/php/8.1/fpm/php.ini
sudo sed -i 's/^session.cookie_httponly =/session.cookie_httponly = on/' /etc/php/8.1/fpm/php.ini

# 6. Baixar e descompactar o GLPI
wget -O /tmp/glpi.tgz "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz"

# 7. Preparar diretórios e descompactar GLPI
sudo mkdir -p /var/www/glpi
sudo tar -xzf /tmp/glpi.tgz -C /var/www/glpi --strip-components=1
sudo rm /tmp/glpi.tgz

# 8. Configurar Nginx para o GLPI (Virtual Host)
cat << "EOF" | sudo tee /etc/nginx/sites-available/glpi.conf
server {
    listen 80;
    server_name _;
    root /var/www/glpi/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    location ~ /(config|files|locales|vendor)/ {
        deny all;
    }
}
EOF

# 9. Ativar o site do Nginx e reiniciar serviços
sudo ln -sf /etc/nginx/sites-available/glpi.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx php8.1-fpm

# 10. Configurar permissões iniciais do GLPI
sudo chown -R www-data:www-data /var/www/glpi

# 11. Finalizar setup do glpi pela linha de comando
sudo php /var/www/glpi/bin/console db:install \
	--default-language=pt_BR \
	--db-host=localhost \
	--db-port=3306 \
	--db-name=${DB_NAME} \
	--db-user=${DB_USER} \
	--db-password=${DB_PASS} \
	--no-interaction

# 12. Ajustes de Segurança Pós-instalação
sudo mkdir -p /var/lib/glpi
sudo mkdir -p /etc/glpi
sudo mkdir -p /var/log/glpi

sudo mv /var/www/glpi/files /var/lib/glpi
sudo mv /var/www/glpi/config /etc/glpi
sudo rm -rf /var/www/glpi/install

# 12.1. Criar os arquivos de configuração
cat << "EOF" | sudo tee /var/www/glpi/inc/downstream.php
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
   require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF

cat << "EOF" | sudo tee /etc/glpi/local_define.php
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
define('GLPI_DOC_DIR', GLPI_VAR_DIR);
define('GLPI_CRON_DIR', GLPI_VAR_DIR . '/_cron');
define('GLPI_DUMP_DIR', GLPI_VAR_DIR . '/_dumps');
define('GLPI_GRAPH_DIR', GLPI_VAR_DIR . '/_graphs');
define('GLPI_LOCK_DIR', GLPI_VAR_DIR . '/_lock');
define('GLPI_PICTURE_DIR', GLPI_VAR_DIR . '/_pictures');
define('GLPI_PLUGIN_DOC_DIR', GLPI_VAR_DIR . '/_plugins');
define('GLPI_RSS_DIR', GLPI_VAR_DIR . '/_rss');
define('GLPI_SESSION_DIR', GLPI_VAR_DIR . '/_sessions');
define('GLPI_TMP_DIR', GLPI_VAR_DIR . '/_tmp');
define('GLPI_UPLOAD_DIR', GLPI_VAR_DIR . '/_uploads');
define('GLPI_CACHE_DIR', GLPI_VAR_DIR . '/_cache');
define('GLPI_LOG_DIR', '/var/log/glpi');
EOF

# 12.2. Definir as permissões corretas
sudo chown -R www-data:www-data /etc/glpi
sudo chown -R www-data:www-data /var/lib/glpi
sudo chown -R www-data:www-data /var/log/glpi
sudo find /var/www/glpi/ -type f -exec chmod 644 {} \;
sudo find /var/www/glpi/ -type d -exec chmod 755 {} \;
sudo chown root:root /var/www/glpi/inc/downstream.php
sudo chown -R www-data:www-data /var/www/glpi/marketplace
sudo chown root:root /var/www/glpi/ -R
sudo chown -R www-data:www-data /var/www/glpi/public/ -R

echo "########  ###################"
echo " INSTALACAO FINALIZADA COM SUCESSO."
echo " Acesse o GLPI via navegador para realizar as configuracoes iniciais."
echo " Usuario de acesso padrao: glpi@localhost, Senha: ${DB_PASS}"
