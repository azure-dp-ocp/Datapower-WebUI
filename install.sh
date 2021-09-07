#!/bin/bash

echo "Attempting to login to cluster using oc whoami"
USER=$(oc whoami)

if [ $? -eq 0 ]
then
    echo "Logged into a cluster"
    printf "User: "
    tput setaf 2
    echo $USER
    tput sgr0
    echo
else
    echo "Not logged into a cluster. Please login using 'oc login'"
    exit 1
fi

#Check the user is set to the correct project
echo "Please check you are using the correct project"
echo `oc project`
while true; do
    read -p "Is this the correct project? (Y/N) " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit 1;;
        * ) echo "Please answer yes or no.";;
    esac
done


if [ -d "./generated-certs" ]
then
    echo "\nError: 'generated-certs' directory already exists"
    while true; do
        read -p "Would you like to overwrite? (Y/N) " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo "Exiting";exit 1;;
            * ) echo "Please answer yes or no.";;
        esac
     done
fi

read -p "Please enter the password you want for admin: " PASSWORD

mkdir -p generated-certs
cd generated-certs

openssl genrsa -out myCA.key 2048

openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem -subj /CN=GB

cd ..

oc create service clusterip webgui-deployment --tcp=9090:9090

oc create route reencrypt webgui-deployment --service=webgui-deployment --dest-ca-cert generated-certs/myCA.pem

oc create secret generic datapower-user --from-literal=password=$PASSWORD

oc create secret generic datapower-cert --from-file=generated-certs/myCA.pem --from-file=generated-certs/myCA.key

oc apply -f manifests/domain-config.yaml

oc apply -f manifests/datapower.yaml

COUNT=30;

while [ $(oc get DataPowerService webgui-deployment  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]
do  
    if  [ $COUNT -le 1 ]
    then 
        echo "timeout waiting for pods"
        exit 1
    else
        COUNT=$(( $COUNT - 1 ))
        echo "waiting for pod, trying $COUNT more times" && sleep 10; 
    fi
done

ROUTE_URL=$(oc get route webgui-deployment -o jsonpath='{.spec.host}')

echo "Route URL is: https://$ROUTE_URL"