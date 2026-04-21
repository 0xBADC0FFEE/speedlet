APP_NAME    := Speedlet
BUNDLE_ID   := dev.vawerv.speedlet
BUILD_DIR   := .build/release
APP_BUNDLE  := dist/$(APP_NAME).app
INSTALL_DIR := /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: build install run clean

build:
	swift build -c release --arch arm64
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns

install: build
	-killall $(APP_NAME) 2>/dev/null || true
	rm -rf $(INSTALLED)
	cp -R $(APP_BUNDLE) $(INSTALLED)
	codesign --force --sign - --deep $(INSTALLED)
	codesign -dv $(INSTALLED)

run: install
	open $(INSTALLED)

clean:
	rm -rf .build dist
