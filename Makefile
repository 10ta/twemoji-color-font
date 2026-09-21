# Makefile to create all versions of the Twitter Color Emoji SVGinOT font
# Run with: make -j [NUMBER_OF_CPUS]

# Use Linux Shared Memory to avoid wasted disk writes. Use /tmp to disable.
TMP := /dev/shm
#TMP := /tmp

# Where to find scfbuild?
SCFBUILD := SCFBuild/bin/scfbuild

# Upstream twemoji repo; the font version always follows its latest release tag.
UPSTREAM_REPO := https://github.com/jdecked/twemoji.git

# VERSION can be passed in (make VERSION=17.0.3, or the VERSION env var set by CI).
# Otherwise query the latest vX.Y.Z tag from upstream (git ls-remote, no API rate limit).
# `export` makes the value flow into recursive $(MAKE) calls so it is only resolved once.
ifndef VERSION
VERSION := $(shell git ls-remote --tags --refs --sort=-v:refname $(UPSTREAM_REPO) 'v*' \
	| sed -n 's|.*refs/tags/v\([0-9]\+\.[0-9]\+\.[0-9]\+\)$$|\1|p' | head -n1)
endif
ifeq ($(strip $(VERSION)),)
  $(error Could not determine VERSION from $(UPSTREAM_REPO); pass it explicitly: make VERSION=x.y.z)
endif
export VERSION

# Debian packaging: revision and changelog identity for the auto-generated entry.
DEB_REVISION ?= 1
DEB_VERSION := $(VERSION)-$(DEB_REVISION)
DEB_DISTRIBUTION ?= bionic
export DEBFULLNAME ?= GitHub Actions
export DEBEMAIL ?= actions@users.noreply.github.com
FONT_PREFIX := TwitterColorEmoji-SVGinOT
REGULAR_FONT := build/$(FONT_PREFIX).ttf
REGULAR_PACKAGE := build/$(FONT_PREFIX)-$(VERSION)
MACOS_FONT := build/$(FONT_PREFIX)-MacOS.ttf
MACOS_PACKAGE := build/$(FONT_PREFIX)-MacOS-$(VERSION)
LINUX_PACKAGE := $(FONT_PREFIX)-Linux-$(VERSION)
DEB_PACKAGE := fonts-twemoji-svginot
WINDOWS_TOOLS := windows

# COLRv0 font (like Mozilla's Twemoji Mozilla): color in Chrome, Firefox and
# native Windows/Linux/Android apps. Built with nanoemoji from the same SVGs.
NANOEMOJI ?= nanoemoji
COLR_FAMILY ?= Twemoji
COLR_FONT := build/Twemoji-$(VERSION).ttf
COLR_SRC := build/colr-src
COLR_BUILD := build/colr-build
WINDOWS_PACKAGE := build/$(FONT_PREFIX)-Win-$(VERSION)
# nanoemoji's ninja build calls `picosvg` and `ninja` by name, so the directory
# holding nanoemoji (e.g. a venv's bin/) must be on PATH while it runs.
NANOEMOJI_DIR = $(abspath $(dir $(shell command -v $(NANOEMOJI))))

ifeq (, $(shell which inkscape))
  $(error "No inkscape in PATH, it is required for fallback b/w variant.")
endif

ifeq (0, $(shell inkscape --export-png 1>&2 2> /dev/null; echo $$?))
  # Inkscape < 1.0
  INKSCAPE_EXPORT_FLAGS := --without-gui --export-png
else
  # Inkscape ≥ 1.0
  INKSCAPE_EXPORT_FLAGS := --export-filename
endif

# There are two SVG source directories to keep the assets separate
# from the additions
SVG_TWEMOJI := assets/twemoji-svg
# Currently empty
SVG_EXTRA := assets/svg
# B&W only glyphs which will not be processed.
SVG_EXTRA_BW := assets/svg-bw

