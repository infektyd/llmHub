# Makefile for llmHub Icon Setup
# Makes it easy to generate and install icons

# Configuration
ICON_SOURCE ?= icon.png
ASSETS_DIR = ./llmHub/Assets.xcassets/AppIcon.appiconset
PLATFORM ?= universal

.PHONY: help icons-bash icons-python icons install clean

help: ## Show this help message
	@echo "llmHub Icon Setup Makefile"
	@echo "=========================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Usage examples:"
	@echo "  make icons                    # Generate icons using auto-detected method"
	@echo "  make icons ICON_SOURCE=my.png  # Use a specific source icon"
	@echo "  make install PLATFORM=macos   # Install macOS-only icons"
	@echo "  make clean                    # Clean generated icons"

icons: ## Auto-detect and generate all icon sizes
	@if command -v sips >/dev/null 2>&1; then \
		$(MAKE) icons-bash; \
	elif command -v python3 >/dev/null 2>&1; then \
		$(MAKE) icons-python; \
	else \
		echo "Error: Neither sips nor python3 found."; \
		exit 1; \
	fi

icons-bash: ## Generate icons using bash script (macOS only)
	@echo "🎨 Generating icons with bash script..."
	@chmod +x generate_icons.sh
	@./generate_icons.sh $(ICON_SOURCE) $(ASSETS_DIR)

icons-python: ## Generate icons using Python script
	@echo "🎨 Generating icons with Python script..."
	@python3 -m pip install --quiet Pillow 2>/dev/null || true
	@python3 generate_icons.py $(ICON_SOURCE) $(ASSETS_DIR)

install: icons ## Generate and install icons with Contents.json
	@echo "📦 Installing $(PLATFORM) configuration..."
	@if [ "$(PLATFORM)" = "universal" ]; then \
		cp AppIcon-Universal-Contents.json $(ASSETS_DIR)/Contents.json; \
		echo "✅ Universal (macOS + iOS) configuration installed"; \
	elif [ "$(PLATFORM)" = "macos" ]; then \
		cp AppIcon-macOS-Contents.json $(ASSETS_DIR)/Contents.json; \
		echo "✅ macOS configuration installed"; \
	elif [ "$(PLATFORM)" = "ios" ]; then \
		cp AppIcon-iOS-Contents.json $(ASSETS_DIR)/Contents.json; \
		echo "✅ iOS configuration installed"; \
	else \
		echo "❌ Invalid platform: $(PLATFORM)"; \
		echo "   Valid options: universal, macos, ios"; \
		exit 1; \
	fi
	@echo ""
	@echo "🎉 Icon setup complete!"
	@echo "Next steps:"
	@echo "  1. Open Xcode"
	@echo "  2. Clean build (Cmd+Shift+K)"
	@echo "  3. Build and run!"

clean: ## Remove generated icon files
	@echo "🧹 Cleaning generated icons..."
	@rm -f $(ASSETS_DIR)/icon_*.png
	@echo "✅ Cleaned"

check: ## Check if icon source file exists
	@if [ -f "$(ICON_SOURCE)" ]; then \
		echo "✅ Icon source found: $(ICON_SOURCE)"; \
		file $(ICON_SOURCE); \
	else \
		echo "❌ Icon source not found: $(ICON_SOURCE)"; \
		echo "Available image files:"; \
		ls -1 *.png *.jpg *.jpeg 2>/dev/null || echo "  (none found)"; \
		exit 1; \
	fi

# Platform-specific shortcuts
universal: ## Install universal (macOS + iOS) icons
	@$(MAKE) install PLATFORM=universal

macos: ## Install macOS-only icons
	@$(MAKE) install PLATFORM=macos

ios: ## Install iOS-only icons
	@$(MAKE) install PLATFORM=ios

# Quick setup
quick: check install ## Quick setup with default settings
	@echo ""
	@echo "✨ Quick setup complete!"
