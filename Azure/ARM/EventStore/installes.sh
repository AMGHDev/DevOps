sudo apt-get update
sudo apt-get install vim
curl -s https://packagecloud.io/install/repositories/EventStore/EventStore-OSS/script.deb.sh.deb | sudo bash
sudo apt-get install eventstore-oss=4.0.0
sudo mkdir -p /data1/esdb
sudo mkdir -p /data1/esindex
sudo mkdir -p /data1/eslogs
sudo chown eventstore:eventstore /data1/esdb
sudo chown eventstore:eventstore /data1/esindex
cd /etc/eventstore/
sudo rm eventstore.conf