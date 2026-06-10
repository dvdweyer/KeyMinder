cask "keyminder" do
  version "1.0.111"
  sha256 "0d523cbacea5df3718d8c9b5228704f97de957a8ab0226c0138f265c65c2bb42"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
