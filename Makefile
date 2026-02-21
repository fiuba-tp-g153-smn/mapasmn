# Root Makefile for orchestrating all services

SERVICES = data-service tiles-processor visualizer

.PHONY: up down prod $(SERVICES)

up:
	@for service in $(SERVICES); do \
		echo "Starting $$service..."; \
		$(MAKE) -C $$service up & \
	done; \
	wait

down:
	@for service in $(SERVICES); do \
		echo "Stopping $$service..."; \
		$(MAKE) -C $$service down; \
	done

prod:
	@for service in $(SERVICES); do \
		echo "Starting $$service (prod)..."; \
		$(MAKE) -C $$service prod & \
	done; \
	wait

# Individual service targets
data-service:
	$(MAKE) -C data-service up

tiles-processor:
	$(MAKE) -C tiles-processor up

visualizer:
	$(MAKE) -C visualizer up