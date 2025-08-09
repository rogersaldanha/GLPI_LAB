#!/usr/bin/env bash
# Instalação automatizada do GLPI no Ubuntu 22.04 com Nginx + PHP-FPM + MariaDB
# Com ajustes de segurança recomendados pela documentação oficial

# ————— CONFIGURAÇÕES —————
GLPI_DB="glpi"
GLPI_USER="glpiuser"
GLPI_PASS="?GHo5zm@jj&9?r#m"
GLPI_VERSION="10.0.15"
DOMAIN="54.189.107.254"           # IP ou domínio
WEB_ROOT="/var/www/glpi"
GLPI_PUBLIC_DIR="$WEB_ROOT/public"
GLPI_FILES_DIR="/var/lib/glpi/files"
LOGFILE="/var/log/install_glpi.log"
DOWNLOAD_DIR="/tmp"
KEEP_DOWNLOADS=false
NGINX_CONF="/etc/nginx/sites-available/glpi"
PHP_VERSION="8.1"

# ————— CORES PARA MENSAGENS —————
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  echo "$(timestamp) $*" | sudo tee -a "$LOGFILE" > /dev/null
}

info() {
  echo -e "${BLUE}[INFO]${NC} $*"
  log "[INFO] $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
  log "[OK] $*"
}

warn() {
  echo -e "${YELLOW}[AVISO]${NC} $*"
  log "[AVISO] $*"
}

fail() {
  echo -e "${RED}[ERRO]${NC} $*"
  log "[ERRO] $*"
  echo -e "${RED}Abortando.${NC}"
  exit 1
}

trap 'fail "Execução interrompida pelo usuário."; exit 1' INT TERM

# ————— INÍCIO —————

echo
info "Iniciando instalação do GLPI com segurança reforçada. Log em: $LOGFILE"
echo

# Verificar sudo
if ! sudo -n true 2>/dev/null; then
  warn "Você precisará digitar a senha do sudo quando solicitado."
fi

# Verificar existência do diretório principal GLPI
if [ -d "$WEB_ROOT" ]; then
  warn "Diretório $WEB_ROOT já existe."
  read -p "Deseja abortar para evitar sobrescrever? (s/N): " resp
  case "$resp" in
    [sS][iI]|[sS]) fail "Abortado. Remova $WEB_ROOT e execute novamente." ;;
    *) warn "Continuando por sua conta e risco." ;;
  esac
fi

# Atualizar sistema
info "Atualizando o sistema..."
sudo apt update -y || fail "Erro no apt update"
sudo apt upgrade -y || fail "Erro no apt upgrade"
success "Sistema atualizado"

# Instalar pacotes necessários (inclui bz2 e zip)
info "Instalando Nginx, MariaDB, PHP e extensões..."
sudo apt install -y nginx mariadb-server mariadb-client \
php-fpm php-cli php-common php-mysql php-gd php-imap php-ldap php-apcu php-xmlrpc \
php-curl php-mbstring php-xml php-bcmath php-intl unzip wget php-bz2 php-zip || fail "Falha na instalação dos pacotes"
success "Pacotes instalados"

# Ativar e iniciar serviços
info "Iniciando e habilitando serviços..."
sudo systemctl enable --now nginx mariadb || fail "Erro ao iniciar nginx ou mariadb"

PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
if sudo systemctl is-active --quiet "$PHP_FPM_SERVICE"; then
  success "$PHP_FPM_SERVICE ativo"
else
  if sudo systemctl is-active --quiet php-fpm; then
    PHP_FPM_SERVICE="php-fpm"
    success "php-fpm ativo"
  else
    warn "$PHP_FPM_SERVICE não ativo. Tentando iniciar..."
    sudo systemctl enable --now "$PHP_FPM_SERVICE" || warn "Não foi possível iniciar $PHP_FPM_SERVICE"
  fi
fi

# Detectar socket PHP-FPM
info "Detectando socket PHP-FPM..."
PHP_SOCKET=""
if [ -S "/var/run/php/php${PHP_VERSION}-fpm.sock" ]; then
  PHP_SOCKET="/var/run/php/php${PHP_VERSION}-fpm.sock"
