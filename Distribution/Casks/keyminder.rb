cask "keyminder" do
  version "1.0.111"
  sha256 "6fe403c2d62167b4821e7b3a59cf1de1af3ac92502b419e53de131134e2010d6"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
