#!/bin/bash

# second_stage
# -----------
# Konfiguration nach dem ersten boot-Vorgang
#
# Der RaspberryPi ist das erste Mal hochgefahren; die IP-Adresse muss bekannt sein.
# Es erfolgen die Hardware-Konfigurationen, die ssh - Konfiguration (public key),
# die Konfiguration von hostname und fixer IP-Adresse (systemd-networkd).
#
# Voraussetzung:
# ssh - Verbindung zu den Maschinen ist mit public key und dem Benutzer berrypi-admin möglich.


# --- Standartwerte
HOST="raspberrypi"
NETZWERK="192.168.99"
HOST_ID="99"
IP=""
ZIEL=""
SSH_USER="berrypi-admin"

# Anzeige der Hilfe
# '$0' -> Pfad des Scripts
_help() {
  echo "Verwendung: $0 -z <Ziel> -H <Hostname> -n <Netzwerk> -i <Host_ID> [-h <Hilfe>]"
  echo ""
  echo "Optionen:"
  echo "  -z <Ziel>  Die IP-Adresse des Rechners, der konfiguriert werden soll (Pflicht)" 
  echo "  -H <Hostname> Der Hostname (Pflicht, Standard: ${HOST})"
  echo "  -n <Netzwerk> Das Netzwerk, z. B. 192.168.17 (Pflicht, Standard: ${NETZWERK})"
  echo "  -i <Host_ID>  Die Host-ID, z.B. 21; wird mit dem Netzwerk zur IP-Adresse 192.168.17.21 (Pflicht, Standard: ${HOST_ID})"
  echo "  -h            Diese Hilfe anzeigen."
  echo ""
  exit 0
}


# --- Kommandozeilen Parameter parsen
while getopts "z:H:n:i:h" opt; do
    case ${opt} in
        z)
            ZIEL="${OPTARG}"
            ;;
        H)
            HOST="${OPTARG}"
            ;;
        n)
            NETZWERK="${OPTARG}"
            ;;
        i)
            HOST_ID="${OPTARG}"
            ;;
        h)
            _help
            ;;
        \?) # Ungültige Option
            echo ""
            echo "!!! ungültige Option -$OPTARG." >&2
            echo ""
            _help
            ;;
    esac
done

# --- Parameter validieren
if [ -z "$ZIEL" ] || [ -z "$HOST" ] || [ -z "$NETZWERK" ] || [ -z "$HOST_ID" ]; then
    echo ""
    echo "!!! Alle Parameter (-z, -H, -n, -i) sind erforderlich" >&2
    echo ""
    _help
fi

# IP-Adresse konstruieren
IP="${NETZWERK}.${HOST_ID}"

# SSH Verbindungstest
echo "... -> teste SSH-Verbindung zu $SSH_USER@$ZIEL"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$SSH_USER@$ZIEL" true 2>/dev/null; then
    echo ""
    echo "!!! SSH-Verbindung zu $ZIEL fehlgeschlagen" >&2
    echo "!!! Bitte prüfen Sie:"
    echo "!!!   - Ist der Raspberry Pi online?"
    echo "!!!   - Ist die IP-Adresse korrekt?"
    echo "!!!   - Ist der SSH public key hinterlegt?"
    echo ""
    exit 1
fi
echo "... -> SSH-Verbindung erfolgreich"


# ===== Hostname konfigurieren =====
echo "... -> konfiguriere Hostname auf $HOST"
if ! ssh "$SSH_USER@$ZIEL" /bin/bash <<EOF
set -e
# Hostname
# /etc/hostname
sudo sh -c "echo ${HOST} > /etc/hostname"

# /etc/hosts - Host zur localhost-Zeile hinzufügen
sudo sed -i "s/^127.0.0.1[[:space:]]\\+localhost.*/127.0.0.1 localhost $HOST/" /etc/hosts
EOF
then
    echo ""
    echo "!!! Fehler bei der Hostname-Konfiguration" >&2
    exit 1
fi



# ===== Hardware konfigurieren =====
echo "... -> konfiguriere Hardware (Audio, Bluetooth, WiFi deaktivieren)"
if ! ssh "$SSH_USER@$ZIEL" /bin/bash <<'EOF'
set -e

# Bestimme den Pfad zur config.txt
if [ -f /boot/firmware/config.txt ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    CONFIG_FILE="/boot/config.txt"
else
    echo "!!! config.txt nicht gefunden" >&2
    exit 1
fi

# Audio deaktivieren (idempotent)
if grep -q "^dtparam=audio=on" "$CONFIG_FILE"; then
    sudo sed -i '/^dtparam=audio=on/ { s/^/#/; a\dtparam=audio=off
}' "$CONFIG_FILE"
fi

# Bluetooth deaktivieren (idempotent)
if ! grep -q "^dtoverlay=disable-bt" "$CONFIG_FILE"; then
    echo "dtoverlay=disable-bt" | sudo tee -a "$CONFIG_FILE" > /dev/null
fi

# WiFi deaktivieren (idempotent)
if ! grep -q "^dtoverlay=disable-wifi" "$CONFIG_FILE"; then
    echo "dtoverlay=disable-wifi" | sudo tee -a "$CONFIG_FILE" > /dev/null
fi
EOF
then
    echo ""
    echo "!!! Fehler bei der Hardware-Konfiguration" >&2
    exit 1
fi



# ===== SSH konfigurieren =====
echo "... -> konfiguriere SSH (nur Public Key Authentication)"
if ! ssh "$SSH_USER@$ZIEL" /bin/bash <<'EOF'
set -e
sudo tee /etc/ssh/sshd_config.d/99-pCloud-custom.conf > /dev/null <<EOT
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
EOT
sudo chmod 644 /etc/ssh/sshd_config.d/99-pCloud-custom.conf
EOF
then
    echo ""
    echo "!!! Fehler bei der SSH-Konfiguration" >&2
    exit 1
fi



# ===== Statische IP-Adresse konfigurieren =====
echo "... -> konfiguriere statische IP-Adresse ${IP}"
if ! ssh "$SSH_USER@$ZIEL" /bin/bash <<EOF
set -e
# systemd-networkd
sudo tee /etc/systemd/network/20-static-eth0.network > /dev/null <<EOT
[Match]
Name=eth0

[Network]
DHCP=no
Gateway=${NETZWERK}.1
DNS=${NETZWERK}.1

[Address]
Address=${IP}/24
EOT
EOF
then
    echo ""
    echo "!!! Fehler bei der IP-Konfiguration" >&2
    exit 1
fi

echo "... -> aktiviere systemd-networkd"
if ! ssh "$SSH_USER@$ZIEL" "sudo systemctl enable systemd-networkd"; then
    echo ""
    echo "!!! Fehler beim Aktivieren von systemd-networkd" >&2
    exit 1
fi

echo "... -> deaktiviere NetworkManager"
if ! ssh "$SSH_USER@$ZIEL" "sudo systemctl disable NetworkManager.service 2>/dev/null || true"; then
    echo ""
    echo "!!! Warnung: Fehler beim Deaktivieren von NetworkManager (möglicherweise nicht installiert)" >&2
fi

# Reboot
echo ""
echo "✓ Konfiguration abgeschlossen!"
echo "... -> starte Raspberry Pi neu"
echo "... -> neue IP-Adresse nach Neustart: ${IP}"
ssh "$SSH_USER@$ZIEL" "sudo reboot" || true

echo ""
echo "✓ Fertig! Der Raspberry Pi wird neu gestartet."
