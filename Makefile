.DEFAULT_GOAL := help
ARG =

.PHONY: help
help: ## help for telmei-go
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# docker-compose
.PHONY: up
up: ## docker-compose up
	docker-compose up -d

.PHONY: reup
reup: ## docker-compose up -d --build
	docker-compose up -d --build

.PHONY: down
down: ## docker-compose down
	docker-compose down

.PHONY: rm
rm: ## docker-compose down and remove
	docker-compose down -v && docker-compose rm -v

.PHONY: ps
ps: ## docker-compose ps
	docker-compose ps

.PHONY: bash
bash: ## docker-compose exec ubuntu bash
	docker-compose exec ubuntu bash

.PHONY: zsh
zsh: ## docker-compose exec ubuntu zsh
	docker-compose exec ubuntu zsh

.PHONY: docker_clean
docker_clean: ## remove docker image
	docker system prune -f

.PHONY: lint
lint: ## ansible-lint site.yml
	ansible-lint site.yml
