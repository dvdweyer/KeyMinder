# SPDX-License-Identifier: GPL-3.0-or-later
cask "keyminder" do
  version "1.0.175"
  sha256 "ffc0339469688249dfd0416e0979ca01fd95a720cfd055f3978114c48bac8d16"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
