.PHONY: build release app install clean run help test verify info open factory-worker-sync factory-worker-check factory-worker-doctor factory-audit-once factory-audit-install proxy-binary

help: ## Show this help message
	@echo "VibeProxy - macOS Menu Bar App"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

CLI_PROXY_SRC ?= $(shell realpath ../CLIProxyAPIPlus 2>/dev/null)
CLI_PROXY_BIN := src/Sources/Resources/cli-proxy-api-plus

proxy-binary: ## Build cli-proxy-api-plus from Go source
	@if [ -z "$(CLI_PROXY_SRC)" ] || [ ! -d "$(CLI_PROXY_SRC)" ]; then \
		echo "Go source not found at ../CLIProxyAPIPlus"; exit 1; \
	fi
	@echo "Building cli-proxy-api-plus from Go source..."
	@cd "$(CLI_PROXY_SRC)" && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
		go build -ldflags="-s -w" -o "$(CURDIR)/$(CLI_PROXY_BIN)" ./cmd/server/
	@echo "Built: $(CLI_PROXY_BIN) ($$(du -h $(CLI_PROXY_BIN) | cut -f1))"

build: ## Build the Swift executable (debug)
	@echo "🔨 Building Swift executable..."
	@cd src && swift build
	@echo "✅ Build complete: src/.build/debug/CLIProxyMenuBar"

release: ## Build the Swift executable (release)
	@echo "🔨 Building Swift executable (release)..."
	@./build.sh
	@echo "✅ Build complete: src/.build/release/CLIProxyMenuBar"

app: ## Create the .app bundle
	@echo "📦 Creating .app bundle..."
	@./create-app-bundle.sh
	@echo "✅ App bundle created: VibeProxy.app"

install: app ## Build and install to /Applications
	@echo "📲 Installing to /Applications..."
	@rm -rf "/Applications/VibeProxy.app"
	@cp -r "VibeProxy.app" /Applications/
	@echo "✅ Installed to /Applications/VibeProxy.app"

run: app ## Build and run the app
	@echo "🚀 Launching app..."
	@open "VibeProxy.app"

clean: ## Clean build artifacts
	@echo "🧹 Cleaning..."
	@rm -rf src/.build
	@rm -rf "VibeProxy.app"
	@rm -rf src/Sources/Resources/cli-proxy-api
	@rm -rf src/Sources/Resources/config.yaml
	@rm -rf src/Sources/Resources/static
	@echo "✅ Clean complete"

test: ## Build and run verification checks
	@echo "🧪 Building app target..."
	@cd src && swift build
	@echo "🧪 Running verification specs..."
	@./scripts/run-verification-specs.sh
	@echo "✅ Verification successful"

verify: test ## Alias for test

factory-worker-sync: ## Rewrite Factory worker snapshots from the global authority file
	@./scripts/sync-factory-worker-contract.sh --write

factory-worker-check: ## Check whether Factory worker snapshots drifted from the global authority file
	@./scripts/sync-factory-worker-contract.sh --check

factory-worker-doctor: ## Verify mission worker readiness against the explicit Factory worker contract
	@./scripts/factory-worker-preflight.sh

factory-audit-once: ## Audit Factory logs/state once and repair local drift or proxy readiness issues
	@./scripts/factory-audit-and-repair.sh

factory-audit-install: ## Install and load the 30-minute Factory audit launch agent
	@mkdir -p "$$HOME/Library/LaunchAgents"
	@cp ops/launchd/com.vibeproxy.factory-audit.plist "$$HOME/Library/LaunchAgents/com.vibeproxy.factory-audit.plist"
	@launchctl bootout "gui/$$(id -u)/com.vibeproxy.factory-audit" >/dev/null 2>&1 || true
	@launchctl bootstrap "gui/$$(id -u)" "$$HOME/Library/LaunchAgents/com.vibeproxy.factory-audit.plist"
	@launchctl kickstart -k "gui/$$(id -u)/com.vibeproxy.factory-audit"

info: ## Show project information
	@echo "Project: VibeProxy - macOS Menu Bar App"
	@echo "Language: Swift 5.9+"
	@echo "Platform: macOS 13.0+"
	@echo ""
	@echo "Files:"
	@find src/Sources -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print "  Swift code: " $$1 " lines"}'
	@echo "  Documentation: 4 files"
	@echo ""
	@echo "Structure:"
	@tree -L 3 -I ".build" || echo "  (install 'tree' for better output)"

open: ## Open app bundle to inspect contents
	@if [ -d "VibeProxy.app" ]; then \
		open "VibeProxy.app"; \
	else \
		echo "❌ App bundle not found. Run 'make app' first."; \
	fi

edit-config: ## Edit the bundled config.yaml
	@if [ -d "VibeProxy.app" ]; then \
		open -e "VibeProxy.app/Contents/Resources/config.yaml"; \
	else \
		echo "❌ App bundle not found. Run 'make app' first."; \
	fi

# Shortcuts
all: app ## Same as 'app'
