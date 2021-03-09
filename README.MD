# Start der KOSMoS-local Umgebung

Mit diesem Skript kann die komplette KOSMoS-local Umgebung gestartet werden. Die KOSMoS-local Umgebung läuft auf der EDGE bei einem Maschinenbetreiber, der an KOSMoS-Prozessen teilnimmt.

Die KOSMoS-local Umgebung besteht aus den Komponenten

* [MQTT-Broker](https://github.com/kosmos-industrie40/kosmos-local-mqtt-broker): sichere Kommunikation (incl. Vault)
* [Blockchain-Connector](https://github.com/kosmos-industrie40/kosmos-local-blockchain-connector): Übertragung Maschinendaten an die KOSMoS-Blockchain
* [Maschinen-Daten-Simulator](https://github.com/kosmos-industrie40/kosmos-local-machine-simulator): Erzeugung von Maschinendaten zum Test der KOSMoS-Komponenten


[Changelog](./CHANGELOG.md)  
[Todo Liste](./TODO.md)  
  

## Voraussetzungen zur Installation/Nutzung

* Linux (getestet unter Ubuntu 18.04.4 LTS und Arch rolling)
* Docker (`apt install docker-ce` bzw. `pacman -S docker`)
* Freie TCP Ports: 
    * 10002 [MQTT-Broker Dashboard](http://localhost:10002/ui)
    * 10003 [Vault UI (HTTP)](http://localhost:10003/ui)
    * 10004 [Vault UI (HTTPS Self Signed)](https://localhost:10004)
    * 10005 [Blockchain Connector Dashboard](http://localhost:10005/ui)

Hinweise wichtige zur [Konfiguration des Nginx-Proxy zur Erreichbarkeit aus dem Internet](#konfiguration-nginx)

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
  
  
## Das Netzwerk in der EDGE


Um das Netzwerk der EDGE zu simulieren initialisiert das `start_all.sh` Script einen virtuellen Docker Switch (`docker network create kosmos-local`).
Alle Komponenten in der Testumgebung müssen Teil dieses Netzes sein um sich:
* mit dem MQTT Broker zu verbinden
* mit der Vault interagieren zu können

Der MQTT-Broker ist ein zentrales Element in der EDGE.

Hier die Eckdaten des aufgespannten virtuellen Netzwerks:    
* Der MQTT-Broker ist erreichbar unter `mqtt.brokers.mqtt.local.kosmos`  
* Alle MQTT-Subscriber und -Publisher müssen das DNS-Prefix bekommen: `*.clients.mqtt.local.kosmos`  
  * Dies wurde in der Vault als Rollenname für MQTT-Clients festgelegt
* Die Vault ist unter `ca.mqtt.local.kosmos`, `ca.local.kosmos` und `ca.global.kosmos` erreichbar  
  * Die DNS bezeichnungen `local` und `global` sollen dazu dienen, die Rollen der Vault als CA im jeweiligen KOSMoS Umfeld zu Simulieren


Alle Komponenten, welche mit dem MQTT-Broker komunizieren sollen, müssen sich in diesen virtuellen Switch "einstecken".
```bash
docker run
[...]
    --net kosmos-local \
[...]
```

Alle Komponenten, welche für andere Komponenten per SSL/TLS erreichbar sein müssen, brauchen (mindestens) einen DNS Namen.  
```
# Der Vault Placeholder ist zu anschaungszecken unter 3 DNS-Namen erreichbar:
docker run 
[...]
    --net-alias ca.mqtt.local.kosmos \
    --net-alias ca.local.kosmos \
    --net-alias ca.global.kosmos \
[...]
```

Dem `start_all.sh` Script können Beispiel-Services entnommen werden.


## Konfiguration Nginx

Wenn die KOSMoS-lokal Umgebung aus dem Internet oder größeren Firmennetzwerken angesprochen 
werden soll, müssen die Docker-Services per Hostname aufrufbar sein. Die IP-Adressen
müssen also mit Domainnamen verbunden werden.

Da diese auf verschiedenen Ports (10001, 10002, ...) zur Verfügung stehen, muss der
Nginx des Hosts als Proxy erweitert werden.

Zwei Schritte sind erforderlich:

1. Der Nginx auf dem Host muss als Reverse Proxy konfiguriert werden
2. Die Namens-IP-Adress-Umsetzung wird durch `nip.io` erledigt

Beispiel: 

* Es sollen die Ports 10002 bis 10005 der gestarteten Services aus dem Internet erreichbar sein.
* Die aus dem Internet-erreichbare Adresse lautet: 1.2.3.4

Schritt 1:

Die Datei /etc/nginx/sites-enabled/default ist zu erweitern:

server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;

        server_name _;
        location / {

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        if ($host = 'port10001.1.2.3.4.nip.io') {
            proxy_pass http://localhost:10001;
        }
        if ($host = 'port10002.1.2.3.4.nip.io') {
            proxy_pass http://localhost:10002;
        }
        if ($host = 'port10003.1.2.3.4.nip.io') {
            proxy_pass http://localhost:10003;
        }
        if ($host = 'port10004.1.2.3.4.nip.io') {
            proxy_pass http://localhost:10004;
        }
        if ($host = 'port10005.1.2.3.4.nip.io') {
            proxy_pass http://localhost:10005;
        }
    }
}

Dann Nginx neu starten:
   
    $ sudo service nginx restart

Schritt 2:

Der Aufruf aus dem Browser kann nun mit folgenden Adressen erfolgen:

http://port10001.1.2.3.4.nip.io/
http://port10002.1.2.3.4.nip.io/
http://port10003.1.2.3.4.nip.io/
http://port10004.1.2.3.4.nip.io/
http://port10005.1.2.3.4.nip.io/

Die Antworten kommen dann von den entsprechenden Docker-Containern. Voilà!

## Credits

Dieses Repo wurde erstellt im Rahmen des BMBF Forschungsprojektes KOSMoS. Danke, BMBF!

Im Forschungsprojekt KOSMoS werden neue Geschäftsmodelle für den Maschinenbau auf Basis von sicheren infrastrukturen (z.B. Blockchain) entwickelt. Das Projekt (2019-2022) wird vom BMBF gefördert. Weitere Informationen unter https://www.kosmos-bmbf.de

Verwendete Software und Technologien:

* Eclipse Foundation: mosquitto
* mosquitto-go-auth Plugin: https://github.com/iegomez/mosquitto-go-auth
* HashiCorp: Vault
* OpenJS Foundation: Node-RED
* alpine Linux: https://alpinelinux.org/
* Docker & Compose: https://www.docker.com

## Author

(C) 2020, Ondics GmbH
