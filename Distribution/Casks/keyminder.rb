cask "keyminder" do
  version "1.0.107"
  sha256 "595b11dab6c51d8c58ed05c0bd0371c5966af145701d9add92b7e61d934ef3f0"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
