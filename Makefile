# Root Makefile for orchestrating all services

SERVICES = data-service tiles-processor visualizer alerts-service
PROD_COMPOSE = docker compose -f compose.yaml -f scripts/compose-production.yaml

.PHONY: setup update up down prod beta1 beta1-down clean pack-radar fetch-radar $(SERVICES)

setup:
	@./scripts/setup-env.sh

# Pull each submodule to the latest commit on its tracked upstream branch.
# Run this explicitly when you want to bump submodule pointers.
update:
	@git submodule update --init --recursive --remote

# Full production: portable input mounts and private infrastructure ports.
# Initialize all workers before the producer can enqueue work: workers clean
# shared scratch at startup. Existing jobs must be drained before an update.
prod: setup
	@set -eu; ROOT_DIR="$(CURDIR)"; . ./scripts/load-env.sh; \
	if [ "$$MYSQL_MODE" = external ]; then \
		set -- -f scripts/compose-mysql-external.yaml; \
	else \
		set --; \
	fi; \
	$(PROD_COMPOSE) "$$@" config --quiet; \
	docker network inspect data_service_network >/dev/null 2>&1 || docker network create data_service_network >/dev/null; \
	$(PROD_COMPOSE) "$$@" up -d --build --wait --wait-timeout 900 rabbitmq seaweedfs redis data-service-api data-service-sync alerts-service metrics-api worker1 worker2 worker-light1 worker-light2 worker-light3; \
	$(PROD_COMPOSE) "$$@" up -d --build --wait --wait-timeout 300 producer visualizer

# Beta-1 uses the production variants of the three HTTP components and the
# light tiles-processor preset. The tiles override is included by the root file.
beta1: setup
	@set -eu; ROOT_DIR="$(CURDIR)"; . ./scripts/load-env.sh; \
	docker network inspect data_service_network >/dev/null 2>&1 || docker network create data_service_network >/dev/null; \
	docker compose -f compose.beta-1.yaml up --build

beta1-down:
	docker compose -f compose.beta-1.yaml down --remove-orphans

down:
	docker compose down --remove-orphans
	docker compose -f compose.beta-1.yaml down --remove-orphans

# Pack the radar H5 dataset into a single zip ready to upload to Google Drive.
# Usage: make pack-radar
#        make pack-radar SOURCE=/path/to/radar-sinarame OUTPUT=/path/to/radar.zip
pack-radar:
	@if [ -z "$(SOURCE)" ]; then \
		echo "Usage: make pack-radar SOURCE=/path/to/radar-sinarame [OUTPUT=/path/to/radar.zip]"; \
		exit 1; \
	fi
	@./scripts/pack-radar.sh "$(SOURCE)" "$(OUTPUT)"

# Download the radar dataset from Google Drive into RADAR_SINARAME_INPUT_DIR.
# Usage: make fetch-radar URL=https://drive.google.com/file/d/<id>/view
fetch-radar:
	@if [ -z "$(URL)" ]; then \
		echo "Usage: make fetch-radar URL=<google-drive-share-url-or-file-id>"; \
		exit 1; \
	fi
	@./scripts/fetch-radar.sh "$(URL)"

# Wipe the stack: stop + remove all containers, networks, and volumes.
# Built images are kept (rebuilds are slow). Data in volumes is destroyed.
clean:
	docker compose down --remove-orphans --volumes
	@docker network rm data_service_network 2>/dev/null || true

# Dev (per-submodule fan-out): each service runs its own docker-compose-dev.yaml
up: setup
	@for service in $(SERVICES); do \
		echo "Starting $$service (dev)..."; \
		$(MAKE) -C $$service up & \
	done; \
	wait

# Individual service targets bring up one submodule with its development compose.
data-service:
	$(MAKE) -C data-service up

tiles-processor:
	$(MAKE) -C tiles-processor up

visualizer:
	$(MAKE) -C visualizer up

alerts-service:
	$(MAKE) -C alerts-service up
