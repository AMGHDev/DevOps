#!/bin/bash


if [ -f "/usr/bin/duplicity" ]
then  
    echo "Duplicity already installed"
else
    sudo add-apt-repository ppa:duplicity-team/ppa --yes
    sudo apt-get update
    sudo apt-get install duplicity --yes
    sudo apt-get install python-pip --yes
    sudo pip install azure-storage==0.20 
    sudo pip install logentries 
fi