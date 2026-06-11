cask "keyminder" do
  version "1.0.115"
  sha256 "b56e4f0b5e3fe5eed672db44811d13371cfeae0e79230b33267cc674664d7199"

  url "https://keyminder.app/KeyMinder_#{version}.dmg"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
