cask "keyminder" do
  version "1.0.118"
  sha256 "f8b89d97c057ba6dac3680faeb896906d2f8766822ab770d8fddd1719df9e834"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
