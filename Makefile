-include .makerc
SHELL = /bin/bash
PACKAGE ?= GO-GRPC

#Build server placeholders
BRANCH_NAME ?= $(shell git rev-parse --abbrev-ref HEAD 2> /dev/null)
BUILD_NUMBER ?= 1
VERSION  ?= $(shell cat $(CURDIR)/version 2> /dev/null || echo 0.0.1)

#Static
GIT_COMMIT ?= $(shell git rev-parse HEAD 2> /dev/null)
TAG ?= $(shell git describe --exact-match $(GIT_COMMIT) 2> /dev/null || true)
GIT_AUTHORS ?= $(shell git log --format='%aN' | sort -u | awk -vORS=, '{ print }' | sed 's/,$$//')

# On master, release or develop, create tags specific for the branch
# On feature branch, still wait for a tag to be present
version:
ifeq ($(BRANCH_NAME), master)
	echo $(VERSION)
else ifeq ($(BRANCH_NAME), release)
	echo $(VERSION)-release-$(BUILD_NUMBER)
else ifeq ($(BRANCH_NAME), develop)
	echo $(VERSION)-develop-$(BUILD_NUMBER)
else
	echo $(TAG)
endif

#Output purposes
OUTPUT_DIR = $(CURDIR)/output
BIN_OUTPUT_DIR = $(OUTPUT_DIR)/bin
TEST_OUTPUT_DIR = $(OUTPUT_DIR)/test
DIRS=$(BIN_OUTPUT_DIR) $(TEST_OUTPUT_DIR)
$(shell mkdir -p $(DIRS))

#Build flags
LDFLAGS ?= "-X 'main.version=$(VERSION)' -X 'main.gitCommit=$(GIT_COMMIT)' -X 'main.application=$(PACKAGE)'"
LINT_FLAGS ?= -c ./.golangci.yaml --out-format checkstyle $(EXTRA_LINT_FLAGS) # EXTRA_LINT_FLAGS can be used to make a difference between Dockerfile builds and local builds
BUILD_FLAGS ?= $(EXTRA_BUILD_FLAGS) ./cmd/app                                 # EXTRA_BUILD_FLAGS can be used to make a difference between Dockerfile builds and local builds
TEST_FLAGS ?= "-tags=unit"
PACKAGE_EXTENSION ?=  $(shell if [ "$(GOOS)" == windows ]; then echo .exe; fi)
GOPROXY=
GONOPROXY=github.com/*
GONOSUMDB=github.com/leonvanderhaeghen
GO111MODULE=on
CGO_ENABLED=0
TARGET ?= final

#Docker
DOCKER_BUILD_ARGS ?=--build-arg ARG_GIT_COMMIT=$(GIT_COMMIT) --build-arg ARG_VERSION=$(VERSION) --build-arg ARG_AUTHORS="$(GIT_AUTHORS)"
DOCKER_FILE_PATH ?= ./build/docker/Dockerfile

.SILENT: ; # no need for @
.ONESHELL: ; # recipes execute in same shell
.NOTPARALLEL: ; # wait for this target to finish
.EXPORT_ALL_VARIABLES: ; # send all vars to shell
.PHONY: version build docs test scripts api cmd configs examples

deps: ## Add dependencies for your project
	go install github.com/jstemmer/go-junit-report@latest

version:
ifeq ($(BRANCH_NAME), master)
	echo $(VERSION)
else ifeq ($(BRANCH_NAME), release)
	echo $(VERSION)-release-$(BUILD_NUMBER)
else ifeq ($(BRANCH_NAME), develop)
	echo $(VERSION)-develop-$(BUILD_NUMBER)
else
	echo $(TAG)
endif

help: ## Show Help
	@grep -E '^[ m-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Lint
	golangci-lint run $(LINT_FLAGS)
	golangci-lint run $(LINT_FLAGS) > $(TEST_OUTPUT_DIR)/lint-report.xml || true && \
	sed -i -e 's/severity="error" source="errcheck"/severity="warning" source="errcheck"/g' $(TEST_OUTPUT_DIR)/lint-report.xml || true && \
	sed -i -e 's/Error return value of/error return value not checked (/g' $(TEST_OUTPUT_DIR)/lint-report.xml || true

build: ## Build the app
	go build -o $(BIN_OUTPUT_DIR)/$(PACKAGE)$(PACKAGE_EXTENSION) --ldflags=$(LDFLAGS) $(BUILD_FLAGS)

run: ## Run the app
	$(BIN_OUTPUT_DIR)/$(PACKAGE)$(PACKAGE_EXTENSION)

test: ## Run tests
	go test $(TEST_FLAGS) ./... $(BUILD_FLAGS)

test-report: ## Launch tests and output go-junit-report
	go test $(TEST_FLAGS) ./... $(BUILD_FLAGS) > $(TEST_OUTPUT_DIR)/tests.output; cat $(TEST_OUTPUT_DIR)/tests.output
	cat $(TEST_OUTPUT_DIR)/tests.output | go-junit-report > $(TEST_OUTPUT_DIR)/go_test_report.xml

test-coverage: ## Run coverage tool for go
	go test $(TEST_FLAGS) ./... -coverpkg ./... -coverprofile $(TEST_OUTPUT_DIR)/cover.out $(BUILD_FLAGS)
	gocov convert $(TEST_OUTPUT_DIR)/cover.out | gocov-xml -source=$(CURDIR) > $(TEST_OUTPUT_DIR)/coverage.xml

docker-build: ## Build: docker
	docker build $(DOCKER_BUILD_ARGS) -t $(PACKAGE):$(VERSION) -f $(DOCKER_FILE_PATH) --target $(TARGET) .
ifeq ($(TARGET), build)
	docker create --name $(PACKAGE)-$(VERSION)-dummy $(PACKAGE):$(VERSION) sh
	docker cp $(PACKAGE)-$(VERSION)-dummy:/go/src/github.com/leonvanderhaeghen/$(PACKAGE)/output/. $(OUTPUT_DIR)
	docker rm -f $(PACKAGE)-$(VERSION)-dummy
endif

proto:
	buf generate