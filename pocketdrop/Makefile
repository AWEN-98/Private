export TARGET = iphone:clang:10.3:8.0
export ARCHS = armv7
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = PocketDrop
PocketDrop_FILES = main.m
PocketDrop_FRAMEWORKS = UIKit Foundation
PocketDrop_CFLAGS = -fobjc-arc -Wall -Wno-unused-parameter
PocketDrop_INSTALL_PATH = /Applications
include $(THEOS_MAKE_PATH)/application.mk
