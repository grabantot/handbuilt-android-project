# jdk version has to be below 8 (52) and build-tools below 24 for dx to work
# though seems like libs (jars) compiled with jdk 8+ are not a problem
# some tools mess up pathes with backslashes, hence $(subst \,/,...

# Environment variables
ANDROID_HOME ?=
ANDROID_HOME := $(subst \,/,$(ANDROID_HOME))

# Build tools & SDK versions
build_tools := 23.0.2
platform    := android-16

# Variables
project     := handbuilt
package     := pl.czak.handbuilt

src_dir     := src
res_dir     := res
lib_dir     := lib

gen_dir     := build/generated
int_dir     := build/intermediates
out_dir     := build/output
cls_dir     := $(int_dir)/classes

sources     := $(shell find $(src_dir) -name '*.java')
resources   := $(shell find $(res_dir) -type f)
generated   := $(gen_dir)/$(subst .,/,$(package))/R.java
classes     := $(foreach java,$(sources),$(patsubst $(src_dir)%.java,$(cls_dir)%.class,$(java)))
libraries   := $(shell find $(lib_dir) -name '*.jar')

# Tools
aapt        := $(ANDROID_HOME)/build-tools/$(build_tools)/aapt
javac       := javac
dx          := java -jar $(ANDROID_HOME)/build-tools/$(build_tools)/lib/dx.jar
jarsigner   := jarsigner
zipalign    := $(ANDROID_HOME)/build-tools/$(build_tools)/zipalign
adb         := $(ANDROID_HOME)/platform-tools/adb

keystore    := $(subst \,/,$(USERPROFILE))/.android/debug.keystore
dev_null    := NUL

# Final signed and zipaligned APK
# sign unaligned apk before zipaligning (not after packaging) for better error handling
$(out_dir)/$(project).apk: $(out_dir)/$(project)-unaligned.apk
	@echo -n Signing the APK...
	@$(jarsigner) \
		-keystore $(keystore) \
		-storepass android \
		-keypass android \
		$< \
		androiddebugkey \
		> $(dev_null)
	@echo Done.
	@echo -n Zipaligning...
	@$(zipalign) -f 4 $< $@
	@echo Done.

# Package APK
$(out_dir)/$(project)-unaligned.apk: $(out_dir) AndroidManifest.xml $(resources) $(int_dir)/classes.dex
	@echo -n Packaging...
	@$(aapt) package -f \
		-M AndroidManifest.xml \
		-I $(ANDROID_HOME)/platforms/$(platform)/android.jar \
		-S $(res_dir) \
		-F $@
	@cd $(int_dir) && $(aapt) add $(abspath $@) classes.dex > $(dev_null)
	@echo Done.

# Assemble classes to classes.dex by dx
$(int_dir)/classes.dex: $(classes)
	@echo -n Generating classes.dex...
	@$(dx) \
		--dex \
		--output=$@ \
		$(cls_dir) $(lib_dir)
	@echo Done.

# Compile by java
$(classes): $(cls_dir) $(sources) $(generated) $(libraries)
	@echo -n Compiling with javac...
	@$(javac) \
		-cp "$(ANDROID_HOME)/platforms/$(platform)/android.jar$(foreach lib,$(libraries),;$(lib)) ;$(gen_dir)" \
		-d $(cls_dir) \
		$(sources)
	@echo Done.

# Generate R.java by aapt based on the manifest and resources
# '-f' force overwrite
# '-M' manifest
# '-I' add package to base include set
# '-S' find resources here
# '-J' put R.java here
# '-m' create directories for R.java if needed
$(generated): $(gen_dir) AndroidManifest.xml $(resources)
	@echo -n Generating R.java... 
	@$(aapt) package -f \
		-M AndroidManifest.xml \
		-I $(ANDROID_HOME)/platforms/$(platform)/android.jar \
		-S $(res_dir) \
		-J $(gen_dir) \
		-m
	@echo Done.

# Subfolders in build/
$(gen_dir) $(out_dir) $(int_dir) $(cls_dir):
	@mkdir -p $@

.PHONY: clean
clean:
	rm -rf build
	#rm $(project).apk

.PHONY: install
install: $(out_dir)/$(project).apk
	adb install -r $<

.PHONY: uninstall
uninstall:
	adb uninstall $(package)

.PHONY: run
run: install
	adb shell input keyevent KEYCODE_WAKEUP
	adb shell am start $(package)/.MainActivity
