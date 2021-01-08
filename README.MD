# Locales KOSMoS Tool-Repository

# Lokales KOSMoS local "startup"

Diesese Helferscript soll dazu dienen, eine Komplette KOSMoS Local Umgebung zu starten.

[Changelog](./doc/CHANGELOG.MD)  
[Todo Liste](./doc/TODO.MD)  
  

## Voraussetzungen zur Installation/Nutzung

* Linux (getestet unter Ubuntu 18.04.4 LTS und Arch rolling)
* Docker (`apt install docker-ce` bzw. `pacman -S docker`)
* Freie TCP Ports: 
    * 10002 [MQTT-Broker Dashboard](http://localhost:10002/ui)
    * 10003 [Vault UI (HTTP)](http://localhost:10003/ui)
    * 10004 [Vault UI (HTTPS Self Signed)](https://localhost:10004)
    * 10005 [Blockchain Connector Dashboard](http://localhost:10005/ui)


## Konfiguration
  
Alle Komponenten werden über Umgebungsvariablen beim Start konfiguriert.

> Zur besseren Übersicht sind Umgebungsvariablen und JSON-Objekte in separaten Dateien.

Zur [Beschreibung der BCC_CONFIG.json](https://github.com/kosmos-industrie40/kosmos-local-blockchain-connector/blob/master/docs/BCC_CONFIG.MD)
Zur [Beschreibung der BCC_PAYLOAD.json](https://github.com/kosmos-industrie40/kosmos-local-blockchain-connector/blob/master/docs/BCC_PAYLOAD.MD)

## Installation und Start der Services

Der Start der Komponenten erfolgt über ein Shell-Script.

```bash
git clone https://github.com/kosmos-industrie40/kosmos-local-startup.git
cd kosmos-local-startup
# TODO - Alle Images bauen und Taggen, sonst geht nichts ohne private Zugangsdaten!
#./build_all.sh
./start_all.sh
``` 

## Credits

Dieses Repo wurde erstellt im Rahmen des BMBF Forschungsprojektes KOSMoS. Danke, BMBF!

Verwendete Software und Technologien:

* Eclipse Foundation: mosquitto
* mosquitto-go-auth Plugin: https://github.com/iegomez/mosquitto-go-auth
* HashiCorp: Vault
* OpenJS Foundation: Node-RED
* alpine Linux: https://alpinelinux.org/
* Docker & Compose: https://www.docker.com

## Author

Andreas Clausnizer (C) 2020, Ondics GmbH