else
  SOCKS=(/var/run/php/*.sock)
  if [ -S "${SOCKS[0]}" ]; then
    PHP_SOCKET="${SOCKS[0]}"
  fi
fi
if [ -z "$PHP_SOCKET" ]; then
  warn "Socket PHP-FPM não encontrado automaticamente. Ajuste o fastcgi_pass manualmente."
else
  success "Socket PHP-FPM detectado: $PHP_SOCKET"
fi

# Configurar PHP para segurança nas sessões
info "Configurando PHP para segurança nas sessões..."
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
sudo sed -i 's/^;session.cookie_httponly =.*/session.cookie_httponly = On/' "$PHP_INI"
sudo sed -i 's/^;session.cookie_secure =.*/session.cookie_secure = On/' "$PHP_INI" || true # pode falhar se não existir linha comentada
success "Configurações PHP aplicadas"

# Criar banco e usuário MariaDB
info "Criando banco e usuário no MariaDB..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`${GLPI_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" || fail "Falha ao criar banco"
sudo mysql -e "CREATE USER IF NOT EXISTS '${GLPI_USER}'@'localhost' IDENTIFIED BY '${GLPI_PASS}';" || fail "Falha ao criar usuário"
sudo mysql -e "GRANT ALL PRIVILEGES ON \`${GLPI_DB}\`.* TO '${GLPI_USER}'@'localhost'; FLUSH PRIVILEGES;" || fail "Falha ao dar privilégios"
success "Banco e usuário criados"

# Baixar GLPI
info "Baixando GLPI versão ${GLPI_VERSION}..."
cd "$DOWNLOAD_DIR" || fail "Falha ao acessar $DOWNLOAD_DIR"
GLPI_TGZ="glpi-${GLPI_VERSION}.tgz"
GLPI_URL="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/${GLPI_TGZ}"
wget -q --show-progress "$GLPI_URL" || fail "Download falhou: $GLPI_URL"
success "Download concluído"

# Extrair e mover GLPI
info "Extraindo e movendo GLPI para $WEB_ROOT..."
tar -xzf "$GLPI_TGZ" || fail "Erro ao descompactar"
sudo rm -rf "$WEB_ROOT" || true
sudo mv glpi "$WEB_ROOT" || fail "Erro ao mover arquivos"
success "GLPI instalado"

# Mover diretório files para fora da raiz web
info "Movendo diretório de arquivos GLPI para $GLPI_FILES_DIR..."
sudo mkdir -p "$GLPI_FILES_DIR"
if [ -d "$WEB_ROOT/files" ]; then
  sudo mv "$WEB_ROOT/files"/* "$GLPI_FILES_DIR/" || warn "Não foi possível mover todos os arquivos de files"
  sudo rm -rf "$WEB_ROOT/files"
fi
sudo chown -R www-data:www-data "$GLPI_FILES_DIR"
success "Diretório files movido e permissões ajustadas"

# Ajustar permissões no GLPI
info "Ajustando permissões para www-data..."
sudo chown -R www-data:www-data "$WEB_ROOT" || fail "Erro no chown"
sudo find "$WEB_ROOT" -type d -exec chmod 755 {} \; || fail "Erro chmod dirs"
sudo find "$WEB_ROOT" -type f -exec chmod 644 {} \; || fail "Erro chmod files"
success "Permissões ajustadas"

# Criar ou atualizar configuração GLPI para definir GLPI_VAR_DIR
info "Configurando variável GLPI_VAR_DIR no config/config.php..."
CONFIG_FILE="$WEB_ROOT/config/config.php"
if ! grep -q "define('GLPI_VAR_DIR'" "$CONFIG_FILE" 2>/dev/null; then
  echo "<?php" | sudo tee -a "$CONFIG_FILE" >/dev/null
  echo "define('GLPI_VAR_DIR', '$GLPI_FILES_DIR');" | sudo tee -a "$CONFIG_FILE" >/dev/null
else
  sudo sed -i "s|define('GLPI_VAR_DIR'.*|define('GLPI_VAR_DIR', '$GLPI_FILES_DIR');|" "$CONFIG_FILE"
fi
success "Configuração GLPI atualizada"

# Configurar Nginx
info "Criando configuração do Nginx..."
sudo bash -c "cat > $NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $GLPI_PUBLIC_DIR;
    index index.php index.html;

    access_log /var/log/nginx/glpi_access.log;
    error_log /var/log/nginx/glpi_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCKET;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(?:ico|css|js|gif|jpe?g|png|woff2?|eot|ttf|svg)\$ {
        expires 6M;
        access_log off;
    }
}
EOF

# Ativar site e remover default
info "Ativando site GLPI e desativando site default..."
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/glpi || fail "Erro ao ativar site"
if [ -f /etc/nginx/sites-enabled/default ]; then
  sudo rm -f /etc/nginx/sites-enabled/default
  warn "Site default removido para evitar conflito"
fi

# Testar e reiniciar Nginx
info "Testando configuração do Nginx..."
sudo nginx -t >/dev/null 2>&1 || { sudo tail -n 50 /var/log/nginx/error.log 2>/dev/null; fail "Erro na configuração do Nginx"; }
success "Configuração do Nginx válida"

info "Reiniciando serviços Nginx e PHP-FPM..."
sudo systemctl restart nginx || fail "Falha ao reiniciar Nginx"
sudo systemctl restart "$PHP_FPM_SERVICE" || warn "Falha ao reiniciar PHP-FPM"
success "Serviços reiniciados"

# Limpeza opcional
if [ "$KEEP_DOWNLOADS" = false ]; then
  info "Removendo arquivos de download..."
  rm -f "$DOWNLOAD_DIR/$GLPI_TGZ" || warn "Não foi possível remover $GLPI_TGZ"
fi

# Resumo final
echo
success "Instalação concluída com sucesso!"
echo
echo "Acesse: http://$DOMAIN (ou http://IP_DO_SERVIDOR)"
echo "Banco: $GLPI_DB"
echo "Usuário: $GLPI_USER"
echo "Senha: $GLPI_PASS"
echo
echo "Próximos passos:"
echo "1) Finalize a instalação pelo navegador."
echo "2) Remova a pasta de instalação: sudo rm -rf $WEB_ROOT/install"
echo "3) Execute mysql_secure_installation para melhorar a segurança do banco."
echo "4) Configure HTTPS com Certbot se usar domínio público."
echo "5) Considere firewall e Fail2Ban para endurecer o servidor."
echo

log "Instalação finalizada com sucesso."

exit 0
