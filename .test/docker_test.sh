#!/usr/bin/sh

set -e

################################################################################
# Testing docker containers

echo "Waiting to ensure everything is fully ready for the tests..."
sleep 60

echo "Checking main containers are reachable..."
if ! ping -c 10 -q "${PING_CONTAINER}" ; then
    echo 'Main container is not responding!'
    exit 1
fi


################################################################################
# Testing PowerDNS

# TODO Check PowerDNS is up from this container, maybe using its Web API

################################################################################
# Success
echo 'Docker tests successful'
echo 'Check the CI reports and logs for details.'
exit 0
