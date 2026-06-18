# SPDX-License-Identifier: GPL-3.0-or-later
cask "keyminder" do
  version "1.0.157"
  sha256 "9e602c21e911d4da8e0518a352a672da7314faa7aa13c58e0af9ef6deaa3c364"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
