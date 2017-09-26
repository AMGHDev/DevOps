#!/bin/bash

sudo add-apt-repository ppa:duplicity-team/ppa
sudo apt-get update
sudo apt-get install duplicity
sudo apt-get install python-pip
sudo pip install azure-storage==0.20
sudo pip install logentries