export ARCHS = arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KBEditToolbar

KBEditToolbar_FILES = Tweak.x
KBEditToolbar_INSTALL_PATH = /usr/lib/TweakInject
KBEditToolbar_CFLAGS = -fobjc-arc -Os -ffunction-sections -fdata-sections
KBEditToolbar_LDFLAGS = -Wl,-dead_strip
KBEditToolbar_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
