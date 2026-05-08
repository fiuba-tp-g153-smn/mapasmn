# Root Makefile for orchestrating all services

SERVICES = data-service tiles-processor visualizer alerts-service

.PHONY: setup update up down prod clean pack-radar fetch-radar $(SERVICES)

setup:
	@./scripts/setup-env.sh

# Pull each submodule to the latest commit on its tracked upstream branch.
# Run this explicitly when you want to bump submodule pointers.
update:
	@git submodule update --init --recursive --remote

# Production (single-compose): root compose.yaml `include:`s every submodule's docker-compose.yaml.
# data-service/docker-compose.yaml expects `data_service_network` to exist (external: true),
# so create it idempotently before bringing the stack up.
prod: setup
	@docker network inspect data_service_network >/dev/null 2>&1 || docker network create data_service_network >/dev/null
	docker compose up --build

down:
	docker compose down --remove-orphans

# Pack the radar H5 dataset into a single zip ready to upload to Google Drive.
# Usage: make pack-radar                                  (defaults to ../tiles-processor/data/radar_h5)
#        make pack-radar SOURCE=/path/to/radar_h5 OUTPUT=/path/to/radar.zip
pack-radar:
	@./scripts/pack-radar.sh "$(SOURCE)" "$(OUTPUT)"

# Download the radar dataset from Google Drive and extract into tiles-processor/data/radar_h5/.
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

# Individual service targets — bring up one submodule on its own (dev compose)
data-service:
	$(MAKE) -C data-service up

tiles-processor:
	$(MAKE) -C tiles-processor up

visualizer:
	$(MAKE) -C visualizer up

alerts-service:
	$(MAKE) -C alerts-service up
