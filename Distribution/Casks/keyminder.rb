# SPDX-License-Identifier: GPL-3.0-or-later
cask "keyminder" do
  version "1.0.130"
  sha256 "2acd8faaca6b958d66dbdbf3c5fb2c92592e9a3e7249cab19e5f419dda6e773e"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
