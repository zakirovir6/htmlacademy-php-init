#!/bin/bash

BASE_DIR=$(pwd)
GIT_REMOTE_FORK="fork"
PROJECT_DOMAIN=".ha"
DOCKER_STACK_PREFIX="ha-"

function usage() {
	echo "usage"
}

function get_user_input_not_empty() {
	read -p "${1}" $2
	if [[ -z "${!2}" ]]
	then
		echo "empty variable not allowed, exit"
		exit 1
	fi
}

REGISTRY_SERVICES_COUNT=$(docker service ls --format "{{.Image}}" | grep "^registry:.*$" | wc -l | tr -d " ")
if [[ $REGISTRY_SERVICES_COUNT != 1 ]]
then
	echo "Need a docker registry service to be run"
	echo "Run docker service create --name registry --publish published=5000,target=5000 registry:latest"
	echo "exit"
	exit 4
fi
REGISTRY_PORT=$(docker service ls --format "{{.Image}}|{{.Ports}}" | grep "^registry:.*$" | cut -f2 -d "|" | awk '{split($0,a,"->"); print a[1]}' | grep -o '[0-9]\+')

get_user_input_not_empty "Please, check that registry is running at 127.0.0.1:$REGISTRY_PORT? [y/n] " REGISTRY_CHECK
if [[ $REGISTRY_CHECK != 'y' ]]
then
	echo "Need a docker registry service to be run"
        echo "Run docker service create --name registry --publish published=5000,target=5000 registry:latest"
        echo "exit"
        exit 4
fi

get_user_input_not_empty "Please, set a project name: " PROJECT_NAME
PROJECT_DIR="${BASE_DIR}/projects/${PROJECT_NAME}"
mkdir -p "${BASE_DIR}/projects"
if [[ -d "${PROJECT_DIR}" ]]
then
	echo "A project ${PROJECT_NAME} has already exists in directory ${PROJECT_DIR}, exit"
	exit 2
fi

get_user_input_not_empty "Please, set a local port for app: " PROJECT_PORT
PORTS_LISTENERS_COUNT=$(lsof -n -i4TCP:${PROJECT_PORT} | wc -l | tr -d " ")
if [[ $PORTS_LISTENERS_COUNT > 0 ]]
then
	echo "There is another processes that listen ${PROJECT_PORT} port, exit"
	exit 3
fi

get_user_input_not_empty "Please, set a github upstream link: " GITHUB_UPSTREAM_REPO
get_user_input_not_empty "Please, set a github fork link: " GITHUB_FORK_REPO

mkdir -p "${PROJECT_DIR}"
mkdir -p "${PROJECT_DIR}/logs"
mkdir -p "${PROJECT_DIR}/db"
mkdir -p "${PROJECT_DIR}/${PROJECT_NAME}"

git clone ${GITHUB_UPSTREAM_REPO} ${PROJECT_DIR}/${PROJECT_NAME}
git -C ${PROJECT_DIR}/${PROJECT_NAME} remote add $GIT_REMOTE_FORK $GITHUB_FORK_REPO

D_COMPOSE_FILE=${PROJECT_DIR}/docker-compose.yaml
NGX_VHOST_FILE=${PROJECT_DIR}/nginx-vhost.conf
PHP_INI_FILE=${PROJECT_DIR}/php.ini
cp "${BASE_DIR}/init/docker-compose.yaml.template" ${D_COMPOSE_FILE}
cp "${BASE_DIR}/init/php.Dockerfile" "${PROJECT_DIR}/php.Dockerfile"
sed -i "" "s|##NGINX_PORT##|${PROJECT_PORT}|g" ${D_COMPOSE_FILE}
sed -i "" "s|##NGINX_VHOST_CONF##|${NGX_VHOST_FILE}|g" ${D_COMPOSE_FILE}
sed -i "" "s|##APP_ROOT##|${PROJECT_DIR}/${PROJECT_NAME}|g" ${D_COMPOSE_FILE}
sed -i "" "s|##NGINX_LOG_PATH##|${PROJECT_DIR}/logs|g" ${D_COMPOSE_FILE}
sed -i "" "s|##NETWORK_NAME##|network-ha-${PROJECT_NAME}|g" ${D_COMPOSE_FILE}
sed -i "" "s|##DB_ROOT##|${PROJECT_DIR}/db|g" ${D_COMPOSE_FILE}
sed -i "" "s|##REGISTRY_PORT##|${REGISTRY_PORT}|g" ${D_COMPOSE_FILE}
sed -i "" "s|##PHP_IMAGE_NAME##|${PROJECT_NAME}-php|g" ${D_COMPOSE_FILE}
sed -i "" "s|##PHP_INI_FILE##|${PHP_INI_FILE}|g" ${D_COMPOSE_FILE}

cp "${BASE_DIR}/init/nginx-vhost.conf.template" ${NGX_VHOST_FILE}
sed -i "" "s|##NGINX_SERVER_NAME##|${PROJECT_NAME}${PROJECT_DOMAIN}|g" ${NGX_VHOST_FILE}

cp "${BASE_DIR}/init/php.ini" ${PHP_INI_FILE}

cd ${PROJECT_DIR} &&
	docker-compose build &&
	docker stack deploy -c ${D_COMPOSE_FILE} ${DOCKER_STACK_PREFIX}${PROJECT_NAME} &&
	cd ${BASE_DIR}
