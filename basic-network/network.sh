export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}
export VERBOSE=false

echo
echo " ____  __     __  _____   __   __     __  ____          ____    _____      _      ____    _____   ____    ____"
echo "| ___| \ \   / / |  _  | | |   \ \   / / | ___|        / ___|  |_   _|    / \    |  _ \  |_   _| | ___|  |  _  \ "
echo "| |__   \ \ / /  | | | | | |    \ \ / /  | |__         \___ \    | |     / _ \   | |_) |   | |   | |__   | |  | | "
echo "| |__    \   /   | |_| | | |___  \   /   | |__          ___) |   | |    / ___ \  |  _ <    | |   | |__   | |_ | |"
echo "|____|    \_/    |_____| |_____|  \_/    |____|        |____/    |_|   /_/   \_\ |_| \_\   |_|   |____|  |_____/"
echo
echo


BLACKLISTED_VERSIONS="^1\.0\. ^1\.1\.0-preview ^1\.1\.0-alpha"
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
CLI_TIMEOUT=10
CLI_DELAY=3
CHANNEL_NAME="mychannel"
COMPOSE_FILE=docker-compose-cli.yaml
COMPOSE_FILE_COUCH=docker-compose-couch.yaml
LANGUAGE=node
IMAGETAG="latest"

function clear_containers() {
  CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-peer.*.mycc.*/) {print $1}')
  
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- No containers available for deletion ----"
  
  else
    docker rm -f $CONTAINER_IDS
  fi
}

function remove_unwanted_images() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*.mycc.*/) {print $3}')
  
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "---- No images available for deletion ----"
  
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

function check_prereqs() {
  LOCAL_VERSION=$(./bin/configtxlator version | sed -ne 's/ Version: //p')
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p' | head -1)

  echo "LOCAL_VERSION=$LOCAL_VERSION"
  echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    echo "=================== WARNING ==================="
    echo "  Local fabric binaries and docker images are  "
    echo "  out of  sync. This may cause problems.       "
    echo "==============================================="
  fi

  for UNSUPPORTED_VERSION in $BLACKLISTED_VERSIONS; do
    echo "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
    
    if [ $? -eq 0 ]; then
      echo "ERROR! Local Fabric binary version of $LOCAL_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
      exit 1
    fi

    echo "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
    
    if [ $? -eq 0 ]; then
      echo "ERROR! Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
      exit 1
    fi
  done
}

function replace_private_key() {
  ARCH=$(uname -s | grep Darwin)
  
  if [ "$ARCH" == "Darwin" ]; then
    OPTS="-it"
  
  else
    OPTS="-i"
  fi

  cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml

  CURRENT_DIR=$PWD

  cd crypto-config/peerOrganizations/org1.example.com/ca/

  PRIV_KEY=$(ls *_sk)
  
  cd "$CURRENT_DIR"
  
  sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
  
  cd crypto-config/peerOrganizations/org2.example.com/ca/
  
  PRIV_KEY=$(ls *_sk)
  
  cd "$CURRENT_DIR"
  
  sed $OPTS "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml

  if [ "$ARCH" == "Darwin" ]; then
    rm docker-compose-e2e.yamlt
  fi
}

function generate_certificates() {
  which ./bin/cryptogen
  
  if [ "$?" -ne 0 ]; then
    echo "Cryptogen tool not found. Exiting..."
    exit 1
  fi
  
  echo
  echo "Generating certificates using cryptogen tool..."

  if [ -d "crypto-config" ]; then
    rm -Rf crypto-config
  fi

  set -x

  ./bin/cryptogen generate --config=./crypto-config.yaml

  res=$?

  set +x

  if [ $res -ne 0 ]; then
    echo "Failed to generate certificates. Exiting..."
    exit 1
  fi

  echo
}

function generate_channel_artifacts() {
  which ./bin/configtxgen

  if [ "$?" -ne 0 ]; then
    echo "Configtxgen tool not found. Exiting..."
    exit 1
  fi

  echo
  echo "Generating Orderer Genesis Block..."

  set -x
  
  ./bin/configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
  
  res=$?

  set +x

  if [ $res -ne 0 ]; then
    echo "Failed to generate orderer genesis block. Exiting..."
    exit 1
  fi

  echo
  echo "Generating channel configuration transaction 'channel.tx'..."
  
  set -x
  
  ./bin/configtxgen -profile TwoOrgsChannel -outputCreateChannelTx \
    ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
  
  res=$?
  
  set +x
  
  if [ $res -ne 0 ]; then
    echo "Failed to generate channel configuration transaction. Exiting..."
    exit 1
  fi

  echo
  echo "Generating anchor peer update for Org1MSP..."

  set -x
  
  ./bin/configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate \
    ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
  
  res=$?
  
  set +x
  
  if [ $res -ne 0 ]; then
    echo "Failed to generate anchor peer update for Org1MSP. Exiting..."
    exit 1
  fi

  echo
  echo "Generating anchor peer update for Org2MSP..."

  set -x

  ./bin/configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate \
    ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP

  res=$?

  set +x

  if [ $res -ne 0 ]; then
    echo "Failed to generate anchor peer update for Org2MSP. Exiting..."
    exit 1
  fi

  echo
}

