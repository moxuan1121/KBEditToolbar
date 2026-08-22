export ARCHS = arm64e
export TARGET = iphone:clang:latest:14.0
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KBEditToolbar

KBEditToolbar_FILES = Tweak.x
KBEditToolbar_CFLAGS = -fobjc-arc -Os -ffunction-sections -fdata-sections
KBEditToolbar_LDFLAGS = -Wl,-dead_strip
KBEditToolbar_FRAMEWORKS = UIKit Foundation CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += kbedittoolbarprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
