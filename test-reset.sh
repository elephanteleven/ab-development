#!/bin/bash
ID_Service=`docker ps | grep ${STACKNAME}-db | awk '{ print $1 }'`
if [ -z "$ID_Service" ]
then
	echo ""
	echo "couldn't find process matching '${STACKNAME}-db' "
	echo ""
	echo "current processes :"
	docker ps
	echo ""
else
	docker exec $ID_Service bash reset.sh
	docker run \
        --env-file .env \
        --network=${STACKNAME}_default \
        digiserve/ab-migration-manager:master node app.js
fi
