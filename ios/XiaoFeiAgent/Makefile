TARGET = iphone:clang:9.3:8.0
ARCHS = armv7
APPLICATION_NAME = XiaoFeiAgent
XiaoFeiAgent_FILES = main.m XFAppDelegate.m XFViewController.m XFModelsController.m XFChatStore.m XFHistoryController.m XFChatView.m XFModelProbe.m XFTextImportController.m XFPromptToolsController.m XFCompareController.m XFDiagnostics.m XFJarvisController.m XFImageGeneration.m
XiaoFeiAgent_FRAMEWORKS = UIKit Foundation AVFoundation AudioToolbox QuartzCore Security
XiaoFeiAgent_RESOURCE_DIRS = Resources
XiaoFeiAgent_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/application.mk
