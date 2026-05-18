#!/bin/bash
docker compose -p ${CYPRESS_STACK} up -d || docker-compose -p ${CYPRESS_STACK} up -d
