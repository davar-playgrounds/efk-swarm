SHELL := $(shell which bash)
.SILENT: ;               # no need for @

include .env
export

define docker-env
$(foreach val, $(shell docker-machine env $1 | sed -e '/^#/d' -e 's/"//g'), $(eval $(val)))
endef

define get-node-ip
$(shell docker-machine ip $1)
endef

node-env:
	$(call docker-env, $(SWARM_MASTER))

node-up:
	./scripts/swarm-up.sh

node-down:
	docker-machine ls --format '{{.Name}}' | xargs -I {} docker-machine rm -f -y {} 2>/dev/null

node-cleanup: node-env
	for node in $$(docker node ls --format '{{.Hostname}}'); do \
		echo "Cleaning up $$node volume"; \
		if [[ ! -z $$node ]]; then \
			eval $$(docker-machine env $$node); \
			docker-machine ssh $$node sh -c "docker volume prune > /dev/null 2>&1"; \
		fi \
	done

node-viz:
	open http://$(call get-node-ip, node-1)/viz

node-status: node-env
	docker node ls

stack-start: node-env
	mkdir -p ./log
	docker stack deploy -c docker-compose.yml $(STACK_NAME)

stack-service: node-env
	watch docker stack services $(STACK_NAME)

ifeq (stack-service-restart,$(firstword $(MAKECMDGOALS)))
  SERVICE:=$(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(SERVICE):;@:)
endif
stack-service-restart: node-env
	eval $(env | grep DOCKER); cnt=`docker service ls | grep $(SERVICE) | wc -l`; \
	if [[ -z $$cnt ]]; then \
		echo "No such service: $(STACK_NAME)_$(SERVICE)"; \
	else \
		echo "Restart service: $(STACK_NAME)_$(SERVICE)"; \
		docker service rm $(STACK_NAME)_$(SERVICE); \
		[[ $(SERVICE) == flog ]] && rm -rf ./log/apache.log; \
		docker stack deploy -c docker-compose.yml $(STACK_NAME); \
	fi

stack-ps: node-env
	watch docker stack ps --no-trunc $(STACK_NAME)

ifeq (stack-logs,$(firstword $(MAKECMDGOALS)))
  SERVICE:=$(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(SERVICE):;@:)
endif
stack-logs: node-env
	docker service logs -f $(STACK_NAME)_$(SERVICE)

stack-stop: node-env
	docker stack rm $(STACK_NAME)

stack-reload:
	make stack-stop && make node-cleanup && make stack-start

kibana:
	open http://$(call get-node-ip, node-1)

kibana-import-dashboard:
	$(eval host=$(call get-node-ip, node-1))
	echo "Import metricbeat dashboard...";
	docker run --net="host" docker.elastic.co/beats/metricbeat:$(TAG) setup -e \
		-E output.logstash.enabled=false \
		-E output.elasticsearch.hosts=['$(host):9200'] \
		-E setup.kibana.host=$(host):80; \
	echo "Import filebeat dashboard...";
	docker run --net="host" docker.elastic.co/beats/filebeat:$(TAG) setup -e \
		-E output.logstash.enabled=false \
		-E output.elasticsearch.hosts=['$(host):9200'] \
		-E setup.kibana.host=$(host):80;

.PHONY: node-env node-up node-down node-cleanup node-viz node-status stack-start stack-service stack-service-restart stack-ps stack-logs stack-stop kibana kibana-import-dashboard
