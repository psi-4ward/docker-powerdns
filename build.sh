#!/usr/bin/env bash

curdir=$(dirname $(readlink -e $0))

pushd $curdir

docker build -t docker.io/sterman/powerdns:4.7.2 -t docker.io/sterman/powerdns:latest

popd
