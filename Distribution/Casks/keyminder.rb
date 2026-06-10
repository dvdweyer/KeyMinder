cask "keyminder" do
  version "1.0.108"
  sha256 "4b1f03d0f3549477f55d5ce115fa772798d2756e410e7f5ab5015de318c88b53"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
