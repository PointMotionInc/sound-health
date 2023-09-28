#!/usr/bin/env sh

# Ports mappings:
# Repo Name : Host machine <-> Inside container
# pii-reverse-proxy : 8001 <-> 8001
# pii-graphql : 8081 <-> 8080
# sh-graphql : 8080 <-> 8080
# app-server : 9000 <-> 9000

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color
BASE_DIR=$(pwd)

# Check if there is at least one command line argument
if [ $# -eq 0 ]; then
  echo -e "${YELLOW}Usage:"
  echo -e "./soundhealth.sh clone [--branch dev]"
  echo -e "./soundhealth.sh start"
  echo -e "./soundhealth.sh stop${NC}"
  exit 1
fi

# Default git branch to clone
git_branch="dev"
src_folder="src"

# if [ -d "$src_folder" ]; then
#     echo -e "${RED}Error: The '$src_folder' folder already exists.${NC}" >&2
#     echo -e "${RED}This script only bootstraps the backend, for updating the code please use git pull command in desired repo ${NC}" >&2
#     exit 1
# fi

if netstat -tuln | grep -q -E ":4200 |:4300 "; then
    echo -e "${RED}Error: A process is running on port 4200 or 4300. Please kill them before continuing.${NC}"
    exit 1
fi

# Check if Docker is running
if docker ps > /dev/null 2>&1 || docker ps -a > /dev/null 2>&1; then
    : # no operation command - does nothing
else
    echo -e "${RED}Error: Docker is not running.${NC}"
    exit 1
fi

# Check if Node.js is installed and get its version
node_version=$(node -v 2>&1)

# Check if the command was successful (Node.js is installed)
if [ $? -eq 0 ]; then
    # Extract the major version number (e.g., 14 from "v14.17.0")
    major_version=$(echo "$node_version" | cut -d 'v' -f 2 | cut -d '.' -f 1)

    # Compare the major version with 18
    if [ "$major_version" -gt 18 ]; then
        echo -e "${GREEN}Node.js is installed, and its version ($node_version) is above 18.${NC}"
    else
        echo -e "${RED}Node.js is installed, but its version ($node_version) is not above 18.${NC}"
        echo -e "${RED}Please install node version 18 or above${NC}"
        exit 1
    fi
else
    echo "Node.js is not installed."
    exit 1
fi

# Parse command line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    "help")
      command="$1"
      shift
      ;;
    "clone")
      command="$1"
      shift
      ;;
    "start")
      command="$1"
      shift
      ;;
    "stop")
      command="$1"
      shift
      ;;
    "--branch")
      shift
      git_branch="$1"
      shift
      ;;
    *)
      echo "Invalid argument: $1"
      echo "run \"setup.sh help\" to print command usage"
      exit 1
      ;;
  esac
done

# Check the value of the command variable
case "$command" in
  "help")
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "${YELLOW}./soundhealth.sh clone [--branch dev]${NC}"
    echo -e "${YELLOW}./soundhealth.sh start${NC}"
    echo -e "${YELLOW}./soundhealth.sh stop${NC}"
    ;;
  "clone")
    echo -e "${YELLOW}Cloning GitHub repositories with branch $git_branch${NC}"
    git clone -b $git_branch https://github.com/iGnosis/pii-reverse-proxy.git $src_folder/pii-reverse-proxy
    git clone -b $git_branch https://github.com/iGnosis/pii-graphql.git $src_folder/pii-graphql
    git clone -b $git_branch https://github.com/iGnosis/sh-graphql.git $src_folder/sh-graphql
    git clone -b $git_branch https://github.com/iGnosis/sh-application-server.git $src_folder/sh-application-server
    echo -e "${GREEN}[√] Cloned all backend repositories.${NC}"

    git clone -b $git_branch https://github.com/iGnosis/sh-player-client.git $src_folder/sh-player-client
    git clone -b $git_branch https://github.com/iGnosis/activity-experience.git $src_folder/activity-experience
    git clone -b $git_branch https://github.com/iGnosis/sh-organization-client $src_folder/sh-organization-client
    echo "${GREEN}[√] Cloned patient and provider repos.${NC}"
    ;;
  "start")
    echo "Starting apps..."
    cd $BASE_DIR/$src_folder/pii-reverse-proxy
    docker compose --env-file $BASE_DIR/.env up --force-recreate -d
    echo -e "${GREEN}[√] pii-reverse-proxy${NC}"
    cd $BASE_DIR

    cd $BASE_DIR/$src_folder/pii-graphql
    docker compose -f docker-compose.prod.yaml --env-file $BASE_DIR/.env up --force-recreate -d
    echo -e "${GREEN}[√] pii-graphql${NC}"
    cd $BASE_DIR

    cd $src_folder/sh-graphql
    docker compose -f docker-compose.prod.yaml --env-file $BASE_DIR/.env up --force-recreate -d
    echo -e "${GREEN}[√] sh-graphql${NC}"
    cd $BASE_DIR

    echo -e "${YELLOW}Pausing script for 30 secs for dependencies to initialize.${NC}"
    sleep 30
    echo -e "${GREEN}Script resumed.${NC}"

    cd $src_folder/sh-application-server
    docker compose --profile prod --env-file $BASE_DIR/.env up --force-recreate -d
    echo -e "${GREEN}[√] sh-application-server${NC}"
    cd $BASE_DIR
    echo -e "${GREEN}Backend servers started. You can run docker ps command to find the containers.${NC}"

    echo -e "${Yellow}Running frontend clients.${NC}"
    cd $BASE_DIR/$src_folder/activity-experience
    npm i --legacy-peer-deps
    npm run start:local-pure
    cd $BASE_DIR/$src_folder/activity-experience/dist/activities
    http-server --port 4201 &
    echo $! >> ../../../../pids.txt

    cd $BASE_DIR/$src_folder/sh-player-client
    npm i --legacy-peer-deps
    npm run start:local-pure
    cd ./dist/sh-player-client
    http-server --port 4200 &
    echo $! >> ../../pids.txt

    cd $src_folder/sh-organization-client
    npm i --legacy-peer-deps
    npm run start:local-pure
    cd $BASE_DIR/$src_folder/sh-organization-client/dist/sh-organization-client
    http-server --port 4300 &
    echo $! >> ../../pids.txt
    
    
    cd $BASE_DIR

    echo "Patient UI: http://localhost:4300/"
    echo "Provider UI: http://localhost:4200/"
    ;;
  "stop")
    if [ ! -f "pids.txt" ]; then
    echo "pids.txt file not found."
    exit 1
    fi

    while read -r pid; do
    if [ -n "$pid" ]; then
        echo "Killing process with PID $pid"
        kill "$pid"
    fi
    done < "pids.txt"

    echo "All processes in pids.txt killed."
    echo > pids.txt

    docker rm -f application_server
    docker rm -f graphql_engine
    docker rm -f local_postgres
    docker rm -f local_postgres_pii
    docker rm -f pii_graphql_engine
    docker rm -f pii_reverse_proxy_local

    echo "Docker containers cleaned up."
    ;;
  *)
    # If the command is not recognized
    echo "Invalid command: $command"
    exit 1
    ;;
esac