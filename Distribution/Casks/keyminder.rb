cask "keyminder" do
  version "0.1.105"
  sha256 "6f569ce5a10fd1bb6aeae14b0c0f8e6c52fc2ff9ea99737ad9daf2b0dd439d4c"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
