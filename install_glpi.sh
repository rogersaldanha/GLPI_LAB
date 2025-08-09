#!/usr/bin/env bash
#
# Instalação automatizada e segura do GLPI no Ubuntu 22.04
# Autor: Seu Nome (ou deixar em branco)
# Versão: 2.0
#
# Melhorias:
# - Geração de senha aleatória e segura para o MariaDB.
# - Uso de "here document" para comandos SQL, evitando exposição de senha.
# - Detecção estrita da versão e socket do PHP-FPM.
# - Manipulação segura de arquivos de configuração.
# - Logs e mensagens de status aprimorados.
# - Credenciais salvas em arquivo seguro em /root/.

# ————— CONFIGURAÇÕES —————
GLPI_DB="glpi"
GLPI_USER="glpiuser"
GLPI_VERSION="10.0.15"
DOMAIN="localhost"                 # Substitua pelo seu IP ou domínio
WEB_ROOT="/var/www/glpi"
GLPI_PUBLIC_DIR="$WEB_ROOT/public"
GLPI_FILES_DIR="/var/lib/glpi/files"
LOGFILE="/var/log/install_glpi.log"
CREDENTIALS_FILE="/root/glpi_credentials.txt"
PHP_VERSION="8.1"                  # Versão do PHP a ser usada
DOWNLOAD_DIR="/tmp"
KEEP_DOWNLOADS=false

# ————— CORES PARA MENSAGENS —————
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# ————— FUNÇÕES AUXILIARES —————
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  # Garante que o log seja escrito como root
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
  echo -e "${RED}Abortando a instalação.${NC}"
  exit 1
}

# Captura interrupções (Ctrl+C) e finaliza de forma limpa
trap 'fail "Execução interrompida pelo usuário."' INT TERM

# ————— INÍCIO DA EXECUÇÃO —————

echo
info "Iniciando instalação segura do GLPI. Log em: $LOGFILE"
echo

# Verificar execução como root
if [ "$(id -u)" -ne 0 ]; then
  fail "Este script precisa ser executado com privilégios de root. Use 'sudo bash $0'."
fi

# Verificar existência do diretório principal do GLPI
if [ -d "$WEB_ROOT" ]; then
  warn "O diretório de instalação $WEB_ROOT já existe."
  read -p "Deseja remover o diretório existente e continuar? (s/N): " resp
  if [[ "$resp" =~ ^[sS]([iI][mM])?$ ]]; then
    info "Removendo diretório antigo $WEB_ROOT..."
    rm -rf "$WEB_ROOT" || fail "Não foi possível remover $WEB_ROOT."
    success "Diretório antigo removido."
  else
    fail "Instalação abortada pelo usuário."
  fi
fi

# Atualizar sistema
info "Atualizando os pacotes do sistema..."
apt update -y >/dev/null 2>&1 || fail "Falha ao executar 'apt update'."
apt upgrade -y >/dev/null 2>&1 || fail "Falha ao executar 'apt upgrade'."
success "Sistema atualizado."

# Instalar pacotes necessários
info "Instalando Nginx, MariaDB, PHP ${PHP_VERSION} e extensões..."
apt install -y nginx mariadb-server mariadb-client \
php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-mysql \
php${PHP_VERSION}-gd php${PHP_VERSION}-imap php${PHP_VERSION}-ldap php${PHP_VERSION}-apcu \
php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring \
php${PHP_VERSION}-xml php${PHP_VERSION}-bcmath php${PHP_VERSION}-intl \
unzip wget php${PHP_VERSION}-bz2 php${PHP_VERSION}-zip openssl || fail "Falha na instalação dos pacotes base."
success "Pacotes essenciais instalados."

# Ativar e iniciar serviços
info "Iniciando e habilitando serviços Nginx e MariaDB..."
systemctl enable --now nginx mariadb || fail "Erro ao iniciar/habilitar Nginx ou MariaDB."
success "Serviços Nginx e MariaDB ativos e habilitados."

