#!/bin/sh

# Check if Docker is running
if ! docker info >/dev/null 2>&1
then
    echo "The Docker service isn't running or accessible"
    exit 1
fi

# Check if the seek-solr container is running
if ! docker ps | grep -q seek-solr
then
    echo "Container named seek-solr is not running"
    exit 1
fi

# Stop the seek-solr container
echo "Stopping seek-solr container"
docker stop seek-solr > /dev/null
echo "Stopped"
