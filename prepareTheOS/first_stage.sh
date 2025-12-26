#!/bin/bash

# first_stage
# -----------
# Konfiguration vor dem ersten boot-Vorgang (als root)
#
# Die ersten Schritte erfolgen auf der 'boot' - Partition des 
# Speichermedium's mit dem OS-Image, die gemounted sein muss:
# ~$: sudo mount /dev/sdXY /mnt
# 


# Anzeige der Hilfe
# '$0' -> Pfad des Scripts
# 'basename' -> Dateiname
_help() {
  echo "Verwendung: $0 -u <Benutzername> [-m <Mountpoint>]"
  echo ""
  echo "Optionen:"
  echo "  -u <Benutzername>  Der anzulegende Benutzername. (Pflicht)"
  echo "  -m <Mountpoint>    Der Einhängepunkt der Boot-Partition. (Optional, Standard: $MOUNT_POINT)"
  echo "  -h                 Diese Hilfe anzeigen."
  echo ""
  echo "Hinweis:"
  echo " - Das Passwort wird beim Ausführen des Skripts sicher abgefragt."
  echo ""
  echo "Voraussetzungen:"
  echo " - openssl muss installiert sein"
  echo " - die boot-Partition muss auf dem angegebenen Mountpoint eingehängt sein"
  echo ""
  echo "Ablauf:"
  echo "Das Skript legt die Datei 'ssh' an, damit beim boot-Vorgang der ssh-Server startet, "
  echo "generiert ein SHA-512 Passwort-Hash und erstellt die 'userconf'-Datei"
  echo "auf der gemounteten Raspberry Pi Boot-Partition, um den Benutzer beim ersten Boot anzulegen."
  exit 0
}


# --- Standartwerte
USERNAME=""
PASSWORD=""
MOUNT_POINT="/mnt"
USERCONF_FILE="${MOUNT_POINT}/userconf"


# --- openssl installiert ?
if ! command -v openssl &> /dev/null
then
    echo ""
    echo "!!! der Befehl 'openssl' wurde nicht gefunden." >&2
    echo ""
    _help
fi


# --- Kommandozeilen Parameter parsen
while getopts "u:m:h" opt; do
    case ${opt} in
        u)
            USERNAME="${OPTARG}"
            ;;
        m)
            MOUNT_POINT="${OPTARG}"
            USERCONF_FILE="${MOUNT_POINT}/userconf"
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
if [ -z "$USERNAME" ]; then
    echo ""
    echo "!!! Benutzername ist ein Pflichtparameter" >&2
    echo ""
    _help
fi

# ist die Partition gemountet ?
if ! mountpoint -q "$MOUNT_POINT"; then
    echo ""
    echo "!!! es ist nichts unter $MOUNT_POINT eingehängt, bitte die benötigte Partition mit"
    echo "~$: sudo mount /dev/sdXY $MOUNT_POINT"
    echo "einhängen."
    echo ""
    exit 1
fi


# ssh - Server beim booten starten
echo "... -> erstelle die Datei ssh"
if ! sudo touch "${MOUNT_POINT}/ssh"; then
    echo ""
    echo "!!! Fehler beim Erstellen der SSH-Datei" >&2
    exit 1
fi

# Benutzer anlegen
echo ""
echo "Bitte geben Sie das Passwort für den Benutzer ${USERNAME} ein:"
read -s -p "Passwort: " PASSWORD
echo ""
read -s -p "Passwort wiederholen: " PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo ""
    echo "!!! Die Passwörter stimmen nicht überein" >&2
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo ""
    echo "!!! Passwort darf nicht leer sein" >&2
    exit 1
fi

# Passwort hashen (mit SHA-512, wie von openssl passwd -6 gefordert)
echo "... -> generiere SHA-512 Hash für den Benutzer ${USERNAME} ..."
PASSWORD_HASH=$(echo "${PASSWORD}" | openssl passwd -6 -stdin)

if [ -z "$PASSWORD_HASH" ]; then
    echo ""
    echo "!!! Fehler beim Generieren des Passwort-Hashes" >&2
    exit 1
fi

# Inhalt für die userconf-Datei erstellen (Format: username:hash)
USERCONF_CONTENT="${USERNAME}:${PASSWORD_HASH}"


# userconf-Datei schreiben
echo "... -> schreibe den Benutzer-Eintrag in ${USERCONF_FILE}..."
if ! echo "${USERCONF_CONTENT}" > "${USERCONF_FILE}"; then
    echo ""
    echo "!!! Fehler beim Schreiben der userconf-Datei" >&2
    exit 1
fi

echo "... -> Konfiguration erfolgreich abgeschlossen"

# Partition aushängen
echo "... -> hänge ${MOUNT_POINT} aus"
if ! sudo umount "${MOUNT_POINT}"; then
    echo ""
    echo "!!! Warnung: Fehler beim Aushängen von ${MOUNT_POINT}" >&2
    echo "!!! Bitte manuell aushängen mit: sudo umount ${MOUNT_POINT}" >&2
    exit 1
fi

echo ""
echo "✓ Fertig! Die Boot-Partition wurde konfiguriert und ausgehängt."

