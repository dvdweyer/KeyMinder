# SPDX-License-Identifier: GPL-3.0-or-later
cask "keyminder" do
  version "1.0.175"
  sha256 "c0c8d49a3545276e65436269c383ac18fbaca1f70ea90ad627cbb7a26d577bfc"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
