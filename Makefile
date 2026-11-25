APP := Lines.app
BIN := $(APP)/Contents/MacOS/Lines
PLIST := $(APP)/Contents/Info.plist
SOURCES := $(wildcard Sources/*.swift)
export MACOSX_DEPLOYMENT_TARGET := 14.0

.PHONY: all run
all: $(APP)/Contents/_CodeSignature/CodeResources

$(BIN): $(SOURCES)
	mkdir -p $(APP)/Contents/MacOS .build/modules
	xcrun swiftc -O -module-cache-path .build/modules $(SOURCES) -o $@

$(PLIST): Info.plist
	mkdir -p $(APP)/Contents
	cp $< $@

$(APP)/Contents/_CodeSignature/CodeResources: $(BIN) $(PLIST)
	codesign --force --sign - $(APP)

run: all
	open $(APP)
