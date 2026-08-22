export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KBEditToolbar

KBEditToolbar_FILES = Tweak.x
KBEditToolbar_CFLAGS = -fobjc-arc
KBEditToolbar_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
