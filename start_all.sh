#!/bin/bash
 
set -e 
# Dieses bash Script soll demonstrieren wie die Komponenten ohne docker-compose parametrisiert und gestartet werden können
#
# Voraussetungen:
# * docker
# * alle KOSMoS-Local Komponenten sind in einem Netz/VLAN
# * alle KOSMoS Komponenten welche SSL/TLS benötigen haben einen DNS-Name
# * auflößung von diesen DNS Namen in IP-Adressen funktioniert
# * Entweder:
#   * Login in der Registry: harbor.kosmos.idcp.inovex.io (docker login harbor.kosmos.idcp.inovex.io)
#   * Docker Images lokal bauen (build_images.sh)
#
# Gestartet wird:
# * Test-Vault
# * MQTT-Broker

# Einschränkungen
# 
# Da in der Test-Umgebung alles auf einem Rechner läuft wird statt dem KOSMoS-Local Netz ein Docker VSwitch verwendet.
# Dieses kann aus Netzwerk sicht als ein eigenes getrenntes Netz betrachtet werden.

#region Umgebung aufräumen
docker_stop_remove_image() {
    echo "stop and remove container: $1"
    while docker ps -a | grep "$1" > /dev/null
    do
        echo -n "."
        docker stop $1 > /dev/null
        echo -n "."
        docker rm -f $1 > /dev/null
        sleep 1
    done
}

echo -n "Umgebung aufräumen"
docker_stop_remove_image vault-placeholder &&\
docker_stop_remove_image mqtt-broker &&\
docker_stop_remove_image mqtt-dashboard &&\
docker_stop_remove_image blockchain-connector &&\
docker_stop_remove_image machine-simulator &&\
docker network ls | grep kosmos-local  > /dev/null && docker network rm kosmos-local > /dev/null &&\
echo " [OK]" ||\
echo " [FAIL]"
#endregion

#region Umgebung vorbereiten
# Environmentvariablen laden
. config.env

echo -n "Docker Netzwerk für kosmos-local anlegen..."
docker network create kosmos-local > /dev/null && echo " [OK]"
#endregion

#region Vault "Platzhalter" starten - Container: vault-placeholder
echo -n "Vault-Platzhalter starten..."
docker run \
    -d \
    --net kosmos-local \
    --net-alias ${KOSMOS_GLOBAL_CA_FQDN} --net-alias ${KOSMOS_LOCAL_CA_FQDN} --net-alias ${KOSMOS_LOCAL_MQTT_CA_FQDN} \
    --name vault-placeholder \
    -e TZ=Europe/Berlin \
    -e VAULT_ADDR \
    -e VAULT_API_ADDR \
    -e VAULT_ADDRESS \
    -e KOSMOS_GLOBAL_CA_FQDN \
    -e KOSMOS_GLOBAL_PKI_PATH \
    -e KOSMOS_LOCAL_CA_FQDN \
    -e KOSMOS_LOCAL_PKI_PATH \
    -e KOSMOS_LOCAL_MQTT_CA_FQDN \
    -e KOSMOS_LOCAL_MQTT_PKI_PATH \
    -e KOSMOS_LOCAL_MQTT_CLIENT_ROLE_FQDN \
    -e KOSMOS_LOCAL_MQTT_CLIENT_ROLE_PATH \
    -e KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN \
    -e KOSMOS_LOCAL_MQTT_BROKER_ROLE_PATH \
    --cap-add=IPC_LOCK \
    -p 10003:8200 \
    -p 10004:8201 \
    harbor.kosmos.idcp.inovex.io/ondics/vault-placeholder:0.3 > /dev/null && echo " [OK]"
#endregion

#region Vault-Token für PKI aus der Vault holen
echo -n "Warte auf Vault Token"
get_tocken(){
    export VAULT_TOKEN=`curl -s --cacert KOSMoS_GLOBAL_ROOT_CA.crt --request POST --data '{"password": "admin"}' --resolve ca.mqtt.local.kosmos:10004:127.0.0.1 https://ca.mqtt.local.kosmos:10004/v1/auth/userpass/login/admin | jq -r .auth.client_token`
    if [[ $VAULT_TOKEN == "s."* ]]; then
        return 1
    else
        return 0
    fi
}

while get_tocken; do
    echo -n "."
    sleep 1
done

echo " [OK] - Token: $VAULT_TOKEN"
#endregion

#region MQTT-Broker und -Dashboard starten - Container: mqtt-broker, mqtt-dashboard
echo -n "MQTT-Broker starten..."
docker run \
    -d \
    --net kosmos-local \
    --domainname=${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    --hostname=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME} \
    --net-alias ${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    --name mqtt-broker \
    -e TZ=Europe/Berlin \
    -e VAULT_TOKEN=${VAULT_TOKEN} \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_BROKER_ROLE_PATH} \
    -e ALLOW_TLS=true \
    harbor.kosmos.idcp.inovex.io/ondics/mqtt-broker:rc3 > /dev/null && echo " [OK]"

echo -n "MQTT-Dashboard starten..."
docker run \
    -d \
    --net kosmos-local \
    --domainname=${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_FQDN} \
    --hostname=mqtt-dashboard \
    --name mqtt-dashboard \
    -e TZ=Europe/Berlin \
    -e VAULT_TOKEN=${VAULT_TOKEN} \
    -e USE_TLS=true \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_PATH} \
    -e MQTT_BROKER_FQDN=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    -p 10002:1880 \
    harbor.kosmos.idcp.inovex.io/ondics/mqtt-dashboard:0.3 > /dev/null && echo " [OK]"
#endregion


#region Blockchain Connector starten - Container: blockchain-connector
echo -n "Blockchain-Connector starten..."
docker run \
    -d \
    --net kosmos-local \
    --domainname=${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_FQDN} \
    --hostname=bockchain-connector \
    --name blockchain-connector \
    -e TZ=Europe/Berlin \
    -e VAULT_TOKEN=${VAULT_TOKEN} \
    -e USE_TLS=true \
    -e USE_STANDALONE_NO_MQTT=false \
    -e BCC_CONFIG="$(cat BCC_CONFIG.json)" \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_PATH} \
    -e MQTT_BROKER_FQDN=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    -p 10005:1880 \
    harbor.kosmos.idcp.inovex.io/ondics/blockchain-connector:0.2.5 > /dev/null && echo " [OK]"
#endregion

echo "Maschinen-Simulator starten..."
echo -e "\e[31m###############################################################################\e[39m"
echo -e "\e[31m### Achtung: Der Blockchain Connector sendet diese Daten in die Blockchain. ###\e[39m"
echo -e "\e[31m###############################################################################\e[39m"
echo ""
for i in {30..01}
do
echo -e "\e[1A\e[KStartet in [$i] sek. - Abbrechen mit STRG-C."
sleep 1
done

#region Maschinen-Simulator starten - Container: machine-simulator
#
# Achtung! Gesendete Daten landen in der Blockchain!
#
docker run \
    -d \
    --net kosmos-local \
    --domainname=${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_FQDN} \
    --hostname=machine-a0b1c2d3 \
    --name machine-simulator \
    -e PAYLOAD="$(cat MS_BCC_PAYLOAD.json)" \
    -e VAULT_TOKEN=${VAULT_TOKEN} \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_PATH} \
    -e MQTT_BROKER_FQDN=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    -e TOPIC='kosmos/machine-data/9d82699b-373a-4b2a-8925-f7bfacb618a4/Sensor/tbd/Update' \
    harbor.kosmos.idcp.inovex.io/ondics/machine-simulator:rc2 && echo " [OK]"
#endregion
