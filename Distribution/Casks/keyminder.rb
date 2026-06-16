# SPDX-License-Identifier: GPL-3.0-or-later
cask "keyminder" do
  version "1.0.153"
  sha256 "7057d5e5973c743915724d361b7e4983c964dc6938e1f763d776b2ab549e197e"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
