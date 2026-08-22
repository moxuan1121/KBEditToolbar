include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = KBEditToolbarPrefs

KBEditToolbarPrefs_FILES = KBETRootListController.m
KBEditToolbarPrefs_INSTALL_PATH = /Library/PreferenceBundles
KBEditToolbarPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
KBEditToolbarPrefs_CFLAGS = -fobjc-arc -Os -ffunction-sections -fdata-sections
# Public CI SDKs omit the private Preferences.framework binary. Settings has
# already loaded it before PreferenceLoader opens this bundle, so resolve the
# PSListController symbols from the host process at runtime.
KBEditToolbarPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-dead_strip

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/KBEditToolbarPrefs.plist$(ECHO_END)
