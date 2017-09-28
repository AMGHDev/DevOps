#!/bin/bash


if [ -f "/etc/eventstore/eventstore.conf" ]
then  
    echo "Event store already installed"
else
    sudo apt-get update
    sudo apt-get install vim --yes
    sudo apt-get install monodevel --yes
    curl -s https://packagecloud.io/install/repositories/EventStore/EventStore-OSS/script.deb.sh | sudo bash
    sudo apt-get install eventstore-oss=4.0.0
    sudo mkdir -p /data1/esdb
    sudo mkdir -p /data1/esindex
    sudo mkdir -p /data1/eslogs
	sudo mkdir -p /data1/temp
    sudo chown eventstore:eventstore /data1/esdb
    sudo chown eventstore:eventstore /data1/esindex
	sudo chown eventstore:eventstore /data1/eslogs
	sudo chown eventstore:eventstore /data1/temp
    cd /etc/eventstore/
    sudo rm eventstore.conf
	
	sudo sh -c 'cat << EOF >> eventstore.conf
IntIp: 0.0.0.0
IntHttpPrefixes: http://*:2112/
ExtIp: 10.0.2.?
ExtHttpPrefixes: http://10.0.2.5:2113/
IntIpAdvertiseAs: 10.0.2.?

Db: /data1/esdb
Log: /data1/eslogs
Index: /data1/esindex

AddInterfacePrefixes: false
RunProjections: All
ClusterSize: 2
DiscoverViaDns: false

GossipSeed: 10.0.2.5:2112,10.0.2.6:2112,10.0.2.7:2112,10.0.2.8:2112
EOF'

sudo sh -c 'cat << EOF >> /etc/security/limits.conf
*         hard    nofile      500000
*         soft    nofile      500000
root      hard    nofile      500000
root      soft    nofile      500000
EOF'


fi