# Verificar e iniciar PHP-FPM
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
info "Verificando o serviço $PHP_FPM_SERVICE..."
if ! systemctl is-active --quiet "$PHP_FPM_SERVICE"; then
    warn "Serviço $PHP_FPM_SERVICE não está ativo. Tentando iniciar..."
    systemctl enable --now "$PHP_FPM_SERVICE" || fail "Não foi possível iniciar $PHP_FPM_SERVICE."
fi
success "Serviço $PHP_FPM_SERVICE ativo e habilitado."

# Detectar socket PHP-FPM de forma segura
info "Detectando socket do PHP-FPM..."
PHP_SOCKET="/var/run/php/php${PHP_VERSION}-fpm.sock"
if [ ! -S "$PHP_SOCKET" ]; then
  fail "Socket PHP-FPM não encontrado em $PHP_SOCKET. Verifique se a versão ${PHP_VERSION} está correta e o serviço ativo."
fi
success "Socket PHP-FPM detectado: $PHP_SOCKET"

# Gerar senha segura para o banco de dados
info "Gerando senha segura para o usuário do banco de dados..."
GLPI_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
success "Senha gerada com sucesso."

# Criar banco e usuário no MariaDB de forma segura
info "Criando banco de dados e usuário no MariaDB..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${GLPI_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${GLPI_USER}'@'localhost' IDENTIFIED BY '${GLPI_PASS}';
GRANT ALL PRIVILEGES ON \`${GLPI_DB}\`.* TO '${GLPI_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

if [ $? -ne 0 ]; then
  fail "Falha ao configurar o banco de dados. Verifique os logs do MariaDB."
fi
success "Banco de dados '${GLPI_DB}' e usuário '${GLPI_USER}' criados."

# Salvar credenciais em arquivo seguro
info "Salvando credenciais em arquivo seguro..."
cat > "$CREDENTIALS_FILE" <<EOF
# Credenciais de acesso ao banco de dados do GLPI
# Geradas em: $(timestamp)
# CUIDADO: Este arquivo contém informações sensíveis.

DB_DATABASE="${GLPI_DB}"
DB_USERNAME="${GLPI_USER}"
DB_PASSWORD="${GLPI_PASS}"
EOF
chmod 600 "$CREDENTIALS_FILE"
success "Credenciais salvas em $CREDENTIALS_FILE (acesso restrito ao root)."

# Baixar e extrair GLPI
info "Baixando GLPI versão ${GLPI_VERSION}..."
cd "$DOWNLOAD_DIR" || fail "Não foi possível acessar o diretório de download $DOWNLOAD_DIR."
GLPI_TGZ="glpi-${GLPI_VERSION}.tgz"
GLPI_URL="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/${GLPI_TGZ}"

wget -q --show-progress "$GLPI_URL" -O "$GLPI_TGZ" || fail "Download do GLPI falhou: $GLPI_URL"
success "Download do GLPI concluído."

info "Extraindo e movendo GLPI para $WEB_ROOT..."
tar -xzf "$GLPI_TGZ" || fail "Erro ao descompactar $GLPI_TGZ."
mv glpi "$WEB_ROOT" || fail "Erro ao mover os arquivos do GLPI para $WEB_ROOT."
success "GLPI extraído e movido."

# Mover diretórios de dados para fora da raiz web por segurança
info "Movendo diretórios de dados ('files', 'config', 'marketplace') para locais seguros..."
mkdir -p "$GLPI_FILES_DIR" "/etc/glpi" "/var/lib/glpi/marketplace"
mv "$WEB_ROOT/files" "$GLPI_FILES_DIR/_tmp" && mv "$GLPI_FILES_DIR/_tmp"/* "$GLPI_FILES_DIR/" && rm -rf "$WEB_ROOT/files" "$GLPI_FILES_DIR/_tmp"
mv "$WEB_ROOT/config" /etc/glpi/
mv "$WEB_ROOT/marketplace" /var/lib/glpi/
success "Diretórios de dados movidos com segurança."

# Criar links simbólicos para os diretórios movidos
ln -s "/etc/glpi/config" "$WEB_ROOT/config"
ln -s "$GLPI_FILES_DIR" "$WEB_ROOT/files"
ln -s "/var/lib/glpi/marketplace" "$WEB_ROOT/marketplace"
success "Links simbólicos criados."

# Ajustar permissões
info "Ajustando permissões para www-data..."
chown -R www-data:www-data "$WEB_ROOT" "/etc/glpi" "$GLPI_FILES_DIR" "/var/lib/glpi"
find "$WEB_ROOT" -type d -exec chmod 755 {} \;
find "$WEB_ROOT" -type f -exec chmod 644 {} \;
success "Permissões de arquivos e diretórios ajustadas."

# Configurar Nginx
info "Criando configuração do Nginx para o GLPI..."
cat > "/etc/nginx/sites-available/glpi" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $GLPI_PUBLIC_DIR;
    index index.php;

    access_log /var/log/nginx/glpi_access.log;
    error_log /var/log/nginx/glpi_error.log;

    # Regra principal para direcionar tudo para o index.php
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # Processamento de arquivos PHP
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCKET;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # Negar acesso a diretórios sensíveis
    location ~ ^/(config|files|locales|install|marketplace|scripts) {
        deny all;
    }

    # Otimizar cache para arquivos estáticos
    location ~* \.(?:ico|css|js|gif|jpe?g|png|woff2?|eot|ttf|svg)\$ {
        expires 6M;
        access_log off;
        add_header Pragma public;
        add_header Cache-Control "public";
    }
}
EOF
success "Arquivo de configuração do Nginx criado."

# Ativar site e testar configuração
info "Ativando o site do GLPI no Nginx..."
ln -sf "/etc/nginx/sites-available/glpi" "/etc/nginx/sites-enabled/glpi"
rm -f /etc/nginx/sites-enabled/default # Remove o site padrão para evitar conflitos

info "Testando a configuração do Nginx..."
nginx -t || fail "Configuração do Nginx inválida. Verifique os logs de erro."
success "Configuração do Nginx é válida."

# Reiniciar serviços para aplicar as mudanças
info "Reiniciando Nginx e PHP-FPM..."
systemctl restart nginx "$PHP_FPM_SERVICE" || fail "Falha ao reiniciar Nginx ou $PHP_FPM_SERVICE."
success "Serviços reiniciados."

# Limpeza opcional
if [ "$KEEP_DOWNLOADS" = false ]; then
  info "Removendo arquivos de download..."
  rm -f "$DOWNLOAD_DIR/$GLPI_TGZ"
fi

# ————— RESUMO FINAL —————
echo
success "Instalação do GLPI concluída com sucesso!"
echo
echo "Acesse o GLPI em: http://$DOMAIN"
echo
echo "As credenciais do banco de dados foram salvas em:"
echo -e "${YELLOW}$CREDENTIALS_FILE${NC}"
echo "Use essas credenciais durante a instalação via navegador."
echo
echo -e "${YELLOW}AÇÕES IMPORTANTES PÓS-INSTALAÇÃO:${NC}"
echo "1) Finalize a configuração pelo navegador."
echo "2) Após a instalação web, remova o arquivo de instalação por segurança:"
echo -e "   ${RED}sudo rm -f ${WEB_ROOT}/public/install/install.php${NC}"
echo "3) Execute 'sudo mysql_secure_installation' para fortalecer a segurança do MariaDB."
echo "4) Configure HTTPS com Certbot (Let's Encrypt) se estiver usando um domínio público."
echo "5) Implemente um firewall (ex: ufw) e considere o Fail2Ban para proteção adicional."
echo

log "Instalação finalizada com sucesso."
exit 0