cask "keyminder" do
  version "0.1.106"
  sha256 "eacc84727884250920954d43c024426eacf2c7c03b8839f6a451cf2467101bcd"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
