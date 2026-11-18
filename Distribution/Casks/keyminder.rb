# SPDX-License-Identifier: GPL-3.0-or-later
cask "keyminder" do
  version "1.0.228"
  sha256 "f1f86fa19affa9b7480740e619f60b58e984e1ca8cb8a99fec87e7960b4bb19c"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: [
    "~/Library/Preferences/org.afaik.KeyMinder.plist",
    "~/Library/SyncedPreferences/org.afaik.KeyMinder*.plist",
  ]
end
