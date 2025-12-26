# rCLoud
#### rudis private cloud

> Die *rCLoud* besteht aus mehreren RaspberryPi (Generation 4), die einen Docker Swarm bilden.

## prepareTheOS
Ein RaspberryPi OS - Image wird auf einen USB-Stick kopiert, der ssh-Server aktiviert und ein User (*berrypi-admin*) angelegt. Dazu gibt es das Skript *first_stage.sh*, das als root ausgeführt werden muss. Es hat eine Hilfe-Funktion (-h).

### first stage
###### copy the image
`dd bs=4M if=IMG-File of=/dev/sdX status=progress conv=fsync`

###### first_stage.sh (root)
Aufruf mit dem Benutzernamen der angelegt werden soll und dem dazugehörigen Passwort:
`sudo first_stage.sh -u berrypi-admin -m `. Mit -h wird die Hilfe angezeigt.

### second stage
Nach dem Hochfahren einer kleinen Maschine mit dem USB-Stick und dem ersten Test-Login wird zunächst der **public key** übertragen, um die Authentifizierung zu vereinfachen (und sicherer zu machen). Die IP-Adresse der Maschine muss zunächst in den *Leases* des Routers herausgefunden werden.
```bash
~$: ssh-copy-id berrypi-admin@IP.Adresse
```

###### second_stage.sh
Aufruf zur Konfiguration der kleinen Maschine mit der IP 192.168.17.152, die den Hostnamen 'pi-manager01' und die fixe IP-Adresse 192.168.7.11 bekommen soll:
`02_second_stage/second_stage.sh -z 192.168.7.152 -H pi-manager01 -n 192.168.7 -i 11`

###### sudoers
Anschließend muss der User *berrypi-admin* in die sudoers-Datei aufgenommen werden:
`sudo visudo -f /etc/sudoers.d/berrypi-admin`. Die Zeile sieht so aus: `berrypi-admin ALL=(ALL:ALL) ALL`

### update the system
```bash
~$: ansible-playbook update_systems.yml
```