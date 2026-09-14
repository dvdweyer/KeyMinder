# SPDX-License-Identifier: GPL-3.0-or-later
cask "keyminder" do
  version "1.0.195"
  sha256 "f277ec2092c9e38de42603244c220c0cf3d719fd0e63a45d663b9eb0f8cf7241"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