# Create the lists of traced and color SVGs
SVG_FILES := $(wildcard $(SVG_TWEMOJI)/*.svg) $(wildcard $(SVG_EXTRA)/*.svg)
SVG_STAGE_FILES := $(patsubst $(SVG_TWEMOJI)/%.svg, build/stage/%.svg, $(SVG_FILES))
SVG_STAGE_FILES := $(patsubst $(SVG_EXTRA)/%.svg, build/stage/%.svg, $(SVG_STAGE_FILES))
SVG_BW_FILES := $(patsubst build/stage/%.svg, build/svg-bw/%.svg, $(SVG_STAGE_FILES))
SVG_COLOR_FILES := $(patsubst build/stage/%.svg, build/svg-color/%.svg, $(SVG_STAGE_FILES))

CPU_CORES := $(shell cat /proc/cpuinfo | grep processor | wc -l)

.PHONY: all update print-version colr-package package regular-package linux-package macos-package windows-package copy-extra clean

all: package

# Run the build concurrently against all available cores
fast:
	$(MAKE) -j $(CPU_CORES)

# Sync SVG assets from upstream at tag v$(VERSION).
# Uses a shallow sparse clone so only assets/svg is downloaded.
update:
	rm -rf build/upstream
	git -c advice.detachedHead=false clone --quiet --depth 1 --branch v$(VERSION) --filter=blob:none --sparse \
		$(UPSTREAM_REPO) build/upstream
	git -C build/upstream sparse-checkout set assets/svg
	rm -f $(SVG_TWEMOJI)/*.svg
	cp build/upstream/assets/svg/*.svg $(SVG_TWEMOJI)/
	rm -rf build/upstream

print-version:
	@echo $(VERSION)

# Create the operating system specific packages
package: regular-package linux-package deb-package macos-package windows-package colr-package

regular-package: $(REGULAR_FONT)
	rm -f $(REGULAR_PACKAGE).zip
	rm -rf $(REGULAR_PACKAGE)
	mkdir $(REGULAR_PACKAGE)
	cp $(REGULAR_FONT) $(REGULAR_PACKAGE)
	cp LICENSE* $(REGULAR_PACKAGE)
	cp README.md $(REGULAR_PACKAGE)
	7z a -tzip -mx=9 $(REGULAR_PACKAGE).zip ./$(REGULAR_PACKAGE)

linux-package: $(REGULAR_FONT)
	rm -f build/$(LINUX_PACKAGE).tar.gz
	rm -rf build/$(LINUX_PACKAGE)
	mkdir build/$(LINUX_PACKAGE)
	cp $(REGULAR_FONT) build/$(LINUX_PACKAGE)
	cp LICENSE* build/$(LINUX_PACKAGE)
	cp README.md build/$(LINUX_PACKAGE)
	cp -R linux/* build/$(LINUX_PACKAGE)
	tar zcvf build/$(LINUX_PACKAGE).tar.gz -C build $(LINUX_PACKAGE)

deb-package: linux-package
	rm -rf build/$(DEB_PACKAGE)-$(VERSION)
	cp build/$(LINUX_PACKAGE).tar.gz build/$(DEB_PACKAGE)_$(VERSION).orig.tar.gz
	cp -R build/$(LINUX_PACKAGE) build/$(DEB_PACKAGE)-$(VERSION)
	# Prepend a changelog entry if debian/changelog lags behind $(VERSION).
	# Only the copy in build/ is modified; linux/debian/changelog stays untouched.
	cd build/$(DEB_PACKAGE)-$(VERSION) && \
	if [ "$$(dpkg-parsechangelog -S Version)" != "$(DEB_VERSION)" ]; then \
		dch --preserve --newversion "$(DEB_VERSION)" \
			--distribution "$(DEB_DISTRIBUTION)" --force-distribution \
			"Update to twemoji $(VERSION)."; \
	fi
	cd build/$(DEB_PACKAGE)-$(VERSION) && debuild --no-tgz-check -us -uc
	# cd build/$(DEB_PACKAGE)-$(VERSION); debuild -S
	# cd build dput ppa:eosrei/fonts $(DEB_PACKAGE)_$(VERSION)_source.changes

colr-package: $(COLR_FONT)

$(COLR_FONT): $(wildcard $(SVG_TWEMOJI)/*.svg) tools/colr_sources.py | build
	python3 tools/colr_sources.py $(SVG_TWEMOJI) $(COLR_SRC)
	rm -rf $(COLR_BUILD)
	PATH="$(NANOEMOJI_DIR):$$PATH" $(NANOEMOJI) --color_format glyf_colr_0 \		--family "$(COLR_FAMILY)" \
		--version_major $(word 1,$(subst ., ,$(VERSION))) \
		--version_minor $(shell printf '%d%02d' $(word 2,$(subst ., ,$(VERSION))) $(word 3,$(subst ., ,$(VERSION)))) \
		--build_dir $(COLR_BUILD) \
		--output_file $(notdir $@) \
		$(COLR_SRC)/*.svg
	mv $(COLR_BUILD)/$(notdir $@) $@

macos-package: $(MACOS_FONT)
	rm -f $(MACOS_PACKAGE).zip
	rm -rf $(MACOS_PACKAGE)
	mkdir $(MACOS_PACKAGE)
	cp $(MACOS_FONT) $(MACOS_PACKAGE)
	cp LICENSE* $(MACOS_PACKAGE)
	cp README.md $(MACOS_PACKAGE)
	7z a -tzip -mx=9 $(MACOS_PACKAGE).zip ./$(MACOS_PACKAGE)

windows-package: $(REGULAR_FONT)
	rm -f $(WINDOWS_PACKAGE).zip
	rm -rf $(WINDOWS_PACKAGE)
	mkdir $(WINDOWS_PACKAGE)
	cp $(REGULAR_FONT) $(WINDOWS_PACKAGE)
	cp LICENSE* $(WINDOWS_PACKAGE)
	cp README.md $(WINDOWS_PACKAGE)
	cp $(WINDOWS_TOOLS)/* $(WINDOWS_PACKAGE)
	7z a -tzip -mx=9 $(WINDOWS_PACKAGE).zip ./$(WINDOWS_PACKAGE)

# Build both versions of the fonts
$(REGULAR_FONT): $(SVG_BW_FILES) $(SVG_COLOR_FILES) copy-extra
	$(SCFBUILD) -c scfbuild.yml -o $(REGULAR_FONT) --font-version="$(VERSION)"

$(MACOS_FONT): $(SVG_BW_FILES) $(SVG_COLOR_FILES) copy-extra
	$(SCFBUILD) -c scfbuild-macos.yml -o $(MACOS_FONT) --font-version="$(VERSION)"

copy-extra: build/svg-bw
	cp $(SVG_EXTRA_BW)/* build/svg-bw/

# Create black SVG traces of the color SVGs to use as glyphs.
# 1. Make the Twemoji SVG into a PNG with Inkscape
# 2. Make the PNG into a BMP with ImageMagick and add margin by increasing the
#    canvas size to allow the outer "stroke" to fit.
# 3. Make the BMP into a Edge Detected PGM with mkbitmap
# 4. Make the PGM into a black SVG trace with potrace
build/svg-bw/%.svg: build/staging/%.svg | build/svg-bw
	inkscape -w 1000 -h 1000 $(INKSCAPE_EXPORT_FLAGS) $(TMP)/$(*F).png $<
	convert $(TMP)/$(*F).png -gravity center -extent 1066x1066 $(TMP)/$(*F).bmp
	rm $(TMP)/$(*F).png
	mkbitmap -g -s 1 -f 10 -o $(TMP)/$(*F).pgm $(TMP)/$(*F).bmp
	rm $(TMP)/$(*F).bmp
	potrace --flat -s --height 2048pt --width 2048pt -o $@ $(TMP)/$(*F).pgm
	rm $(TMP)/$(*F).pgm

# Optimize/clean the color SVG files
build/svg-color/%.svg: build/staging/%.svg | build/svg-color
	svgo -i $< -o $@

# Copy the files from multiple directories into one source directory
build/staging/%.svg: $(SVG_TWEMOJI)/%.svg | build/staging
	cp $< $@

build/staging/%.svg: $(SVG_MORE)/%.svg | build/staging
	cp $< $@

# Create the build directories
build:
	mkdir build

build/staging: | build
	mkdir build/staging

build/svg-bw: | build
	mkdir build/svg-bw

build/svg-color: | build
	mkdir build/svg-color

clean:
	rm -rf build