#!/bin/bash

# Dieses bash Script soll demonstrieren wie die Komponenten ohne docker-compose parametrisiert und gestartet werden können
#
# Voraussetungen:
# * docker
# * alle KOSMoS-Local Komponenten sind in einem Netz/VLAN
# * alle KOSMoS Komponenten welche SSL/TLS benötigen haben einen DNS-Name
# * auflößung von diesen DNS Namen in IP-Adressen funktioniert
# * Login in der Registry: harbor.kosmos.idcp.inovex.io (docker login harbor.kosmos.idcp.inovex.io)
#
# Gestartet wird:
# * Test-Vault
# * MQTT-Broker

# Einschränkungen
# 
# Da in der Test-Umgebung alles auf einem Rechner läuft wird statt dem KOSMoS-Local Netz ein Docker VSwitch verwendet.
# Dieses kann aus Netzwerk sicht als ein eigenes getrenntes Netz betrachtet werden.

#region Erstmal umgebung aufräumen
docker_stop_remove_image() {
    while docker ps -a | grep "harbor.kosmos.idcp.inovex.io/ondics/$1"
    do
        docker rm -f $1
        sleep 1
    done
}

docker_stop_remove_image vault-placeholder
docker_stop_remove_image mqtt-broker
docker_stop_remove_image mqtt-dashboard
docker_stop_remove_image machine-simulator
docker_stop_remove_image blockchain-connector

docker network ls | grep kosmos-local && docker network rm kosmos-local
#endregion

# Environmentvariablen laden
. config.env

# Docker Netzwerk für kosmos-local anlegen
docker network create kosmos-local



#region Vault "Platzhalter" starten - vault-placeholder
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
    harbor.kosmos.idcp.inovex.io/ondics/vault-placeholder:0.3
#endregion

#region TOKEN für PKI aus der Vault laden
echo -n "Warte auf Vault Token..."

get_tocken(){
    export VAULT_TOKEN=`curl -s --cacert KOSMoS_GLOBAL_ROOT_CA.crt --request POST --data '{"password": "admin"}' --resolve ca.mqtt.local.kosmos:10004:127.0.0.1 https://ca.mqtt.local.kosmos:10004/v1/auth/userpass/login/admin | jq -r .auth.client_token`
    if [[ $VAULT_TOKEN == "s."* ]]; then
        return 1
    else
        return 0
    fi
}

while get_tocken; do
    sleep 5      
done

echo OK - $VAULT_TOKEN
#endregion

# MQTT-Broker starten - mqtt-broker
docker run \
    -d \
    --net kosmos-local \
    --net-alias ${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    --name mqtt-broker \
    -e TZ=Europe/Berlin \
    -e VAULT_TOKEN=${VAULT_TOKEN} \
    -e MY_CA_FQDN=${KOSMOS_LOCAL_MQTT_CA_FQDN} \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_BROKER_ROLE_PATH} \
    -e MY_FQDN=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    -e KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME \
    -e ALLOW_TLS=true \
    harbor.kosmos.idcp.inovex.io/ondics/mqtt-broker:rc2

# MQTT-Dasboard starten - mqtt-dashboard
docker run \
    -d \
    --net kosmos-local \
    --name mqtt-dashboard \
    -e TZ=Europe/Berlin \
    -e VAULT_TOKEN=${VAULT_TOKEN} \
    -e USE_TLS=true \
    -e MY_CA_FQDN=${KOSMOS_LOCAL_MQTT_CA_FQDN} \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_PATH} \
    -e MY_DN=${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_FQDN} \
    -e MQTT_BROKER_FQDN=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    -p 10002:1880 \
    harbor.kosmos.idcp.inovex.io/ondics/mqtt-dashboard:0.2

exit 0
# TODO: Test other components


# Blockchain Connector starten - blockchain-connector
docker run \
    -d \
    --net kosmos-local \
    --name blockchain-connector \
    -e TZ=Europe/Berlin \
    -e USE_TLS=true \
    -e USE_STANDALONE_NO_MQTT=false \
    -e BCC_CONFIG='{"customerId":"ondics-8925-f7bfacb618a4","9d82699b-373a-4b2a-8925-f7bfacb618a4-prodData":{"mqtt-topic":"kosmos/machine-data/9d82699b-373a-4b2a-8925-f7bfacb618a4/Sensor/tbd/Update","blockchain":{"endpoint":"http://kosmos-2017317103.eu-central-1.elb.amazonaws.com/api/machine/9d82699b-373a-4b2a-8925-f7bfacb618a4/prodData","data-mapping":[{"column":"msg.payload.columns[0]","value":"msg.payload.data[0][0]"},{"column":"msg.payload.columns[1]","value":"msg.payload.data[1][0]"},{"column":"msg.payload.columns[2]","value":"msg.payload.data[2][0]"},{"column":"msg.payload.columns[3]","value":"msg.payload.data[3][0]"},{"column":"msg.payload.columns[4]","value":"msg.payload.data[4][0]"},{"column":"msg.payload.columns[5]","value":"msg.payload.data[5][0]"}]}}}' \
    -e MY_CA_FQDN=${KOSMOS_LOCAL_MQTT_CA_FQDN} \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_PATH} \
    -e MY_DN=${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_FQDN} \
    -e MQTT_BROKER_FQDN=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    -p 8013:1880 \
    harbor.kosmos.idcp.inovex.io/ondics/blockchain-connector:0.2.4

# 20 Sekunden warten, damit der vault-placeholder initialisieren und der BCC mit dem Broker verbinden kann. 
sleep 20

# Maschinen-Simulator starten - machine-simulator
#
# Achtung! Gesendete Daten landen in der Blockchain!
#
docker run \
    -d \
    --net kosmos-local \
    --name machine-simulator \
    -e MY_CA_FQDN=${KOSMOS_LOCAL_MQTT_CA_FQDN} \
    -e MY_PKI_URI=https://${KOSMOS_LOCAL_MQTT_CA_FQDN}:8201/v1/${KOSMOS_LOCAL_MQTT_PKI_PATH}/issue/${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_PATH} \
    -e MY_FQDN=machine-simulator.${KOSMOS_LOCAL_MQTT_CLIENT_ROLE_FQDN} \
    -e MQTT_BROKER_FQDN=${KOSMOS_LOCAL_MQTT_BROKER_HOSTNAME}.${KOSMOS_LOCAL_MQTT_BROKER_ROLE_FQDN} \
    -e TOPIC='kosmos/machine-data/9d82699b-373a-4b2a-8925-f7bfacb618a4/Sensor/tbd/Update' \
    harbor.kosmos.idcp.inovex.io/ondics/machine-simulator:rc1