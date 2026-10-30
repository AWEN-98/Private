TARGET := iphone:clang:10.3:8.0
ARCHS := armv7
export ARCHS
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = DouyinLite
DouyinLite_FILES = main.m DLBrowserController.m DLAccountSession.m DLLoginController.m DLRemoteBrowserController.m
DouyinLite_FRAMEWORKS = UIKit Foundation AVFoundation WebKit JavaScriptCore Security CoreImage
DouyinLite_CFLAGS = -fobjc-arc -fblocks -Wno-deprecated-declarations
DouyinLite_LDFLAGS = -Wl,-U,_objc_msgSend_stret
DouyinLite_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
