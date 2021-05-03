#!/bin/sh

docker run --rm --privileged docker/binfmt:820fdd95a9972a5308930a2bdfb8573dd4447ad3
docker buildx build --platform linux/amd64,linux/arm/v7 -t hlappa/bb_aleksi:latest . --push
