#!/bin/bash

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <IP | IP-Range> [more IPs/Ranges...]"
  echo "Examples:"
  echo "  $0 192.168.1.10"
  echo "  $0 192.168.1.[11-13]"
  echo "  $0 192.168.1.[1-3,7,10-12]"
  exit 1
fi

ping_ip() {
  local ip="$1"
  ping -c 1 -W 1 "$ip" &>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "✅ $ip erreichbar"
  else
    echo "❌ $ip nicht erreichbar"
  fi
}

for TARGET in "$@"; do

  # Prüfen auf Range-Notation
  if [[ "$TARGET" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.\[([0-9,\-]+)\]$ ]]; then
    BASE_IP="${BASH_REMATCH[1]}"
    RANGE_PART="${BASH_REMATCH[2]}"

    # Kommagetrennte Segmente aufteilen
    IFS=',' read -ra SEGMENTS <<< "$RANGE_PART"

    for SEG in "${SEGMENTS[@]}"; do
      if [[ "$SEG" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        START="${BASH_REMATCH[1]}"
        END="${BASH_REMATCH[2]}"
        for ((i=START; i<=END; i++)); do
          ping_ip "$BASE_IP.$i"
        done
      else
        ping_ip "$BASE_IP.$SEG"
      fi
    done

  else
    # Einzelne IP
    ping_ip "$TARGET"
  fi
done
