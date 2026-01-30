IMAGE := europe-docker.pkg.dev/tenant-dev-435411/tenant-container-repo/dart-cpu-gvisor
TAG := latest
DEPLOYMENT := dart-cpu-gvisor-deployment.yaml
NAMESPACE := prometheus-test
KUBECONFIG := $(HOME)/.kube/membership-tenant-dev-europe-west3-lunar.yaml
KUBECTL := kubectl --kubeconfig=$(KUBECONFIG)

.PHONY: build push deploy all logs top validate burn unburn clean

build:
	docker build --platform=linux/amd64 -t $(IMAGE):$(TAG) .

push:
	docker push $(IMAGE):$(TAG)

deploy:
	$(KUBECTL) apply -f $(DEPLOYMENT)
	$(KUBECTL) rollout restart deployment/dart-cpu-gvisor -n $(NAMESPACE)

all: build push deploy

logs:
	$(KUBECTL) logs -f -n $(NAMESPACE) -l app=dart-cpu-gvisor

top:
	$(KUBECTL) top pod -n $(NAMESPACE) -l app=dart-cpu-gvisor

validate:
	@echo "Compare 'make logs' output with 'make top' - should be within ±20%"

compare:
	@echo "Logging app metrics and kubectl top to cpu_compare.log (Ctrl+C to stop)"
	@echo "timestamp,source,millicores" > cpu_compare.log
	@while true; do \
		ts=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
		top_cpu=$$($(KUBECTL) top pod -n $(NAMESPACE) -l app=dart-cpu-gvisor --no-headers 2>/dev/null | awk '{print $$2}' | sed 's/m//'); \
		if [ -n "$$top_cpu" ]; then \
			echo "$$ts,kubectl_top,$$top_cpu" >> cpu_compare.log; \
			echo "$$ts kubectl_top: $${top_cpu}m"; \
		fi; \
		app_line=$$($(KUBECTL) logs -n $(NAMESPACE) -l app=dart-cpu-gvisor --tail=1 2>/dev/null); \
		app_cpu=$$(echo "$$app_line" | grep -oE 'CPU: [0-9]+m' | grep -oE '[0-9]+'); \
		if [ -n "$$app_cpu" ]; then \
			app_ts=$$(echo "$$app_line" | grep -oE '\[.*\]' | tr -d '[]'); \
			echo "$$app_ts,app,$$app_cpu" >> cpu_compare.log; \
			echo "$$app_ts app: $${app_cpu}m"; \
		fi; \
		sleep 5; \
	done

burn:
	$(KUBECTL) set env deployment/dart-cpu-gvisor -n $(NAMESPACE) BURN_MODE=1
	$(KUBECTL) patch deployment dart-cpu-gvisor -n $(NAMESPACE) --type='json' \
		-p='[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["./monitor", "--burn"]}]'

unburn:
	$(KUBECTL) set env deployment/dart-cpu-gvisor -n $(NAMESPACE) BURN_MODE-
	$(KUBECTL) patch deployment dart-cpu-gvisor -n $(NAMESPACE) --type='json' \
		-p='[{"op": "remove", "path": "/spec/template/spec/containers/0/command"}]'

clean:
	rm -f libmonitor.so monitor
