include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = KBEditToolbarPrefs

KBEditToolbarPrefs_FILES = KBETRootListController.m
KBEditToolbarPrefs_INSTALL_PATH = /Library/PreferenceBundles
KBEditToolbarPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
KBEditToolbarPrefs_PRIVATE_FRAMEWORKS = Preferences
KBEditToolbarPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/KBEditToolbarPrefs.plist$(ECHO_END)
