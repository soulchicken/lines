APP := Lines.app
BIN := $(APP)/Contents/MacOS/Lines
PLIST := $(APP)/Contents/Info.plist
RESOURCES := $(addprefix $(APP)/Contents/Resources/,Lines.icns MenuPen.png)
SOURCES := $(wildcard Sources/*.swift)
MACOSX_DEPLOYMENT_TARGET := 14.0
ARCH := $(shell uname -m)

.PHONY: all run
all: $(APP)/Contents/_CodeSignature/CodeResources

$(BIN): $(SOURCES) Makefile
	mkdir -p $(APP)/Contents/MacOS .build/modules
	xcrun swiftc -O -target $(ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) -module-cache-path .build/modules $(SOURCES) -o $@

$(PLIST): Info.plist
	mkdir -p $(APP)/Contents
	cp $< $@

$(APP)/Contents/Resources/%: Resources/%
	mkdir -p $(APP)/Contents/Resources
	cp $< $@

$(APP)/Contents/_CodeSignature/CodeResources: $(BIN) $(PLIST) $(RESOURCES)
	codesign --force --sign - $(APP)

run: all
	open $(APP)
