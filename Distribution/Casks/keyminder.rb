cask "keyminder" do
  version "1.0.122"
  sha256 "4b599852a764e24e1572b4237ee80daee356c59995b37508b260cb1a7bb5f4a9"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: :sonoma

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
