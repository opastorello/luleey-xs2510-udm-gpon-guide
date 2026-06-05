#!/bin/sh
# ============================================================================
# 10-xpon-stick.sh  —  vai em /data/on_boot.d/ na UDM
# (requer o mecanismo on-boot-script / unifios-utilities instalado)
#
# Garante que a gerencia do stick (http://<IP-DA-UDM>:8888) fique SEMPRE no ar,
# inclusive apos updates do UniFi OS que limpam o /etc. Re-cria o service de
# keepalive se ele sumiu e o ativa.
# ============================================================================

# Re-cria o service systemd caso o /etc tenha sido limpo (ex: update do UniFi OS)
if [ ! -f /etc/systemd/system/xpon-stick-keepalive.service ]; then
  cat > /etc/systemd/system/xpon-stick-keepalive.service <<'UNIT'
[Unit]
Description=XPON stick mgmt keepalive (eth9 192.168.1.2 + :8888 DNAT)
After=network-online.target
[Service]
Type=simple
ExecStart=/data/xpon-stick-keepalive.sh
Restart=always
RestartSec=15
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload 2>/dev/null
fi

systemctl enable --now xpon-stick-keepalive.service 2>/dev/null

# Aplica a rota uma vez de imediato (o keepalive mantem dai pra frente)
ip addr add 192.168.1.2/24 dev eth9 2>/dev/null