function setup_network() {
  echo
  echo "================================================"
  echo "Creating entities certificates and keys..."
  echo "---"

  generate_certificates

  echo
  echo "Replacing private key..."
  echo "---"
  
  replace_private_key

  echo
  echo "Creating channel artifacts (genesis block to start ordering services and transactions collection to configure the channel)..."
  echo "---"

  generate_channel_artifacts
  
  echo
}

function start_network() {
  check_prereqs

  if [ ! -d "crypto-config" ]; then
    setup_network
  fi

  if [ "${IF_COUCHDB}" == "couchdb" ]; then
    IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH up -d 2>&1
  
  else
    IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE up -d 2>&1
  fi

  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start network"
    exit 1
  fi

  docker exec cli scripts/script.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE
  
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Test failed"
    exit 1
  fi
}

function upgrade_network() {
  if [[ "$IMAGETAG" == *"1.3"* ]] || [[ $IMAGETAG == "latest" ]]; then
    docker inspect -f '{{.Config.Volumes}}' orderer.example.com | grep -q '/var/hyperledger/production/orderer'
    if [ $? -ne 0 ]; then
      echo "ERROR !!!! This network does not appear to be using volumes for its ledgers, did you start from fabric-samples >= v1.2.x?"
      exit 1
    fi

    LEDGERS_BACKUP=./ledgers-backup

    mkdir -p $LEDGERS_BACKUP

    export IMAGE_TAG=$IMAGETAG
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
      COMPOSE_FILES="-f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH"
    else
      COMPOSE_FILES="-f $COMPOSE_FILE"
    fi

    docker-compose $COMPOSE_FILES stop cli
    docker-compose $COMPOSE_FILES up -d --no-deps cli

    echo "Upgrading orderer"
    docker-compose $COMPOSE_FILES stop orderer.example.com
    docker cp -a orderer.example.com:/var/hyperledger/production/orderer $LEDGERS_BACKUP/orderer.example.com
    docker-compose $COMPOSE_FILES up -d --no-deps orderer.example.com

    for PEER in peer0.org1.example.com peer1.org1.example.com peer0.org2.example.com peer1.org2.example.com; do
      echo "Upgrading peer $PEER"

      docker-compose $COMPOSE_FILES stop $PEER
      docker cp -a $PEER:/var/hyperledger/production $LEDGERS_BACKUP/$PEER/

      CC_CONTAINERS=$(docker ps | grep dev-$PEER | awk '{print $1}')
      if [ -n "$CC_CONTAINERS" ]; then
        docker rm -f $CC_CONTAINERS
      fi
      CC_IMAGES=$(docker images | grep dev-$PEER | awk '{print $1}')
      if [ -n "$CC_IMAGES" ]; then
        docker rmi -f $CC_IMAGES
      fi

      docker-compose $COMPOSE_FILES up -d --no-deps $PEER
    done

    docker exec cli scripts/upgrade_to_v13.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE
    if [ $? -ne 0 ]; then
      echo "ERROR !!!! Test failed"
      exit 1
    fi
  else
    echo "ERROR !!!! Pass the v1.3.x image tag"
  fi
}

function shutdown_network() {
  echo
  echo "================================================"
  echo "Shutting down last deployed network..."
  echo "---"

  docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH down --volumes --remove-orphans

  if [ "$MODE" != "restart" ]; then
    docker run -v $PWD:/tmp/first-network --rm hyperledger/fabric-tools:$IMAGETAG rm -Rf /tmp/first-network/ledgers-backup
    
    clear_containers
    
    remove_unwanted_images

    rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config

    rm -f docker-compose-e2e.yaml
  fi
}

MODE=$1

if [ "${MODE}" == "start" ]; then
  start_network
elif [ "${MODE}" == "shutdown" ]; then
  shutdown_network
elif [ "${MODE}" == "setup" ]; then
  setup_network
elif [ "${MODE}" == "restart" ]; then
  shutdown_network
  start_network
elif [ "${MODE}" == "upgrade" ]; then
  upgrade_network
else
  shutdown_network
  setup_network
  start_network
fi
