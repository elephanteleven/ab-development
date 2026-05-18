#!/bin/bash
docker compose -p ${CYPRESS_STACK} down || docker-compose -p ${CYPRESS_STACK} down
