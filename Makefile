#
##
APPMAIL?="webmaster@zentek.com.mx"
REPONAME?="zentekmx"
NOCLR=\x1b[0m
OKCLR=\x1b[32;01m
ERRCLR=\x1b[31;01m
WARNCLR=\x1b[33;01m
TEST_ARGS=
EXECUTABLES=docker pip python screen npm gulp
include .env
export $(shell sed 's/=.*//' .env)
ENVIRONMENT=$(lastword $(subst ., ,$(DJANGO_SETTINGS_MODULE)))
ifeq (${ENVIRONMENT},prod)
PREFIX=
else
PREFIX=${ENVIRONMENT}_
endif

define usage =
Build and development task automation tool for project"

Usage:
  make [task]
endef

## Built in tasks ##

#: env - Shows current working environment
env:
	@echo -e "\n\tProfile [${OKCLR}${DJANGO_SETTINGS_MODULE}${NOCLR}]\n"

#: development - Changes to development environment
development:
	@sed -i 's|^DJANGO_SETTINGS_MODULE=.*|DJANGO_SETTINGS_MODULE=ralph.settings.dev|' .env
	@make env

#: testing - Changes to qa(testing) environment
testing:
	@sed -i 's|^DJANGO_SETTINGS_MODULE=.*|DJANGO_SETTINGS_MODULE=ralph.settings.test|' .env
	@make env

#: production - Changes to uat(production) environment
production:
	@sed -i 's|^DJANGO_SETTINGS_MODULE=.*|DJANGO_SETTINGS_MODULE=ralph.settings.prod|' .env
	@make env

#: help - Show Test info
help: env
	$(info $(usage))
	@echo -e "\n  Available targets:"
	@egrep -o "^#: (.+)" [Mm]akefile  | sed 's/#: /    /'
	@echo "  Please report errors to ${APPMAIL}"

#: check - Check that system requirements are met
check:
	$(info Required: ${EXECUTABLES})
	$(foreach bin,$(EXECUTABLES),\
	    $(if $(shell command -v $(bin) 2> /dev/null),$(info Found `$(bin)`),$(error Please install `$(bin)`)))

# postgres - Start postgres container
postgres: env
	@if [[ ! $$(docker ps -a | grep "${SLUG}-postgres") ]]; then \
		docker run -d --rm --name ${SLUG}-postgres -p ${DATABASE_PORT}:${DATABASE_PORT} -e POSTGRES_DB=${DATABASE_NAME} -e POSTGRES_USER=${DATABASE_USER} -e POSTGRES_PASSWORD=${DATABASE_PASSWORD} postgres:12-alpine; \
	else \
		echo "[${SLUG}-postgres] There is an existing postgres container name, I will use"; \
	fi

# redis - Start redis container
redis: env
	@if [[ ! $$(docker ps -a | grep "${SLUG}-redis") ]]; then \
		docker run -d --rm --name ${SLUG}-redis -p ${REDIS_PORT}:${REDIS_PORT} redis:5-alpine; \
	else \
		echo "[${SLUG}-redis] There is an existing redis container name, I will use"; \
	fi

#: backend-start - Start backend services
backend-start: postgres redis
	@sleep 2
	@echo "Backend services started..."

#: backend-stop - Start backend services
backend-stop:
	@if [[ $$(docker ps -a | grep "${SLUG}-redis") ]]; then \
		docker stop ${SLUG}-redis; \
	fi; \
	if [[ $$(docker ps -a | grep "${SLUG}-postgres") ]]; then \
		docker stop ${SLUG}-postgres; \
	fi;
	@echo "Backend services stopped..."

#: migrations - Initializes and apply changes to DB
migrations: env
	@${PREFIX}ralph makemigrations
	@${PREFIX}ralph migrate

#: jupyterlab - Runs notebook
jupyterlab: env
	@jupyter lab --ip=0.0.0.0 --no-browser --notebook-dir ./notebook

#: shell - Access django admin shell
shell:
	@${PREFIX}ralph shell

#: dbshell - Access database shell
dbshell:
	@${PREFIX}ralph dbshell

#: ddl - Dump database ddl
ddl:
	@pg_dump "postgresql://${DATABASE_USER}:${DATABASE_PASSWORD}@${DATABASE_HOST}:${DATABASE_PORT}/${DATABASE_NAME}" -s > fixtures/ddl/ddl.sql

#: schema - Dump database schema
schema:
	@pg_dump "postgresql://${DATABASE_USER}:${DATABASE_PASSWORD}@${DATABASE_HOST}:${DATABASE_PORT}/${DATABASE_NAME}" > fixtures/ddl/schema.sql

# release-new-version is used by ralph mainteiners prior to publishing
# new version of the package. The command generates the debian changelog
# commits it and tags the created commit with the appropriate snapshot version.
release-new-version: new_version = $(shell ./get_version.sh generate)
release-new-version:
	docker build \
		--force-rm \
		-f docker/Dockerfile-deb \
		--build-arg GIT_USER_NAME="$(shell git config user.name)" \
		--build-arg GIT_USER_EMAIL="$(shell git config user.email)" \
		-t ralph-deb:latest .
	docker run --rm -it -v $(shell pwd):/volume ralph-deb:latest release-new-version
	docker image rm --force ralph-deb:latest
	git add debian/changelog
	git commit -S -m "Updated changelog for $(new_version) version."
	git tag -m $(new_version) -a $(new_version) -s

# build-package builds a release version of the package using the generated
# changelog and the tag.
build-package:
	docker build --force-rm -f docker/Dockerfile-deb -t ralph-deb:latest .
	docker run --rm -v $(shell pwd):/volume ralph-deb:latest build-package
	docker image rm --force ralph-deb:latest

# build-snapshot-package renerates a snapshot changelog and uses it to build
# snapshot version of the package. It is mainly used for testing.
build-snapshot-package:
	docker build --force-rm -f docker/Dockerfile-deb -t ralph-deb:latest .
	docker run --rm -v $(shell pwd):/volume ralph-deb:latest build-snapshot-package
	docker image rm --force ralph-deb:latest

build-docker-image: version = $(shell git describe --abbrev=0)
build-docker-image:
	docker build \
		--no-cache \
		-f docker/Dockerfile-prod \
		--build-arg RALPH_VERSION="$(version)" \
		-t $(REPONAME)/ralph:latest \
		-t "$(REPONAME)/ralph:$(version)" .
	docker build \
		--no-cache \
		-f docker/Dockerfile-static \
		--build-arg RALPH_VERSION="$(version)" \
		-t $(REPONAME)/ralph-static-nginx:latest \
		-t "$(REPONAME)/ralph-static-nginx:$(version)" .

build-snapshot-docker-image: version = $(shell ./get_version.sh show)
build-snapshot-docker-image: build-snapshot-package
	docker build \
		-f docker/Dockerfile-prod \
		--build-arg RALPH_VERSION="$(version)" \
		--build-arg SNAPSHOT="1" \
		-t $(REPONAME)/ralph:latest \
		-t "$(REPONAME)/ralph:$(version)" .
	docker build \
		-f docker/Dockerfile-static \
		--build-arg RALPH_VERSION="$(version)" \
		-t "$(REPONAME)/ralph-static-nginx:$(version)" .

# pipdep - Tweak pip dependencies before 20.3+
pipdep: env
	@pip install pip==20.2.4

#: install-js - Install js dependencies
install-js:
	npm install

js-hint:
	find src/ralph|grep "\.js$$"|grep -v vendor|xargs ./node_modules/.bin/jshint;

#: install - Install dependencies for current environment
install: install-js
	pip3 install -r requirements/${ENVIRONMENT}.txt

#: install-docs - Install docs dependencies
install-docs: pipdep
	pip3 install -r requirements/docs.txt

#: install-jupyter - Install jupyter dependencies and extensions
install-jupyter: pipdep
	pip3 install -r requirements/jupyter.txt
	jupyter labextension install jupyterlab-execute-time
	jupyter labextension install @jupyter-widgets/jupyterlab-manager
	jupyter labextension install @jupyterlab/toc
	jupyter labextension install @jupyterlab/debugger
	jupyter labextension install jupyterlab-jupytext
	jupyter labextension install @axlair/jupyterlab_vim
	jupyter labextension install @jupyter-widgets/jupyterlab-manager jupyter-leaflet
	jupyter labextension install jupyterlab-topbar-extension jupyterlab-system-monitor
	jupyter labextension install @bokeh/jupyter_bokeh
	jupyter labextension install jupyterlab-drawio
	jupyter labextension install @jupyterlab/commenting-extension
	jupyter labextension install @jupyterlab/google-drive

isort:
	isort --diff --recursive --check-only --quiet src

#: test - Execute test
test: clean
	${PREFIX}ralph test ralph $(TEST_ARGS)

flake: isort
	flake8 src/ralph
	flake8 src/ralph/settings --ignore=F405 --exclude=*local.py
	@cat scripts/flake.txt

# clean - Remove build and python files
clean:
	@find . -name '*.py[cod~]' -exec rm -rf {} +

# clean-build - Remove build and python files
clean-dist:
	@rm -fr lib/
	@rm -fr build/
	@rm -fr dist/
	@rm -fr .tox/
	@rm -fr *.egg-info

# clean-migrations - Remove migrations files
clean-migrations:
	@find "src/ralph" -path "*/migrations/*.py" -not -name "__init__.py" -delete
	@find "src/ralph" -name __pycache__ -delete
	@rm -fr media/*

# clean-containers - Remove docker files
clean-containers:
	@docker system prune --volumes

#: clean-all - Full clean
clean-all: clean clean-dist clean-migrations clean-containers

#: coverage - Coverage tests
coverage: clean
	coverage run $(shell which test_ralph) test ralph -v 2 --keepdb --settings="ralph.settings.test"
	coverage report

#: docs - Generate docs
docs: install-docs
	mkdocs build

# run-dev - Run development mode
run-dev:
	${PREFIX}ralph runserver_plus 0.0.0.0:8000

# run-wsgi - Run development mode
run-prod:
	ralph runserver 0.0.0.0:8000

#: run - Run
run: run-dev

#: stop - Stop
stop: backend-stop

#: fixtures - Load fixtures
fixtures: env
ifeq (${ENVIRONMENT},prod)
	ifneq (,$(wildcard ./fixtures/*.yaml))
		${PREFIX}ralph loaddata fixtures/*.yaml
	endif
else
	ifneq (,$(wildcard ./fixtures/dev/*.yaml))
		${PREFIX}ralph loaddata fixtures/dev/*.yaml
	endif
endif

#: static - Collect statics
statics: env
	${PREFIX}ralph sitetree_resync_apps
	${PREFIX}ralph collectstatic -c --noinput
	${PREFIX}ralph collectmedia --noinput
	gulp

#: fixtures-dump - Dump fixtures
fixtures-dump: env
ifeq (${ENVIRONMENT},prod)
	${PREFIX}ralph dumpdata -e sessions.Session --indent 2 --format=yaml > fixtures/ralph.yaml
else
	${PREFIX}ralph dumpdata -e sessions.Session --indent 2 --format=yaml > fixtures/dev/ralph.yaml
	rsync -av media/ fixtures/media_fixtures/
endif

# populate - Run test from different version managed in tox
createuser: env
	@${PREFIX}ralph createsuperuser --username admin --email ${APPMAIL}

# populate - Run test from different version managed in tox
populate: env
	@${PREFIX}ralph demodata

translate_messages:
	${PREFIX}ralph makemessages -a

compile_messages:
	${PREFIX}ralph compilemessages

#: deploy - Deploy
deploy: env clean backend-start migrations statics run

# push - Push to upload
push: build-docker-image
	docker login
	docker push ${REPONAME}/ralph

#: release - Build and push
release: build-docker-image push

#: tag - Generate new tag with current version
tag: env
	git tag -a "v$(shell ${PREFIX}ralph print-version | tail -1 )"
	@gitchangelog > CHANGELOG

# compose - Run with docker compose
compose: build-docker-image
	docker-compose up


.PHONY: test flake clean coverage docs coveralls
