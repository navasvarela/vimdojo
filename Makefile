NVIM ?= nvim
DEPS_DIR := .deps
PLENARY_DIR := $(abspath $(DEPS_DIR)/plenary.nvim)
AJV := npx --yes ajv-cli@5.0.0

.PHONY: all check deps test lint fmt validate par manifest doc gif web-deps web-check verifier-check api-check workflows

all: lint validate doc test

deps: $(PLENARY_DIR)

$(PLENARY_DIR):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@

# Plenary kills a spec file after 50 s by default. solutions_spec.lua plays
# every level in a real clean room, which takes longer than that on a busy
# laptop: it was killed mid-run, before reaching the fixture packs.
test: deps
	PLENARY_DIR=$(PLENARY_DIR) $(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true, timeout = 600000 }"

lint:
	stylua --check .
	selene lua plugin tests scripts

fmt:
	stylua .
	npm --prefix web run fix

# Everything CI runs, in one command: Lua lint and format, level validation,
# the help file, plugin tests, Biome (web code, level packs, fixtures),
# typecheck, web tests and build, and the workflow linter.
check: all web-check verifier-check api-check workflows

web-deps:
	npm --prefix web ci

web-check: web-deps
	npm --prefix web run lint
	npm --prefix web run typecheck
	npm --prefix web test
	npm --prefix web run build

# Replays every Motions and Usage reference solution in the leaderboard
# verifier, plus its adversarial tests. Needs nvim on PATH.
verifier-check: web-deps
	npm --prefix verifier ci
	npm --prefix verifier run typecheck
	npm --prefix verifier test

# The leaderboard API, on a real local D1.
api-check:
	npm --prefix api ci
	npm --prefix api run typecheck
	npm --prefix api test
	npm --prefix api run build

workflows:
	scripts/actionlint.sh

validate:
	$(AJV) validate --spec=draft2020 -s challenges/schema.json -d "challenges/[0-9]*.json" -d "tests/fixtures/packs/*.json"

par:
	$(NVIM) --headless --noplugin -u NONE -l scripts/par.lua

# Regenerates verifier/manifest.json after adding or changing levels. A changed
# hash starts that level's leaderboard over, and the tests fail until it's run.
manifest:
	$(NVIM) --headless --noplugin -u NONE -l scripts/manifest.lua

# Fails if the help file has duplicate or malformed tags.
doc:
	$(NVIM) --headless --clean -c "try | helptags doc | catch | cquit 1 | endtry" -c "qa"

# Re-records docs/demo.gif from docs/demo.tape (needs https://github.com/charmbracelet/vhs).
gif:
	vhs docs/demo.tape
