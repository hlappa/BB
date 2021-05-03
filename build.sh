#!/bin/sh

docker buildx build --platform linux/amd64,linux/arm/v7 -t hlappa/bb_aleksi:latest . --push
