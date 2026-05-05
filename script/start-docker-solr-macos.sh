#!/bin/sh

# Check if Docker Desktop is running
if ! pgrep -f "Docker Desktop" >/dev/null
then
    echo "Docker Desktop isn't running"
    exit 1
fi

# Check if the seek-search container is already running
if docker ps | grep -q seek-solr
then
    echo "Container named seek-solr is already running"
    exit 1
fi

# Create the volume if it doesn't exist
if ! (docker volume ls | grep -q seek-solr-data-volume)
then
  echo "Creating seek-solr-data-volume"
  docker volume create --name=seek-solr-data-volume
fi

# Start or create the container
if docker ps -a | grep -q seek-solr
then
    echo "Starting seek-search container"
    docker start seek-solr > /dev/null
    echo "Started"
else
    echo "Creating and starting seek-search container"
#    docker run --platform linux/amd64 -d --name seek-search --restart=unless-stopped -p 8983:8983 -v "seek-solr-data-volume:/var/solr/" fairdom/seek-solr:8.11 solr-precreate seek /opt/solr/server/solr/configsets/seek_config

docker run -d --name seek-solr --restart=always \
  -p 8983:8983 \
  -e SOLR_JAVA_MEM="-Xms512m -Xmx1024m" \
  -v seek-solr-data-volume:/var/solr/ \
  -v /Users/whomingbird/work/code/rails-projects/seek/solr/seek/conf:/opt/solr/server/solr/configsets/seek_config \
  fairdom/seek-solr:8.11 \
  docker-entrypoint.sh solr-precreate seek /opt/solr/server/solr/configsets/seek_config

  echo "Created and started"
fi
