include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for WFB-ng
LUCI_DEPENDS:=+wfb-ng-full +luci-base +luci-lib-nixio
LUCI_PKGARCH:=all
PKG_MAINTAINER:=wfb-ng developers

include $(TOPDIR)/feeds/luci/luci.mk

$(call BuildPackage,luci-app-wfb-ng)
