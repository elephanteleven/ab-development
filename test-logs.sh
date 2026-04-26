#!/bin/bash
docker compose -p ${CYPRESS_STACK} logs -f || docker-compose -p ${CYPRESS_STACK} logs -f
