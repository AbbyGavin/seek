#!/bin/sh

# Check if Docker is running
if ! docker info >/dev/null 2>&1
then
    echo "The Docker service isn't running or accessible"
    exit 1
fi

# Check if the seek-search container is running
if docker ps | grep -q seek-search
then
    echo "Container named seek-search is currently running, stop it first"
    exit 1
fi

# Remove the seek-search container and seek-solr-data-volume
echo "Deleting seek-solr container and seek-solr-data-volume volume"
docker rm seek-solr > /dev/null 2>&1 && echo "Deleted container"
docker volume rm seek-solr-data-volume > /dev/null 2>&1 && echo "Deleted volume"