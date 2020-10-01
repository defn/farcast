SHELL := /bin/bash

.PHONY: docs

VARIANT ?= latest
HOMEDIR ?= https://github.com/amanibhavam/homedir
DOTFILES ?= https://github.com/amanibhavam/dotfiles

menu:
	@perl -ne 'printf("\n") if m{^-}; printf("%20s: %s\n","$$1","$$2") if m{^([\w+-]+):[^#]+#\s(.+)$$}' Makefile

config: docker-compose.yml
	@true

---------------build: # -----------------------------
thing: # Build all the things
	$(MAKE) build-sshd
	$(MAKE) build-boot
	$(MAKE) build-jojomomojo

build-sshd: # Build sshd container with lefn/python
	@echo
	docker build $(build) -t defn/home:sshd \
		--build-arg HOMEBOOT=boot \
		-f b/Dockerfile.sshd \
		--no-cache \
		b
	$(MAKE) test-sshd
	docker push defn/home:sshd

build-ssh: # Build ssh container with sshd
	@echo
	docker build $(build) -t defn/home:ssh \
		--build-arg HOMEBOOT=boot \
		--build-arg HOMEUSER=jojomomojo \
		--build-arg HOMEHOST=ssh.defn.sh \
		-f b/Dockerfile.sshu \
		--no-cache \
		b
	$(MAKE) test-ssh
	docker push defn/home:ssh

build-boot: # Build boot container with sshd
	@echo
	docker build $(build) -t defn/home:boot \
		--build-arg HOMEBOOT=boot \
		-f b/Dockerfile.boot \
		b
	$(MAKE) test-boot
	docker push defn/home:boot

b/index: .git/index
	cp -f .git/index b/index.1
	mv -f b/index.1 b/index

build-jojomomojo: b/index # Build jojomomojo container with boot
	@echo
	docker build $(build) -t defn/home:jojomomojo \
		--build-arg HOMEBOOT=boot \
		--build-arg HOMEUSER=jojomomojo \
		--build-arg HOMEHOST=jojomomojo.defn.sh \
		--build-arg HOMEDIR=https://github.com/amanibhavam/homedir \
		--build-arg DOTFILES=https://github.com/amanibhavam/dotfiles \
		-f b/Dockerfile.bootu \
		b
	echo "TEST_PY=$(shell cat test.py | (base64 -w 0 2>/dev/null || base64) )" > .drone.env
	$(MAKE) test-jojomomojo
	docker push defn/home:jojomomojo

----------------test: # -----------------------------

test: # test all images
	$(MAKE) test-sshd
	$(MAKE) test-ssh
	$(MAKE) test-boot
	$(MAKE) test-jojomomojo

test-sshd: # test image sshd
	drone exec --env-file=.drone.env --pipeline test-sshd

test-ssh: # test image ssh
	drone exec --env-file=.drone.env --pipeline test-ssh

test-boot: # test image boot
	drone exec --env-file=.drone.env --pipeline test-boot

test-jojomomojo: # test image jojomomojo
	drone exec --env-file=.drone.env --pipeline test-jojomomojo

----------------bash: # -----------------------------

bash-sshd: # bash shell with sshd
	docker run --rm -ti --entrypoint bash defn/home:sshd

bash-ssh: # bash shell with ssh
	docker run --rm -ti --entrypoint bash defn/home:ssh

bash-boot: # bash shell with boot
	docker run --rm -ti --entrypoint bash defn/home:boot

bash-jojomomojo: # bash shell with jojomomojo
	docker run --rm -ti --entrypoint bash defn/home:jojomomojo

------docker-compose: # -----------------------------

up: # Bring up farcast
	docker-compose up -d --remove-orphans

down: # Bring down farcast
	docker-compose down --remove-orphans

recreate: # Recreate home container
	$(MAKE) down
	$(MAKE) up

recycle: # Recycle home container
	docker-compose pull
	$(MAKE) recreate

bash:
	docker-compose exec sshd bash -il

-------------cuelang: # -----------------------------

docker-compose.yml: docker-compose.cue
	cue export --out json docker-compose.cue | yq -y -s '.[]'  > docker-compose.yml.1
	mv docker-compose.yml.1 docker-compose.yml
