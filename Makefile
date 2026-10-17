NVIM ?= nvim
DEPS_DIR := .deps
PLENARY_DIR := $(abspath $(DEPS_DIR)/plenary.nvim)
AJV := npx --yes ajv-cli@5.0.0

.PHONY: all deps test lint fmt validate

all: lint validate test

deps: $(PLENARY_DIR)

$(PLENARY_DIR):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@

test: deps
	PLENARY_DIR=$(PLENARY_DIR) $(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

lint:
	stylua --check .
	selene lua plugin tests

fmt:
	stylua .

validate:
	$(AJV) validate --spec=draft2020 -s challenges/schema.json -d "challenges/[0-9]*.json"
